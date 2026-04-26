<script setup lang="ts">
import { ref, watch, nextTick } from 'vue'
import { NButton, NInput, NTag } from 'naive-ui'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

const props = defineProps<{
  command: string
  description: string
  running: boolean
}>()

const emit = defineEmits<{
  (e: 'run', args: string[]): void
  (e: 'abort'): void
  (e: 'clear'): void
}>()

export interface OutputLine {
  type: 'stdout' | 'stderr'
  text: string
}

export interface RunResult {
  exit_code: number | null
  duration_ms: number
  failed?: boolean
  reason?: string
}

const args = ref<string[]>([''])
const outputLines = defineModel<OutputLine[]>('outputLines', { default: () => [] })
const lastResult = defineModel<RunResult | null>('lastResult', { default: null })

const outputEl = ref<HTMLElement | null>(null)

watch(
  () => outputLines.value.length,
  async () => {
    await nextTick()
    if (outputEl.value) {
      outputEl.value.scrollTop = outputEl.value.scrollHeight
    }
  },
)

watch(
  () => props.command,
  () => {
    args.value = ['']
  },
)

function addArg() {
  args.value = [...args.value, '']
}

function removeArg(idx: number) {
  args.value = args.value.filter((_, i) => i !== idx)
  if (args.value.length === 0) args.value = ['']
}

function updateArg(idx: number, val: string) {
  const next = [...args.value]
  next[idx] = val
  args.value = next
}

function handleRun() {
  const trimmed = args.value.map(a => a.trim())
  while (trimmed.length > 0 && trimmed[trimmed.length - 1] === '') trimmed.pop()
  emit('run', trimmed)
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}초`
}
</script>

<template>
  <div class="runner">
    <!-- Command header -->
    <div class="runner-header">
      <div class="cmd-meta">
        <span class="selected-label">{{ t('forge.selectedCommand') }}</span>
        <code class="selected-cmd">{{ props.command }}</code>
      </div>
      <p class="cmd-description">{{ props.description }}</p>
    </div>

    <!-- Args -->
    <div class="args-section">
      <div class="args-label">{{ t('forge.argsLabel') }}</div>
      <div class="args-rows">
        <div v-for="(arg, idx) in args" :key="idx" class="arg-row">
          <NInput
            :value="arg"
            size="small"
            :placeholder="t('forge.argPlaceholder', { n: idx + 1 })"
            @update:value="(v: string) => updateArg(idx, v)"
            @keydown.enter="handleRun"
          />
          <NButton
            v-if="args.length > 1"
            size="small"
            quaternary
            @click="removeArg(idx)"
          >
            ×
          </NButton>
        </div>
      </div>
      <NButton size="small" quaternary @click="addArg">
        + {{ t('forge.addArg') }}
      </NButton>
    </div>

    <!-- Action buttons -->
    <div class="action-row">
      <NButton
        type="primary"
        size="small"
        :loading="props.running"
        :disabled="props.running"
        @click="handleRun"
      >
        {{ t('forge.run') }}
      </NButton>
      <NButton
        v-if="props.running"
        size="small"
        type="error"
        ghost
        @click="emit('abort')"
      >
        {{ t('forge.abort') }}
      </NButton>
      <NButton
        v-if="outputLines.length > 0 && !props.running"
        size="small"
        quaternary
        @click="emit('clear')"
      >
        {{ t('forge.clearOutput') }}
      </NButton>
    </div>

    <!-- Output area -->
    <div class="output-wrap">
      <div class="output-label">{{ t('forge.outputLabel') }}</div>
      <div ref="outputEl" class="output-body">
        <div
          v-for="(line, idx) in outputLines"
          :key="idx"
          class="output-line"
          :class="line.type"
        >{{ line.text }}</div>
        <div v-if="outputLines.length === 0 && !props.running" class="output-empty">
          {{ t('forge.outputEmpty') }}
        </div>
      </div>

      <!-- Result footer -->
      <div v-if="lastResult !== null" class="result-footer">
        <NTag
          :type="lastResult.exit_code === 0 ? 'success' : 'error'"
          size="small"
          :bordered="false"
        >
          <template v-if="lastResult.failed">
            {{ t('forge.resultFailed', { reason: lastResult.reason ?? '' }) }}
          </template>
          <template v-else>
            {{ t('forge.resultDone', { code: lastResult.exit_code, duration: formatDuration(lastResult.duration_ms) }) }}
          </template>
        </NTag>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.runner {
  display: flex;
  flex-direction: column;
  gap: 14px;
  height: 100%;
}

.runner-header {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.cmd-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}

.selected-label {
  font-size: 12px;
  color: $text-muted;
}

.selected-cmd {
  font-family: $font-code;
  font-size: 14px;
  font-weight: 600;
  color: $accent-primary;
  background: rgba(var(--accent-primary-rgb), 0.1);
  padding: 2px 8px;
  border-radius: $radius-sm;
}

.cmd-description {
  font-size: 12px;
  color: $text-secondary;
  margin: 0;
}

.args-section {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.args-label {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.args-rows {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.arg-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.action-row {
  display: flex;
  gap: 8px;
  align-items: center;
}

.output-wrap {
  display: flex;
  flex-direction: column;
  gap: 6px;
  flex: 1;
  min-height: 0;
}

.output-label {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.output-body {
  flex: 1;
  min-height: 200px;
  max-height: 50vh;
  overflow-y: auto;
  background: rgba(0, 0, 0, 0.04);
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  padding: 10px 12px;
  font-family: $font-code;
  font-size: 12px;
  line-height: 1.6;

  .dark & {
    background: rgba(0, 0, 0, 0.2);
  }
}

.output-line {
  white-space: pre-wrap;
  word-break: break-all;
  color: $text-primary;

  &.stderr {
    color: #e57373;
  }
}

.output-empty {
  color: $text-muted;
  font-style: italic;
  font-size: 12px;
}

.result-footer {
  display: flex;
  align-items: center;
  gap: 8px;
  padding-top: 4px;
}
</style>
