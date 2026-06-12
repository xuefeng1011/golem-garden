<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  text: string
  streaming?: boolean
}>()

const { t } = useI18n()
// 기본 접힘 — 사고 과정은 보조 정보, 본문이 주인공
const expanded = ref(false)
</script>

<template>
  <div class="thinking-block" :class="{ streaming: props.streaming }">
    <button class="thinking-header" @click="expanded = !expanded">
      <span class="thinking-dot" :class="{ pulse: props.streaming }" />
      <span class="thinking-label">{{ t('chat.thinkingLabel') }}</span>
      <svg
        class="thinking-chevron"
        :class="{ open: expanded }"
        width="12"
        height="12"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
      >
        <polyline points="6 9 12 15 18 9" />
      </svg>
    </button>
    <div v-if="expanded" class="thinking-body">{{ props.text }}</div>
  </div>
</template>

<style scoped lang="scss">
.thinking-block {
  margin-bottom: 8px;
  border-left: 2px solid var(--border-color, rgba(128, 128, 128, 0.3));
  padding-left: 8px;
}

.thinking-header {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 2px 0;
  border: none;
  background: none;
  color: var(--text-muted);
  font-size: 12px;
  cursor: pointer;

  &:hover {
    color: var(--text-secondary);
  }
}

.thinking-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--text-muted);

  &.pulse {
    animation: thinking-pulse 1.2s var(--ease-in-out, ease-in-out) infinite;
  }
}

@keyframes thinking-pulse {
  0%, 100% { opacity: 0.3; }
  50% { opacity: 1; }
}

@media (prefers-reduced-motion: reduce) {
  .thinking-dot.pulse {
    animation: none;
  }
}

.thinking-chevron {
  transition: transform 0.15s var(--ease-out, ease);

  &.open {
    transform: rotate(180deg);
  }
}

.thinking-body {
  padding: 6px 0 2px;
  font-size: 12px;
  line-height: 1.5;
  color: var(--text-muted);
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
