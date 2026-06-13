<script setup lang="ts">
/**
 * RunPanel — collapsible bottom panel showing live forge stdout/stderr.
 * Approval/rejection buttons appear for waiting_approval nodes.
 */
import { ref, watch, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { NButton, NIcon } from 'naive-ui'
import { ChevronDownOutline, ChevronUpOutline, CheckmarkOutline, CloseOutline } from '@vicons/ionicons5'

import { computed } from 'vue'

const props = defineProps<{
  lines: string[]
  running: boolean
  phase?: 'idle' | 'running' | 'waiting' | 'done' | 'failed'
  waitingSteps: { stepId: string; label: string }[]
}>()

const emit = defineEmits<{
  (e: 'approve', stepId: string): void
  (e: 'reject', stepId: string): void
  (e: 'stop'): void
}>()

const { t } = useI18n()

const collapsed = ref(false)
const logEl = ref<HTMLElement | null>(null)

// 실행 시작 시 패널 자동 펼침 (진행 상황이 바로 보이도록)
watch(
  () => props.running,
  (r) => { if (r) collapsed.value = false },
)

// 결과 칩 — 실행 종료 후 단계 표시
const resultChip = computed(() => {
  switch (props.phase) {
    case 'done':    return { text: t('flowEditor.phaseDone'),    cls: 'chip-done' }
    case 'failed':  return { text: t('flowEditor.phaseFailed'),  cls: 'chip-failed' }
    case 'waiting': return { text: t('flowEditor.phaseWaiting'), cls: 'chip-waiting' }
    default:        return null
  }
})

// Auto-scroll to bottom when new lines arrive
watch(
  () => props.lines.length,
  async () => {
    if (collapsed.value) return
    await nextTick()
    if (logEl.value) {
      logEl.value.scrollTop = logEl.value.scrollHeight
    }
  },
)
</script>

<template>
  <div class="run-panel" :class="{ collapsed }">
    <div class="run-panel-header" @click="collapsed = !collapsed">
      <span class="run-panel-title">{{ t('flowEditor.runPanelTitle') }}</span>
      <span v-if="running" class="running-badge">{{ t('flowEditor.running') }}</span>
      <span v-else-if="resultChip" class="result-chip" :class="resultChip.cls">{{ resultChip.text }}</span>
      <button
        v-if="running"
        class="stop-btn"
        :title="t('flowEditor.btnStop')"
        @click.stop="emit('stop')"
      >■ {{ t('flowEditor.btnStop') }}</button>
      <NIcon class="toggle-icon" :size="14">
        <ChevronUpOutline v-if="!collapsed" />
        <ChevronDownOutline v-else />
      </NIcon>
    </div>

    <div v-show="!collapsed" class="run-panel-body">
      <!-- Approval actions -->
      <div v-if="waitingSteps.length > 0" class="approval-bar">
        <span class="approval-label">{{ t('flowEditor.approvalPending') }}</span>
        <div v-for="step in waitingSteps" :key="step.stepId" class="approval-step">
          <span class="step-name">{{ step.label }}</span>
          <NButton size="tiny" type="success" @click="emit('approve', step.stepId)">
            <template #icon><NIcon><CheckmarkOutline /></NIcon></template>
            {{ t('flowEditor.btnApprove') }}
          </NButton>
          <NButton size="tiny" type="error" @click="emit('reject', step.stepId)">
            <template #icon><NIcon><CloseOutline /></NIcon></template>
            {{ t('flowEditor.btnReject') }}
          </NButton>
        </div>
      </div>

      <!-- Log output -->
      <div ref="logEl" class="run-log">
        <div v-if="lines.length === 0" class="log-empty">{{ t('flowEditor.runLogEmpty') }}</div>
        <div v-for="(line, i) in lines" :key="i" class="log-line">{{ line }}</div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.run-panel {
  flex-shrink: 0;
  border-top: 1px solid $border-color;
  background: $bg-secondary;
  display: flex;
  flex-direction: column;
  max-height: 220px;
  transition: max-height $transition-fast;

  &.collapsed {
    max-height: 36px;
  }
}

.run-panel-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  cursor: pointer;
  flex-shrink: 0;
  user-select: none;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.04);
  }
}

.run-panel-title {
  font-size: 12px;
  font-weight: 600;
  color: $text-primary;
  flex: 1;
}

.running-badge {
  font-size: 11px;
  color: $accent-primary;
  background: rgba(var(--accent-primary-rgb), 0.12);
  border-radius: 10px;
  padding: 1px 8px;
  animation: pulse-opacity 1.4s ease-in-out infinite;
}

@keyframes pulse-opacity {
  0%, 100% { opacity: 1; }
  50%       { opacity: 0.5; }
}

.stop-btn {
  font-size: 11px;
  font-weight: 600;
  color: $error;
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.3);
  border-radius: 6px;
  padding: 1px 8px;
  cursor: pointer;

  &:hover { background: rgba(239, 68, 68, 0.18); }
}

.result-chip {
  font-size: 11px;
  font-weight: 600;
  border-radius: 10px;
  padding: 1px 8px;

  &.chip-done    { color: $success; background: rgba(34, 197, 94, 0.14); }
  &.chip-failed  { color: $error;   background: rgba(239, 68, 68, 0.14); }
  &.chip-waiting { color: $warning;  background: rgba(245, 158, 11, 0.16); }
}

.toggle-icon {
  color: $text-muted;
}

.run-panel-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.approval-bar {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  padding: 6px 14px;
  background: rgba(245, 158, 11, 0.08);
  border-bottom: 1px solid rgba(245, 158, 11, 0.2);
  flex-shrink: 0;
}

.approval-label {
  font-size: 12px;
  color: $warning;
  font-weight: 600;
}

.approval-step {
  display: flex;
  align-items: center;
  gap: 4px;
}

.step-name {
  font-size: 11px;
  color: $text-secondary;
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.run-log {
  flex: 1;
  overflow-y: auto;
  padding: 6px 14px 10px;
  font-family: $font-code;
  font-size: 12px;
  line-height: 1.6;
}

.log-empty {
  color: $text-muted;
  font-style: italic;
  padding-top: 4px;
}

.log-line {
  color: $text-secondary;
  white-space: pre-wrap;
  word-break: break-all;
}
</style>
