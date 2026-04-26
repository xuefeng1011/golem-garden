<script setup lang="ts">
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

export interface CatalogEntry {
  command: string
  description: string
}

const props = defineProps<{
  selectedCommand: string
}>()

const emit = defineEmits<{
  (e: 'select', command: string): void
}>()

const CATEGORIES: Record<string, string[]> = {
  '상태': ['status', 'souls', 'rank', 'dashboard', 'overview', 'ov'],
  '빌드': ['build', 'quick', 'assign'],
  '리뷰': ['review', 'sync'],
  '운영': ['session', 'mailbox', 'worktree', 'recover'],
  '분석': ['insights', 'memory', 'retro', 'chemistry', 'achievement', 'skill-tree', 'dna', 'budget', 'tool-char'],
  '관리': ['soul-create', 'pack', 'skill-export', 'skill-import', 'log-add'],
}

const DESCRIPTIONS: Record<string, string> = {
  status: '팀 상태 + SOUL 랭크',
  souls: '등록된 SOUL 목록',
  rank: '랭크 분포 요약',
  dashboard: '성장 대시보드',
  overview: '통합 개요 (팀/성과/비용)',
  ov: '통합 개요 단축',
  build: '팀 전체 빌드 실행',
  quick: '단독 SOUL 빌드',
  assign: '지정 SOUL에 태스크 배정',
  review: '크로스 리뷰 실행',
  sync: '지식 승격 심사',
  session: '세션 생성/재개/상태',
  mailbox: '메일박스 현황/전송',
  worktree: 'SOUL별 격리 worktree',
  recover: '3단계 에러 복구',
  insights: '팀 성과 패턴 분석',
  memory: 'SOUL 학습 기억 현황',
  retro: '자동 회고',
  chemistry: '팀 케미 대시보드',
  achievement: '업적/뱃지 대시보드',
  'skill-tree': '전문화 분기 현황',
  dna: '프로젝트 DNA 조회',
  budget: '예산 상태',
  'tool-char': '도구 성격 가이드',
  'soul-create': '새 SOUL 생성',
  pack: 'SOUL 팩 관리',
  'skill-export': 'SOUL → Agent Skill 내보내기',
  'skill-import': 'Agent Skill → SOUL 임포트',
  'log-add': '성장 기록 추가',
}
</script>

<template>
  <div class="catalog">
    <div class="catalog-title">{{ t('forge.catalogTitle') }}</div>
    <div
      v-for="(commands, category) in CATEGORIES"
      :key="category"
      class="catalog-group"
    >
      <div class="group-label">{{ category }}</div>
      <button
        v-for="cmd in commands"
        :key="cmd"
        class="cmd-item"
        :class="{ active: props.selectedCommand === cmd }"
        @click="emit('select', cmd)"
      >
        <span class="cmd-name">{{ cmd }}</span>
        <span class="cmd-desc">{{ DESCRIPTIONS[cmd] ?? '' }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.catalog {
  display: flex;
  flex-direction: column;
  gap: 4px;
  overflow-y: auto;
  height: 100%;
  padding-right: 4px;
}

.catalog-title {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  padding: 0 8px 6px;
}

.catalog-group {
  display: flex;
  flex-direction: column;
  gap: 1px;
  margin-bottom: 6px;
}

.group-label {
  font-size: 10px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  padding: 6px 8px 3px;
}

.cmd-item {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 1px;
  padding: 7px 10px;
  border: none;
  background: none;
  border-radius: $radius-sm;
  cursor: pointer;
  width: 100%;
  text-align: left;
  transition: background $transition-fast;

  &:hover {
    background-color: rgba(var(--accent-primary-rgb), 0.06);
  }

  &.active {
    background-color: rgba(var(--accent-primary-rgb), 0.14);

    .cmd-name {
      color: $accent-primary;
    }
  }
}

.cmd-name {
  font-size: 13px;
  font-weight: 500;
  color: $text-primary;
  font-family: $font-code;
}

.cmd-desc {
  font-size: 11px;
  color: $text-muted;
  line-height: 1.3;
}
</style>
