<script setup lang="ts">
import { computed } from 'vue'
import { NTag } from 'naive-ui'
import EmptyState from '@/components/common/EmptyState.vue'
import type { MailboxMessage } from '@/api/hermes/souls'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  messages: MailboxMessage[]
}>()

const { t } = useI18n()

const TYPE_COLOR: Record<string, string> = {
  task_assign: '#4a9eff',
  task_done: '#52a770',
  info: '#888888',
  review_request: '#c8922a',
}

function typeColor(type: string): string {
  return TYPE_COLOR[type] ?? '#888888'
}

function relativeTime(ts: string): string {
  if (!ts) return ''
  const d = new Date(ts)
  if (isNaN(d.getTime())) return ts
  const diff = Math.floor((Date.now() - d.getTime()) / 1000)
  if (diff < 60) return t('activity.mailbox.timeJustNow')
  if (diff < 3600) return t('activity.mailbox.timeMinutesAgo', { n: Math.floor(diff / 60) })
  if (diff < 86400) return t('activity.mailbox.timeHoursAgo', { n: Math.floor(diff / 3600) })
  return t('activity.mailbox.timeDaysAgo', { n: Math.floor(diff / 86400) })
}

function truncate(text: string, max = 100): string {
  if (!text) return ''
  return text.length > max ? text.slice(0, max) + '…' : text
}

const sorted = computed(() =>
  [...props.messages].sort((a, b) => {
    const ta = new Date(a.ts).getTime()
    const tb = new Date(b.ts).getTime()
    return tb - ta
  })
)
</script>

<template>
  <div class="mailbox-feed">
    <EmptyState
      v-if="messages.length === 0"
      :title="t('activity.mailbox.empty')"
      :description="t('activity.mailbox.emptyHint')"
    />

    <div v-else class="feed-list">
      <div
        v-for="(msg, idx) in sorted"
        :key="idx"
        class="feed-item"
      >
        <div class="feed-header">
          <span class="feed-route">
            <span class="feed-from">{{ msg.from }}</span>
            <span class="feed-arrow">→</span>
            <span class="feed-to">{{ msg.to }}</span>
          </span>
          <NTag
            size="tiny"
            :bordered="false"
            class="feed-type-tag"
            :style="{ background: typeColor(msg.type) + '22', color: typeColor(msg.type) }"
          >
            {{ msg.type }}
          </NTag>
          <span class="feed-time">{{ relativeTime(msg.ts) }}</span>
        </div>
        <p class="feed-content">{{ truncate(msg.content) }}</p>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.mailbox-feed {
  display: flex;
  flex-direction: column;
}

.feed-list {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.feed-item {
  padding: 10px 0;
  border-bottom: 1px solid $border-light;

  &:last-child {
    border-bottom: none;
  }
}

.feed-header {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 4px;
}

.feed-route {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
}

.feed-from,
.feed-to {
  color: $text-primary;
}

.feed-arrow {
  color: $text-muted;
  font-size: 12px;
}

.feed-type-tag {
  font-size: 11px;
  border-radius: 4px;
  padding: 0 6px;
}

.feed-time {
  margin-left: auto;
  font-size: 12px;
  color: $text-muted;
  flex-shrink: 0;
}

.feed-content {
  font-size: 13px;
  color: $text-secondary;
  margin: 0;
  line-height: 1.5;
  word-break: break-word;
}
</style>
