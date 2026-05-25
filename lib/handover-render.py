#!/usr/bin/env python3
"""
handover-render.py — 단일 HTML 빌더 (M3 업그레이드)

Usage:
    python lib/handover-render.py <src_dir> <output_html>

    <src_dir>   : handover-scan.sh 가 생성한 00-overview.md ~ 07-people.md 포함 디렉토리
    <output_html>: 출력할 단일 HTML 파일 경로

의존성:
    pip install markdown
    또는 uv pip install markdown

M3 추가 기능:
    - path:line 패턴 → vscode://file 자동 링크 변환 (post-process, code block 제외)
    - 검색 인덱스 JSON 빌드 (window.SEARCH_INDEX) — Ctrl+K 검색용
    - h2/h3 heading에 id 자동 부여 (anchor 링크용)
    - {{SEARCH_INDEX_JSON}}, {{CWD}} placeholder 지원
"""

from __future__ import annotations

import sys
import os
import re
import glob
import json
import html as html_module
from datetime import datetime, timezone
from pathlib import Path

# ── markdown 라이브러리 확인 ──────────────────────────────
try:
    import markdown
    from markdown.extensions import fenced_code, tables, toc, nl2br
except ImportError:
    print(
        "[ERROR] 'markdown' 라이브러리 필요. 설치:\n"
        "  pip install markdown\n"
        "  또는 uv pip install markdown",
        file=sys.stderr,
    )
    sys.exit(1)


# ── 섹션 메타데이터 ────────────────────────────────────────
SECTION_META = {
    "00-overview":    {"num": "00", "title": "프로젝트 개요"},
    "01-architecture":{"num": "01", "title": "아키텍처"},
    "02-directory":   {"num": "02", "title": "디렉토리 구조"},
    "03-dev-guide":   {"num": "03", "title": "개발 환경 가이드"},
    "04-pitfalls":    {"num": "04", "title": "함정 & 주의사항"},
    "05-checklist":   {"num": "05", "title": "온보딩 체크리스트"},
    "06-glossary":    {"num": "06", "title": "용어 사전"},
    "07-people":      {"num": "07", "title": "팀 / People"},
}

# 코드 링크 정규식: path/to/file.ext:123 또는 path/to/file.ext:123-145
_CODE_REF_RE = re.compile(
    r'(?<!\.)\b([a-zA-Z_][a-zA-Z0-9\-_./]*\.[\w]+):(\d+)(?:-(\d+))?\b'
)

# HTML 태그 제거용 (검색 인덱스 텍스트 평탄화)
_HTML_TAG_RE = re.compile(r'<[^>]+>')

# 마크다운 문법 제거용 (검색 인덱스용 raw 텍스트)
_MD_SYNTAX_RE = re.compile(
    r'(\*{1,3}|_{1,3}|~~|`{1,3})'  # 강조/코드
    r'|!\[.*?\]\(.*?\)'              # 이미지
    r'|\[([^\]]*)\]\([^)]*\)'        # 링크 → 텍스트만
    r'|^#{1,6}\s+'                   # 헤딩 마커
    r'|^>\s+'                        # blockquote
    r'|^[-*+]\s+'                    # 목록 마커
    r'|^\d+\.\s+',                   # 번호 목록
    re.MULTILINE,
)


def _load_template(src_dir: str) -> str:
    """base.html 템플릿 로드 — 스크립트 위치 기준으로 탐색."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(script_dir, "handover-templates", "base.html"),
        os.path.join(src_dir, "..", "handover-templates", "base.html"),
    ]
    for path in candidates:
        path = os.path.normpath(path)
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                return f.read()
    raise FileNotFoundError(
        f"base.html 템플릿을 찾을 수 없습니다. 탐색 경로:\n"
        + "\n".join(f"  {p}" for p in candidates)
    )


def _md_to_html(md_text: str) -> str:
    """마크다운 → HTML 변환. 코드 펜스, 테이블, 체크리스트 지원."""
    md = markdown.Markdown(
        extensions=[
            "fenced_code",
            "tables",
            "nl2br",
            "sane_lists",
        ],
        extension_configs={},
        output_format="html",
    )
    # 체크리스트 [ ] / [x] 처리 (markdown 라이브러리 기본 미지원 → 수동 치환)
    result = md.convert(md_text)
    result = result.replace(
        "<li>[ ] ", '<li><input type="checkbox" disabled> '
    ).replace(
        "<li>[x] ", '<li><input type="checkbox" disabled checked> '
    ).replace(
        "<li>[X] ", '<li><input type="checkbox" disabled checked> '
    )
    return result


def _section_id(stem: str) -> str:
    """파일 스템(예: '00-overview') → HTML anchor id."""
    return stem.replace(".", "-")


def _collect_md_files(src_dir: str) -> list[str]:
    """src_dir 안의 *.md 파일을 알파벳 순으로 반환."""
    pattern = os.path.join(src_dir, "*.md")
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"[WARN] {src_dir} 에서 .md 파일을 찾을 수 없습니다.", file=sys.stderr)
    return files


def _build_toc(stems: list[str]) -> str:
    """사이드바 목차 <li> HTML 생성."""
    lines: list[str] = []
    for stem in stems:
        sid = _section_id(stem)
        meta = SECTION_META.get(stem, {"num": "??", "title": stem})
        num = meta["num"]
        title = meta["title"]
        lines.append(
            f'          <li><a href="#{sid}">'
            f'<span class="section-num">{num}</span>{title}</a></li>'
        )
    return "\n".join(lines)


def _assign_heading_ids(html_body: str, section_id: str) -> str:
    """
    h2/h3 태그에 id 자동 부여. anchor 링크 + 검색 인덱스에서 사용.
    id 형식: section-{section_id}-h{level}-{1-based-index}
    """
    h2_counter = 0
    h3_counter = 0

    def _replace_heading(m: re.Match) -> str:
        nonlocal h2_counter, h3_counter
        level = int(m.group(1))
        existing_attrs = m.group(2) or ""
        content = m.group(3)

        if level == 2:
            h2_counter += 1
            idx = h2_counter
        else:  # h3
            h3_counter += 1
            idx = h3_counter

        heading_id = f"section-{section_id}-h{level}-{idx}"
        # 기존 id 속성이 있으면 교체, 없으면 추가
        if "id=" in existing_attrs:
            new_attrs = re.sub(r'id="[^"]*"', f'id="{heading_id}"', existing_attrs)
        else:
            new_attrs = f' id="{heading_id}"' + (existing_attrs or "")
        return f"<h{level}{new_attrs}>{content}</h{level}>"

    pattern = re.compile(r'<h([23])([^>]*)>(.*?)</h\1>', re.DOTALL)
    return pattern.sub(_replace_heading, html_body)


def _split_html_on_code_blocks(html: str) -> list[tuple[str, bool]]:
    """
    HTML을 code/pre 블록 안팎으로 분리.
    반환: [(text, is_code_block), ...] 리스트
    is_code_block=True 이면 <pre> 또는 <code> 안 영역
    """
    segments: list[tuple[str, bool]] = []
    # <pre...>...</pre> 와 <code...>...</code> 를 보호 영역으로 추출
    code_block_re = re.compile(
        r'(<pre[^>]*>.*?</pre>|<code[^>]*>.*?</code>)',
        re.DOTALL | re.IGNORECASE,
    )
    last = 0
    for m in code_block_re.finditer(html):
        start, end = m.span()
        if start > last:
            segments.append((html[last:start], False))
        segments.append((html[start:end], True))
        last = end
    if last < len(html):
        segments.append((html[last:], False))
    return segments


def _link_code_refs(html_body: str, cwd: str) -> tuple[str, int]:
    """
    HTML에서 path:line 또는 path:start-end 패턴을 vscode://file 링크로 변환.
    <code>, <pre> 블록 안의 패턴은 건드리지 않음.

    반환: (변환된 html, 링크 변환 카운트)
    """
    segments = _split_html_on_code_blocks(html_body)
    link_count = 0

    def _replace_ref(m: re.Match) -> str:
        nonlocal link_count
        path_part = m.group(1)
        start_line = m.group(2)
        end_line = m.group(3)  # None 이면 단일 라인

        # abs_path 조립 (cwd 기반)
        abs_path = os.path.join(cwd, path_part).replace("\\", "/")

        # href: vscode://file/{abs_path}:{start_line}
        href = f"vscode://file/{abs_path}:{start_line}"

        # 표시 텍스트 (HTML escape)
        if end_line:
            display = html_module.escape(f"{path_part}:{start_line}-{end_line}")
        else:
            display = html_module.escape(f"{path_part}:{start_line}")

        link_count += 1
        return (
            f'<a class="code-link" href="{href}" '
            f'title="VS Code에서 열기">{display}</a>'
        )

    result_parts: list[str] = []
    for segment_text, is_code in segments:
        if is_code:
            result_parts.append(segment_text)
        else:
            result_parts.append(_CODE_REF_RE.sub(_replace_ref, segment_text))

    return "".join(result_parts), link_count


def _strip_md_syntax(text: str) -> str:
    """마크다운 문법 기호 제거 — 링크는 텍스트만, 나머지 마커 제거."""
    def _replace_md(m: re.Match) -> str:
        # 링크 [text](url) → text 만 유지
        if m.group(2) is not None:
            return m.group(2)
        return ""
    return _MD_SYNTAX_RE.sub(_replace_md, text)


def _strip_html_tags(text: str) -> str:
    """HTML 태그 제거."""
    return _HTML_TAG_RE.sub("", text)


def _extract_headings_from_md(md_text: str, section_id: str) -> list[dict]:
    """
    마크다운 raw 텍스트에서 h2/h3 헤딩 추출.
    반환: [{"level": 2, "text": "...", "anchor": "section-{id}-h2-1"}, ...]
    """
    headings: list[dict] = []
    h2_count = 0
    h3_count = 0
    for line in md_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("## "):
            h2_count += 1
            text = stripped[3:].strip()
            headings.append({
                "level": 2,
                "text": text,
                "anchor": f"section-{section_id}-h2-{h2_count}",
            })
        elif stripped.startswith("### "):
            h3_count += 1
            text = stripped[4:].strip()
            headings.append({
                "level": 3,
                "text": text,
                "anchor": f"section-{section_id}-h3-{h3_count}",
            })
    return headings


def _md_to_plain_text(md_text: str) -> str:
    """마크다운 → 검색용 평탄화 텍스트."""
    # 먼저 마크다운 → HTML → 태그 제거
    md = markdown.Markdown(
        extensions=["fenced_code", "tables", "nl2br", "sane_lists"],
        output_format="html",
    )
    html_body = md.convert(md_text)
    text = _strip_html_tags(html_body)
    # 연속 공백/줄바꿈 정리
    text = re.sub(r'\s+', ' ', text).strip()
    return text


def _build_search_index(src_dir: str, stems: list[str]) -> list[dict]:
    """
    각 섹션에 대한 검색 인덱스 JSON 배열 생성.
    구조: [{"id", "title", "headings": [...], "text": "..."}, ...]
    """
    index: list[dict] = []
    for stem in stems:
        fpath = os.path.join(src_dir, f"{stem}.md")
        if not os.path.isfile(fpath):
            continue

        with open(fpath, encoding="utf-8") as f:
            md_text = f.read()

        sid = _section_id(stem)
        meta = SECTION_META.get(stem, {"num": "??", "title": stem})
        title = meta["title"]

        headings = _extract_headings_from_md(md_text, sid)
        plain_text = _md_to_plain_text(md_text)

        index.append({
            "id": sid,
            "title": title,
            "headings": headings,
            "text": plain_text,
        })

    return index


def _build_sections(
    files: list[str], cwd: str
) -> tuple[list[str], list[str], int]:
    """
    MD 파일 목록 → (stems, sections_html_list, total_link_count) 반환.
    각 section 은 <section id="..."> ... </section> 형태.
    heading id 자동 부여 + vscode 코드 링크 변환 포함.
    """
    stems: list[str] = []
    sections: list[str] = []
    total_links = 0

    for fpath in files:
        stem = os.path.splitext(os.path.basename(fpath))[0]
        stems.append(stem)
        sid = _section_id(stem)

        with open(fpath, encoding="utf-8") as f:
            md_text = f.read()

        body_html = _md_to_html(md_text)

        # h2/h3에 id 부여 (anchor + 검색 인덱스 연결)
        body_html = _assign_heading_ids(body_html, sid)

        # 코드 링크 변환 (code/pre 블록 보호)
        body_html, link_count = _link_code_refs(body_html, cwd)
        total_links += link_count

        section = (
            f'      <section id="{sid}" class="handover-section">\n'
            f"{body_html}\n"
            f"      </section>"
        )
        sections.append(section)

    return stems, sections, total_links


def render(src_dir: str, output_html: str) -> None:
    """메인 렌더링 함수."""
    src_dir = os.path.abspath(src_dir)
    output_html = os.path.abspath(output_html)
    cwd = os.environ.get("GOLEM_PROJECT", src_dir)
    # Windows 경로를 슬래시로 통일 (vscode://file 링크용)
    cwd = cwd.replace("\\", "/")

    if not os.path.isdir(src_dir):
        print(f"[ERROR] src_dir 디렉토리가 없습니다: {src_dir}", file=sys.stderr)
        sys.exit(1)

    # 출력 디렉토리 생성
    out_dir = os.path.dirname(output_html)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    # 템플릿 로드
    try:
        template = _load_template(src_dir)
    except FileNotFoundError as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        sys.exit(1)

    # MD 파일 수집 및 변환
    files = _collect_md_files(src_dir)
    stems, section_htmls, total_links = _build_sections(files, cwd)

    # 검색 인덱스 빌드
    search_index = _build_search_index(src_dir, stems)
    search_index_json = json.dumps(search_index, ensure_ascii=False, separators=(",", ":"))

    # 프로젝트 이름 추론 (1순위: GOLEM_PROJECT 환경변수, 2순위: src_dir 부모, 3순위: overview)
    _golem_proj = os.environ.get("GOLEM_PROJECT", "").strip()
    if _golem_proj:
        project_name = Path(_golem_proj).name or "Project"
    else:
        project_name = os.path.basename(os.path.dirname(src_dir))
        if not project_name or project_name in (".", ".."):
            project_name = "Project"

    # overview MD에서 프로젝트 이름 추출 시도
    overview_path = os.path.join(src_dir, "00-overview.md")
    if os.path.isfile(overview_path):
        with open(overview_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # "`project_name`" 패턴 찾기
                if line.count("`") == 2 and line.startswith("`") and line.endswith("`"):
                    candidate = line[1:-1].strip()
                    if candidate and " " not in candidate:
                        project_name = candidate
                        break

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    toc_html = _build_toc(stems)
    sections_html = "\n\n".join(section_htmls)

    # 템플릿 치환 (string.Template 미사용 — {{ }} 형식이므로 단순 replace)
    html = (
        template
        .replace("{{PROJECT_NAME}}", project_name)
        .replace("{{GENERATED_AT}}", generated_at)
        .replace("{{TOC_HTML}}", toc_html)
        .replace("{{SECTIONS_HTML}}", sections_html)
        .replace("{{SEARCH_INDEX_JSON}}", search_index_json)
        .replace("{{CWD}}", cwd)
    )

    with open(output_html, "w", encoding="utf-8") as f:
        f.write(html)

    file_size_kb = os.path.getsize(output_html) // 1024
    print(f"[handover-render] 완료 → {output_html} ({file_size_kb} KB)")
    print(f"[handover-render] 섹션 수: {len(stems)}")
    print(f"[handover-render] 코드 링크 변환: {total_links}개")
    print(f"[handover-render] 검색 인덱스 섹션: {len(search_index)}개")


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "Usage: python lib/handover-render.py <src_dir> <output_html>",
            file=sys.stderr,
        )
        sys.exit(1)

    src_dir = sys.argv[1]
    output_html = sys.argv[2]
    render(src_dir, output_html)


if __name__ == "__main__":
    main()
