<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { CATEGORIES } from './commandSchema'

const { t, te } = useI18n()

export interface CatalogEntry {
  command: string
  description: string
}

const props = defineProps<{
  selectedCommand: string
}>()

const emit = defineEmits<{
  (e: 'select', command: string): void
}>()

function describe(cmd: string): string {
  const key = `forge.descriptions.${cmd}`
  return te(key) ? t(key) : ''
}
</script>

<template>
  <div class="catalog">
    <div class="catalog-title">{{ t('forge.catalogTitle') }}</div>
    <div
      v-for="(commands, category) in CATEGORIES"
      :key="category"
      class="catalog-group"
    >
      <div class="group-label">{{ t(`forge.categories.${category}`) }}</div>
      <button
        v-for="cmd in commands"
        :key="cmd"
        class="cmd-item"
        :class="{ active: props.selectedCommand === cmd }"
        @click="emit('select', cmd)"
      >
        <span class="cmd-name">{{ cmd }}</span>
        <span class="cmd-desc">{{ describe(cmd) }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.catalog {
  display: flex;
  flex-direction: column;
  gap: 4px;
  overflow-y: auto;
  height: 100%;
  padding-right: 4px;
}

.catalog-title {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  padding: 0 8px 6px;
}

.catalog-group {
  display: flex;
  flex-direction: column;
  gap: 1px;
  margin-bottom: 6px;
}

.group-label {
  font-size: 10px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  padding: 6px 8px 3px;
}

.cmd-item {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 1px;
  padding: 7px 10px;
  border: none;
  background: none;
  border-radius: $radius-sm;
  cursor: pointer;
  width: 100%;
  text-align: left;
  transition: background $transition-fast;

  &:hover {
    background-color: rgba(var(--accent-primary-rgb), 0.06);
  }

  &.active {
    background-color: rgba(var(--accent-primary-rgb), 0.14);

    .cmd-name {
      color: $accent-primary;
    }
  }
}

.cmd-name {
  font-size: 13px;
  font-weight: 500;
  color: $text-primary;
  font-family: $font-code;
}

.cmd-desc {
  font-size: 11px;
  color: $text-muted;
  line-height: 1.3;
}
</style>
