<script setup lang="ts">
import MarkdownRenderer from '@/components/hermes/chat/MarkdownRenderer.vue'
import type { SkillDetail } from '@/api/hermes/skills'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

defineProps<{
  skill: SkillDetail
}>()
</script>

<template>
  <div class="skill-detail">
    <div class="detail-title">
      <span class="detail-name">{{ skill.name }}</span>
      <span v-if="skill.has_scripts" class="scripts-badge">{{ t('skills.hasScripts') }}</span>
    </div>

    <p v-if="skill.description" class="detail-desc">{{ skill.description }}</p>

    <div class="detail-content">
      <MarkdownRenderer :content="skill.content" />
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.skill-detail {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.detail-title {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  gap: 8px;
  padding-bottom: 12px;
  border-bottom: 1px solid $border-color;
  margin-bottom: 12px;
}

.detail-name {
  color: $text-primary;
  font-size: 15px;
  font-weight: 600;
}

.scripts-badge {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 8px;
  background: rgba(var(--accent-primary-rgb), 0.1);
  color: $accent-primary;
  font-weight: 500;
}

.detail-desc {
  flex-shrink: 0;
  font-size: 13px;
  color: $text-muted;
  margin: 0 0 12px;
}

.detail-content {
  flex: 1;
  overflow-y: auto;
  min-height: 0;
  padding-bottom: 12px;

  :deep(hr) {
    border: none;
    margin: 12px 0;
  }
}
</style>
