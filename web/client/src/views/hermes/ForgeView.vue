<script setup lang="ts">
import { ref, computed, watch, onUnmounted } from 'vue'
import { NButton, NAlert } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'
import type { ForgeFailedEvent } from '@/api/hermes/forge'
import CommandCatalog from '@/components/hermes/forge/CommandCatalog.vue'
import CommandRunner from '@/components/hermes/forge/CommandRunner.vue'
import type { OutputLine, RunResult } from '@/components/hermes/forge/CommandRunner.vue'
import { getArgSchema } from '@/components/hermes/forge/commandSchema'

const { t, te } = useI18n()
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

// ── Description + arg schema (shared with CommandCatalog) ────────

const selectedDescription = computed(() => {
  const key = `forge.descriptions.${selectedCommand.value}`
  return te(key) ? t(key) : ''
})

const selectedArgSchema = computed(() => getArgSchema(selectedCommand.value))

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
            :arg-schema="selectedArgSchema"
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
