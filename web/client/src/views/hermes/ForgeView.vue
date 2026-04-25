<script setup lang="ts">
import { ref, computed, watch, onUnmounted } from 'vue'
import { NButton, NAlert } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'
import type { ForgeCompletedEvent, ForgeFailedEvent } from '@/api/hermes/forge'
import CommandCatalog from '@/components/hermes/forge/CommandCatalog.vue'
import CommandRunner from '@/components/hermes/forge/CommandRunner.vue'
import type { OutputLine, RunResult } from '@/components/hermes/forge/CommandRunner.vue'

const { t } = useI18n()
const profilesStore = useProfilesStore()

// ── State ─────────────────────────────────────────────────────────

const selectedCommand = ref('status')
const outputLines = ref<OutputLine[]>([])
const lastResult = ref<RunResult | null>(null)
const running = ref(false)
const errorMsg = ref<string | null>(null)
let streamHandle: { abort: () => void } | null = null

interface HistoryEntry {
  command: string
  args: string[]
  exit_code: number | null
  duration_ms: number
  started_at: string
  failed?: boolean
  reason?: string
}
const runHistory = ref<HistoryEntry[]>([])

// ── Descriptions (mirrors CommandCatalog) ─────────────────────────

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

const selectedDescription = computed(() => DESCRIPTIONS[selectedCommand.value] ?? '')

// ── Watchers ──────────────────────────────────────────────────────

watch(
  () => profilesStore.activeProfile?.id,
  () => {
    selectedCommand.value = 'status'
    abortCurrent()
    outputLines.value = []
    lastResult.value = null
    errorMsg.value = null
  },
)

// ── Helpers ───────────────────────────────────────────────────────

function abortCurrent() {
  if (streamHandle) {
    streamHandle.abort()
    streamHandle = null
  }
  running.value = false
}

function handleSelect(cmd: string) {
  selectedCommand.value = cmd
}

function handleClear() {
  outputLines.value = []
  lastResult.value = null
  errorMsg.value = null
}

async function handleRun(args: string[]) {
  if (running.value) return

  const projectId = profilesStore.activeProfile?.id
  if (!projectId) {
    errorMsg.value = t('forge.noProject')
    return
  }

  running.value = true
  abortCurrent()
  outputLines.value = []
  lastResult.value = null
  errorMsg.value = null

  const startedAt = new Date().toISOString()

  try {
    const { run_id } = await startForge(projectId, selectedCommand.value, args)

    streamHandle = streamForgeEvents(
      run_id,
      (event) => {
        if (event.event === 'forge.stdout') {
          outputLines.value = [...outputLines.value, { type: 'stdout', text: event.line ?? '' }]
        } else if (event.event === 'forge.stderr') {
          outputLines.value = [...outputLines.value, { type: 'stderr', text: event.line ?? '' }]
        }
        // heartbeat and terminal events with no line content are ignored here
      },
      (result) => {
        running.value = false
        streamHandle = null
        const isFailed = 'reason' in result
        lastResult.value = {
          exit_code: result.exit_code,
          duration_ms: result.duration_ms,
          failed: isFailed,
          reason: (result as ForgeFailedEvent).reason,
        }
        // Append to history (keep last 5)
        const entry: HistoryEntry = {
          command: selectedCommand.value,
          args,
          exit_code: result.exit_code,
          duration_ms: result.duration_ms,
          started_at: startedAt,
          failed: isFailed,
          reason: (result as ForgeFailedEvent).reason,
        }
        runHistory.value = [entry, ...runHistory.value].slice(0, 5)
      },
      (err) => {
        running.value = false
        streamHandle = null
        outputLines.value = [
          ...outputLines.value,
          { type: 'stderr', text: `Connection error: ${err.message}` },
        ]
      },
    )
  } catch (err) {
    running.value = false
    const msg = err instanceof Error ? err.message : String(err)
    errorMsg.value = msg
  }
}

function handleAbort() {
  abortCurrent()
  outputLines.value = [
    ...outputLines.value,
    { type: 'stderr', text: t('forge.aborted') },
  ]
}

function handleHistoryClick(entry: HistoryEntry) {
  selectedCommand.value = entry.command
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

onUnmounted(() => {
  abortCurrent()
})
</script>

<template>
  <div class="forge-view">
    <!-- Header -->
    <header class="page-header">
      <div class="header-left">
        <h2 class="header-title">{{ t('forge.title') }}</h2>
        <span v-if="profilesStore.activeProfile" class="header-project">
          {{ profilesStore.activeProfile.name }}
        </span>
      </div>
      <NButton
        v-if="outputLines.length > 0 && !running"
        size="small"
        quaternary
        @click="handleClear"
      >
        {{ t('forge.clearAll') }}
      </NButton>
    </header>

    <!-- No project alert -->
    <div v-if="!profilesStore.activeProfile" class="no-project">
      {{ t('forge.noProject') }}
    </div>

    <template v-else>
      <!-- Error alert -->
      <NAlert
        v-if="errorMsg"
        type="error"
        closable
        class="error-alert"
        @close="errorMsg = null"
      >
        {{ errorMsg }}
      </NAlert>

      <!-- Two-column layout -->
      <div class="forge-main">
        <!-- Left: catalog -->
        <div class="catalog-panel">
          <CommandCatalog
            :selected-command="selectedCommand"
            @select="handleSelect"
          />
        </div>

        <!-- Right: runner -->
        <div class="runner-panel">
          <CommandRunner
            :command="selectedCommand"
            :description="selectedDescription"
            :running="running"
            v-model:output-lines="outputLines"
            v-model:last-result="lastResult"
            @run="handleRun"
            @abort="handleAbort"
            @clear="handleClear"
          />
        </div>
      </div>

      <!-- Run history -->
      <div v-if="runHistory.length > 0" class="history-section">
        <div class="history-label">{{ t('forge.historyTitle') }}</div>
        <div class="history-list">
          <button
            v-for="(entry, idx) in runHistory"
            :key="idx"
            class="history-item"
            @click="handleHistoryClick(entry)"
          >
            <code class="history-cmd">{{ entry.command }}</code>
            <span v-if="entry.args.length" class="history-args">{{ entry.args.join(' ') }}</span>
            <span
              class="history-badge"
              :class="entry.exit_code === 0 ? 'badge-ok' : 'badge-err'"
            >
              {{ entry.exit_code === 0 ? 'exit=0' : `exit=${entry.exit_code ?? '?'}` }}
            </span>
            <span class="history-dur">{{ formatDuration(entry.duration_ms) }}</span>
          </button>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.forge-view {
  height: calc(100 * var(--vh));
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 20px;
  border-bottom: 1px solid $border-color;
  flex-shrink: 0;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 10px;
}

.header-title {
  font-size: 16px;
  font-weight: 600;
  color: $text-primary;
}

.header-project {
  font-size: 12px;
  color: $text-muted;
}

.no-project {
  padding: 60px 0;
  text-align: center;
  color: $text-muted;
  font-size: 14px;
}

.error-alert {
  margin: 12px 20px 0;
  flex-shrink: 0;
}

.forge-main {
  flex: 1;
  display: flex;
  min-height: 0;
  gap: 0;
}

.catalog-panel {
  width: 40%;
  flex-shrink: 0;
  border-right: 1px solid $border-color;
  padding: 14px 12px;
  overflow-y: auto;
}

.runner-panel {
  flex: 1;
  padding: 14px 20px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
}

.history-section {
  flex-shrink: 0;
  border-top: 1px solid $border-color;
  padding: 10px 20px;
}

.history-label {
  font-size: 10px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 6px;
}

.history-list {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.history-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 10px;
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  background: none;
  cursor: pointer;
  font-size: 12px;
  color: $text-secondary;
  transition: background $transition-fast;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.06);
    color: $text-primary;
  }
}

.history-cmd {
  font-family: $font-code;
  font-size: 12px;
  color: $text-primary;
}

.history-args {
  color: $text-muted;
  max-width: 80px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.history-badge {
  font-size: 10px;
  font-weight: 600;
  padding: 1px 6px;
  border-radius: $radius-sm;

  &.badge-ok {
    color: #52a770;
    background: rgba(82, 167, 112, 0.12);
  }

  &.badge-err {
    color: #e57373;
    background: rgba(229, 115, 115, 0.12);
  }
}

.history-dur {
  font-size: 11px;
  color: $text-muted;
}
</style>
