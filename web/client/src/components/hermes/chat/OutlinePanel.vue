<script setup lang="ts">
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import type { OutlineItem } from "@/utils/outline";

defineProps<{ items: OutlineItem[] }>();
const emit = defineEmits<{ (e: "navigate", item: OutlineItem): void }>();

const { t } = useI18n();
const expanded = ref(false);

// Note: highlighting the currently visible section would require an
// IntersectionObserver on rendered headings inside MessageItem's DOM,
// which this panel does not own — intentionally omitted for now.
</script>

<template>
  <div class="outline-panel" :class="{ expanded }">
    <button
      class="outline-toggle"
      :title="expanded ? t('chat.outlineHide') : t('chat.outlineShow')"
      :aria-label="expanded ? t('chat.outlineHide') : t('chat.outlineShow')"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      <svg
        width="14"
        height="14"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
      >
        <line x1="8" y1="6" x2="21" y2="6" />
        <line x1="8" y1="12" x2="21" y2="12" />
        <line x1="8" y1="18" x2="21" y2="18" />
        <line x1="3" y1="6" x2="3.01" y2="6" />
        <line x1="3" y1="12" x2="3.01" y2="12" />
        <line x1="3" y1="18" x2="3.01" y2="18" />
      </svg>
    </button>
    <Transition name="outline-slide">
      <nav v-if="expanded" class="outline-body" :aria-label="t('chat.outlineTitle')">
        <div class="outline-title">{{ t("chat.outlineTitle") }}</div>
        <ul class="outline-list">
          <li v-for="item in items" :key="item.anchorId">
            <button
              class="outline-item"
              :class="`level-${item.level}`"
              :title="item.text"
              @click="emit('navigate', item)"
            >
              {{ item.text }}
            </button>
          </li>
        </ul>
      </nav>
    </Transition>
  </div>
</template>

<style scoped lang="scss">
@use "@/styles/variables" as *;

.outline-panel {
  position: absolute;
  top: 12px;
  right: 12px;
  z-index: 5;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 6px;
  // Desktop only: hide on narrow viewports.
  @media (max-width: 1099px) {
    display: none;
  }
}

.outline-toggle {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  background: $bg-card;
  color: var(--text-muted);
  cursor: pointer;
  box-shadow: var(--shadow-sm);
  transition: color 0.15s var(--ease-out), border-color 0.15s var(--ease-out);

  &:hover {
    color: $text-secondary;
    border-color: $text-muted;
  }
}

.outline-body {
  width: 220px;
  max-height: 50vh;
  overflow-y: auto;
  padding: 10px 8px;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  background: $bg-card;
  box-shadow: var(--shadow-sm);
}

.outline-title {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-muted);
  padding: 0 6px 6px;
}

.outline-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.outline-item {
  display: block;
  width: 100%;
  text-align: left;
  border: none;
  background: transparent;
  cursor: pointer;
  font-size: 12px;
  line-height: 1.4;
  color: $text-secondary;
  padding: 3px 6px;
  border-radius: $radius-sm;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  transition: background 0.15s var(--ease-out), color 0.15s var(--ease-out);

  &:hover {
    background: rgba(var(--text-muted-rgb), 0.12);
    color: $text-primary;
  }

  &.level-2 {
    padding-left: 18px;
    color: var(--text-muted);
  }

  &.level-3 {
    padding-left: 30px;
    color: var(--text-muted);
    font-size: 11px;
  }
}

.outline-slide-enter-active,
.outline-slide-leave-active {
  transition: opacity 0.18s var(--ease-out), transform 0.18s var(--ease-out);
}
.outline-slide-enter-from,
.outline-slide-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}
</style>
