<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { extractReasoning, type ReasoningItem } from '@/utils/trace'

const { t } = useI18n()

const props = defineProps<{
  lines: object[]
}>()

const items = computed<ReasoningItem[]>(() => extractReasoning(props.lines))
</script>

<template>
  <div class="reasoning-root">
    <div class="reasoning-list" role="list">
      <div
        v-for="(item, idx) in items"
        :key="idx"
        class="reasoning-item"
        :class="`item-${item.kind}`"
        role="listitem"
      >
        <!-- thinking: blockquote style -->
        <template v-if="item.kind === 'thinking'">
          <div class="thinking-block">
            <span class="thinking-gutter" />
            <div class="thinking-text">{{ item.text }}</div>
          </div>
        </template>

        <!-- tool: chip style -->
        <template v-else-if="item.kind === 'tool'">
          <span class="tool-chip">
            <span class="tool-chip-icon">⚙</span>
            {{ item.text }}
          </span>
        </template>

        <!-- text: plain -->
        <template v-else>
          <div class="text-block">{{ item.text }}</div>
        </template>
      </div>
      <div v-if="items.length === 0" class="empty-msg">
        {{ t('console.noReasoning') }}
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.reasoning-root {
  height: 100%;
  overflow-y: auto;
}

.reasoning-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 4px 0;
}

.thinking-block {
  display: flex;
  gap: 10px;
  padding: 10px 12px;
  background: rgba(var(--accent-primary-rgb), 0.05);
  border-radius: $radius-sm;
}

.thinking-gutter {
  flex-shrink: 0;
  width: 3px;
  border-radius: 2px;
  background: rgba(var(--accent-primary-rgb), 0.4);
  align-self: stretch;
}

.thinking-text {
  font-size: 13px;
  color: $text-secondary;
  line-height: 1.6;
  white-space: pre-wrap;
  word-break: break-word;
}

.tool-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 12px;
  border-radius: 999px;
  border: 1px solid $border-color;
  background: $bg-card;
  font-size: 12px;
  font-family: $font-code;
  font-weight: 600;
  color: $text-primary;
}

.tool-chip-icon {
  font-size: 12px;
}

.text-block {
  font-size: 13px;
  color: $text-secondary;
  line-height: 1.6;
  white-space: pre-wrap;
  word-break: break-word;
  padding: 4px 0;
}

.empty-msg {
  text-align: center;
  color: $text-muted;
  padding: 24px;
  font-size: 13px;
}
</style>
