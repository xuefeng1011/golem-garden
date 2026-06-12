<script setup lang="ts">
import { ref, computed, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { buildReplayTimeline, type ReplayEvent } from '@/utils/trace'

const { t } = useI18n()

const props = defineProps<{
  lines: object[]
}>()

const events = computed<ReplayEvent[]>(() => buildReplayTimeline(props.lines))

// ── playback state ────────────────────────────────────────────────────────────
const cursor = ref(-1)
const playing = ref(false)
const speed = ref(1)
let playTimer: ReturnType<typeof setInterval> | null = null

function advanceCursor() {
  if (cursor.value >= events.value.length - 1) {
    stopPlay()
    return
  }
  cursor.value++
}

function startPlay() {
  if (playing.value) return
  if (cursor.value >= events.value.length - 1) cursor.value = -1
  playing.value = true
  scheduleTimer()
}

function scheduleTimer() {
  if (playTimer) clearInterval(playTimer)
  const intervalMs = Math.round(600 / speed.value)
  playTimer = setInterval(advanceCursor, intervalMs)
}

function stopPlay() {
  playing.value = false
  if (playTimer) { clearInterval(playTimer); playTimer = null }
}

function togglePlay() {
  if (playing.value) stopPlay()
  else startPlay()
}

function setSpeed(s: number) {
  speed.value = s
  if (playing.value) scheduleTimer()
}

onUnmounted(stopPlay)

const kindIcon: Record<string, string> = {
  init: '⚙',
  text: '✦',
  thinking: '💭',
  tool_use: '🔧',
  tool_result: '↩',
  result: '✓',
}
</script>

<template>
  <div class="replay-root">
    <!-- Controls -->
    <div class="replay-controls">
      <button class="ctrl-btn" @click="togglePlay">
        {{ playing ? t('console.pause') : t('console.play') }}
      </button>
      <div class="speed-group">
        <button
          v-for="s in [1, 4]"
          :key="s"
          class="speed-btn"
          :class="{ active: speed === s }"
          @click="setSpeed(s)"
        >{{ s }}x</button>
      </div>
      <span class="cursor-label">{{ cursor + 1 }} / {{ events.length }}</span>
    </div>

    <!-- Timeline -->
    <div class="timeline-list" role="list">
      <div
        v-for="ev in events"
        :key="ev.idx"
        class="timeline-item"
        :class="{
          highlighted: ev.idx === cursor,
          passed: ev.idx < cursor,
        }"
        role="listitem"
      >
        <span class="ev-icon" :title="ev.kind">{{ kindIcon[ev.kind] ?? '•' }}</span>
        <div class="ev-body">
          <span class="ev-label">{{ ev.label }}</span>
          <span v-if="ev.detail" class="ev-detail">{{ ev.detail }}</span>
        </div>
      </div>
      <div v-if="events.length === 0" class="empty-msg">{{ t('common.noData') }}</div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.replay-root {
  display: flex;
  flex-direction: column;
  gap: 12px;
  height: 100%;
}

.replay-controls {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 0;
  border-bottom: 1px solid $border-color;
  flex-shrink: 0;
}

.ctrl-btn {
  padding: 5px 14px;
  border-radius: $radius-sm;
  border: 1px solid $border-color;
  background: $bg-card;
  color: $text-primary;
  font-size: 13px;
  cursor: pointer;
  transition: background $transition-fast;

  &:hover { background: rgba(var(--accent-primary-rgb), 0.08); }
}

.speed-group {
  display: flex;
  gap: 4px;
}

.speed-btn {
  padding: 4px 10px;
  border-radius: $radius-sm;
  border: 1px solid $border-color;
  background: none;
  color: $text-muted;
  font-size: 12px;
  cursor: pointer;
  transition: all $transition-fast;

  &.active {
    background: rgba(var(--accent-primary-rgb), 0.12);
    color: $accent-primary;
    border-color: rgba(var(--accent-primary-rgb), 0.35);
  }
}

.cursor-label {
  font-size: 12px;
  color: $text-muted;
  font-variant-numeric: tabular-nums;
  margin-left: auto;
}

.timeline-list {
  flex: 1;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.timeline-item {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 7px 10px;
  border-radius: $radius-sm;
  border: 1px solid transparent;
  transition: all $transition-fast;
  opacity: 0.55;

  &.passed { opacity: 0.8; }

  &.highlighted {
    opacity: 1;
    background: rgba(var(--accent-primary-rgb), 0.1);
    border-color: rgba(var(--accent-primary-rgb), 0.3);
  }
}

.ev-icon {
  font-size: 14px;
  flex-shrink: 0;
  width: 20px;
  text-align: center;
}

.ev-body {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.ev-label {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
}

.ev-detail {
  font-size: 12px;
  color: $text-muted;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.empty-msg {
  text-align: center;
  color: $text-muted;
  padding: 24px;
  font-size: 13px;
}
</style>
