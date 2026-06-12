<script setup lang="ts">
import { NPopconfirm } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import type { Session } from '@/stores/hermes/chat'
import { formatTimestampMs } from '@/shared/session-display'

const props = defineProps<{
  session: Session
  active: boolean
  live: boolean
  pinned: boolean
  canDelete: boolean
  selectable?: boolean
  selected?: boolean
}>()

const emit = defineEmits<{
  select: []
  contextmenu: [event: MouseEvent]
  delete: []
  'toggle-select': []
}>()

const { t } = useI18n()

function handleClick() {
  if (props.selectable) emit('toggle-select')
  else emit('select')
}
</script>

<template>
  <button
    class="session-item"
    :class="{ active, live }"
    :aria-current="active ? 'page' : undefined"
    @click="handleClick"
    @contextmenu="emit('contextmenu', $event)"
  >
    <span v-if="selectable" class="session-item-checkbox" :class="{ checked: selected }" aria-hidden="true">
      <svg v-if="selected" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
    </span>
    <div class="session-item-content">
      <span class="session-item-title-row">
        <span v-if="live" class="session-item-active-indicator" aria-hidden="true">
          <svg class="session-item-active-spinner" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
            <circle cx="12" cy="12" r="8" opacity="0.2" />
            <path d="M20 12a8 8 0 0 0-8-8" />
          </svg>
        </span>
        <span v-if="pinned" class="session-item-pin" aria-hidden="true">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 17v5" />
            <path d="M5 8l14 0" />
            <path d="M8 3l8 0 0 5 3 5-14 0 3-5z" />
          </svg>
        </span>
        <span class="session-item-title">{{ session.title }}</span>
        <span v-if="live" class="session-item-live-badge">
          <span class="live-dot"></span>
          <span>{{ t('chat.liveMode') }}</span>
        </span>
      </span>
      <span class="session-item-meta">
        <span v-if="session.model" class="session-item-model">{{ session.model }}</span>
        <span class="session-item-time">{{ formatTimestampMs(session.createdAt) }}</span>
        <span v-if="session.messageCount && session.messageCount > 0" class="session-item-msg-count">
          {{ session.messageCount }}
        </span>
      </span>
    </div>
    <NPopconfirm v-if="canDelete && !selectable" @positive-click="emit('delete')">
      <template #trigger>
        <button class="session-item-delete" @click.stop>
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </template>
      {{ t('chat.deleteSession') }}
    </NPopconfirm>
  </button>
</template>
