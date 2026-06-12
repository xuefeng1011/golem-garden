<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import type { ActiveRun } from '@/api/hermes/console'

const { t } = useI18n()

const props = defineProps<{
  runs: ActiveRun[]
}>()

// Live elapsed ticker — updates every second
const tick = ref(0)
let timer: ReturnType<typeof setInterval> | null = null

onMounted(() => {
  timer = setInterval(() => { tick.value++ }, 1000)
})

onUnmounted(() => {
  if (timer) clearInterval(timer)
})

function fmtElapsed(run: ActiveRun): string {
  // elapsed_ms from server + client-side ticks (approximate)
  void tick.value // reactive dependency
  const ms = run.elapsed_ms
  const sec = Math.floor(ms / 1000)
  if (sec < 60) return `${sec}s`
  const min = Math.floor(sec / 60)
  const rem = sec % 60
  return `${min}m${rem}s`
}
</script>

<template>
  <div v-if="runs.length > 0" class="active-banner">
    <span class="banner-label">
      <span class="pulse-dot" />
      {{ t('console.activeRuns', { count: runs.length }) }}
    </span>
    <div class="run-chips">
      <div v-for="run in runs" :key="run.run_id" class="run-chip">
        <span class="chip-soul">{{ run.soul }}</span>
        <span class="chip-elapsed">{{ fmtElapsed(run) }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.active-banner {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 14px;
  background: rgba(var(--success-rgb), 0.08);
  border: 1px solid rgba(var(--success-rgb), 0.25);
  border-radius: $radius-md;
  margin-bottom: 16px;
  flex-wrap: wrap;
}

.banner-label {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  font-weight: 600;
  color: $success;
  white-space: nowrap;
}

.pulse-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: $success;
  animation: pulse 1.4s ease-in-out infinite;
  flex-shrink: 0;
}

@keyframes pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.5; transform: scale(0.85); }
}

.run-chips {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.run-chip {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px;
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: 999px;
  font-size: 12px;
}

.chip-soul {
  font-weight: 600;
  color: $text-primary;
}

.chip-elapsed {
  color: $text-muted;
  font-variant-numeric: tabular-nums;
}
</style>
