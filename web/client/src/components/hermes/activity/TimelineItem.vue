<script setup lang="ts">
import { computed } from 'vue'
import { NTag } from 'naive-ui'
import type { TimelineEvent, MailboxDetails, SessionDetails } from '@/api/hermes/activity'

const props = defineProps<{
  event: TimelineEvent
}>()

const TYPE_COLORS: Record<string, string> = {
  task: '#4a9eff',
  session_start: '#52a770',
  session_end: '#52a770',
  mailbox: '#d97f4a',
}

const TYPE_LABELS: Record<string, string> = {
  task: 'task',
  session_start: 'session_start',
  session_end: 'session_end',
  mailbox: 'mailbox',
}

const dotColor = computed(() => TYPE_COLORS[props.event.type] ?? '#888')

const actor = computed(() => {
  if (props.event.type === 'mailbox') {
    const d = props.event.details as MailboxDetails | undefined
    return d?.to ? `${props.event.soul} → ${d.to}` : props.event.soul
  }
  return props.event.soul
})

const formattedDate = computed(() => {
  const raw = props.event.ts
  if (!raw) return ''
  const d = new Date(raw)
  if (isNaN(d.getTime())) return raw
  const month = d.getMonth() + 1
  const day = d.getDate()
  const hours = d.getHours()
  const minutes = String(d.getMinutes()).padStart(2, '0')
  // Show time only if ts contains a time component (not date-only string)
  const hasTime = raw.includes('T') || raw.includes(' ') || raw.includes(':')
  return hasTime ? `${month}월 ${day}일 ${hours}:${minutes}` : `${month}월 ${day}일`
})

const truncatedSummary = computed(() => {
  const s = props.event.summary ?? ''
  return s.length > 120 ? s.slice(0, 120) + '…' : s
})

const subtext = computed(() => {
  const d = props.event.details
  if (!d) return null
  if (props.event.type === 'task') {
    const td = d as { result?: string }
    return td.result ? `result: ${td.result}` : null
  }
  if (props.event.type === 'session_start' || props.event.type === 'session_end') {
    const sd = d as SessionDetails
    return sd.souls?.length ? `souls: ${sd.souls.join(', ')}` : null
  }
  if (props.event.type === 'mailbox') {
    const md = d as MailboxDetails
    return md.msg_type ?? null
  }
  return null
})
</script>

<template>
  <div class="timeline-item">
    <div class="tl-left">
      <span class="tl-dot" :style="{ background: dotColor }" />
      <span class="tl-line" />
    </div>
    <div class="tl-body">
      <div class="tl-header">
        <span class="tl-actor">{{ actor }}</span>
        <NTag size="tiny" :bordered="false" class="tl-type-tag" :style="{ background: dotColor + '22', color: dotColor }">
          {{ TYPE_LABELS[event.type] ?? event.type }}
        </NTag>
        <span class="tl-date">{{ formattedDate }}</span>
      </div>
      <p class="tl-summary">{{ truncatedSummary }}</p>
      <p v-if="subtext" class="tl-sub">{{ subtext }}</p>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.timeline-item {
  display: flex;
  gap: 12px;
  position: relative;
}

.tl-left {
  display: flex;
  flex-direction: column;
  align-items: center;
  flex-shrink: 0;
  width: 16px;
}

.tl-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  flex-shrink: 0;
  margin-top: 3px;
  z-index: 1;
}

.tl-line {
  flex: 1;
  width: 2px;
  background-color: $border-color;
  margin-top: 4px;
}

.tl-body {
  flex: 1;
  padding-bottom: 20px;
  min-width: 0;
}

.tl-header {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 4px;
}

.tl-actor {
  font-weight: 600;
  font-size: 13px;
  color: $text-primary;
}

.tl-type-tag {
  font-size: 11px;
  border-radius: 4px;
  padding: 0 6px;
}

.tl-date {
  font-size: 12px;
  color: $text-muted;
  margin-left: auto;
}

.tl-summary {
  font-size: 13px;
  color: $text-secondary;
  margin: 0;
  line-height: 1.5;
  word-break: break-word;
}

.tl-sub {
  font-size: 12px;
  color: $text-muted;
  margin: 4px 0 0;
}
</style>
