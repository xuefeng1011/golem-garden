<script setup lang="ts">
import { computed, ref } from 'vue'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { NCollapse, NCollapseItem } from 'naive-ui'

interface TaskInput {
  subagent_type?: string
  description?: string
  prompt?: string
  [key: string]: unknown
}

const props = defineProps<{
  taskInput: TaskInput | null
  result?: string
  isError?: boolean
  running: boolean
}>()

const profilesStore = useProfilesStore()

/** Extract worker label from prompt ("You are **Name**") or subagent_type fallback */
const workerLabel = computed<string>(() => {
  const input = props.taskInput
  if (!input) return 'Worker'

  // Try to extract "You are **Name**" from prompt
  if (input.prompt) {
    const match = /You are \*\*([A-Z][a-z]+)\*\*/.exec(input.prompt)
    if (match) return match[1]
  }

  if (input.subagent_type) {
    // Strip plugin prefixes like "oh-my-claudecode:executor" → "executor"
    const stripped = input.subagent_type.includes(':')
      ? input.subagent_type.split(':').pop() ?? input.subagent_type
      : input.subagent_type
    // Capitalize first letter for display
    return stripped.charAt(0).toUpperCase() + stripped.slice(1)
  }

  return 'Worker'
})

/** Look up the matched SOUL for rank color */
const workerSoul = computed(() => {
  const label = workerLabel.value
  return profilesStore.availableSouls.find(
    s => s.name.toLowerCase() === label.toLowerCase() || s.id.toLowerCase() === label.toLowerCase()
  ) ?? null
})

const directorSoul = computed(() => profilesStore.directorSoul)

const directorLabel = computed<string>(() => {
  const d = directorSoul.value
  if (d) return `${d.name} (Director)`
  return 'Director'
})

const workerRankClass = computed<string>(() => {
  const rank = workerSoul.value?.rank
  return rank ? `rank-${rank}` : ''
})

const taskSummary = computed<string>(() => {
  const input = props.taskInput
  if (!input) return '작업 위임'
  if (input.description) return input.description
  if (input.prompt) return input.prompt.slice(0, 120) + (input.prompt.length > 120 ? '…' : '')
  return '작업 위임'
})

const formattedResult = computed<string>(() => {
  if (!props.result) return ''
  try {
    return JSON.stringify(JSON.parse(props.result), null, 2)
  } catch {
    return props.result
  }
})

const resultExpanded = ref(false)
</script>

<template>
  <div
    class="soul-handoff"
    :class="{ running, error: isError }"
  >
    <div class="handoff-header">
      <span class="director">{{ directorLabel }}</span>
      <span class="arrow">→</span>
      <span class="worker" :class="workerRankClass">{{ workerLabel }}</span>
    </div>
    <div class="handoff-task">{{ taskSummary }}</div>
    <div class="handoff-status">
      <span v-if="running" class="status-running">⏳ 실행 중…</span>
      <span v-else-if="isError" class="status-error">✗ 실패</span>
      <span v-else class="status-done">✓ 완료</span>
    </div>
    <NCollapse v-if="formattedResult && !running" v-model:expanded-names="resultExpanded">
      <NCollapseItem title="Worker 응답 보기" name="result">
        <pre class="result-text">{{ formattedResult }}</pre>
      </NCollapseItem>
    </NCollapse>
  </div>
</template>

<style scoped lang="scss">
@use "@/styles/variables" as *;

.soul-handoff {
  margin: 6px 0;
  padding: 10px 12px;
  border-left: 3px solid #2d7a57;
  background: rgba(45, 122, 87, 0.05);
  border-radius: $radius-sm;

  &.running {
    border-left-color: var(--accent-info);
    background: rgba(var(--accent-info-rgb), 0.05);
  }

  &.error {
    border-left-color: $error;
    background: rgba(var(--error-rgb), 0.05);
  }
}

.handoff-header {
  display: flex;
  gap: 8px;
  align-items: center;
  font-size: 13px;
  font-weight: 600;

  .arrow {
    color: $text-muted;
    font-weight: 400;
  }

  .director {
    color: $text-secondary;
  }

  .worker {
    color: $text-secondary;

    &.rank-novice  { color: #888888; }
    &.rank-junior  { color: #4a90d9; }
    &.rank-senior  { color: #52a770; }
    &.rank-master  { color: #9b59b6; }
  }
}

.handoff-task {
  margin-top: 4px;
  font-size: 13px;
  color: $text-primary;
  line-height: 1.5;
}

.handoff-status {
  margin-top: 4px;
  font-size: 12px;

  .status-running { color: var(--accent-info); }
  .status-error   { color: $error; }
  .status-done    { color: #2d7a57; }

  .dark & {
    .status-done { color: #66bb6a; }
  }
}

.result-text {
  font-size: 12px;
  font-family: $font-code;
  white-space: pre-wrap;
  word-break: break-word;
  max-height: 300px;
  overflow-y: auto;
  margin: 0;
  color: $text-secondary;
}
</style>
