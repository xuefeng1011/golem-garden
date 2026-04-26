<script setup lang="ts">
import { computed } from 'vue'
import type { Skill } from '@/api/hermes/skills'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

const props = defineProps<{
  skills: Skill[]
  selectedSkillId: string | null
  searchQuery: string
}>()

const emit = defineEmits<{
  select: [skill: Skill]
}>()

const filteredSkills = computed(() => {
  if (!props.searchQuery) return props.skills
  const q = props.searchQuery.toLowerCase()
  return props.skills.filter(
    s => s.name.toLowerCase().includes(q) || s.description.toLowerCase().includes(q),
  )
})
</script>

<template>
  <div class="skill-list">
    <div v-if="filteredSkills.length === 0" class="skill-empty">
      {{ searchQuery ? t('skills.noMatch') : t('skills.noSkills') }}
    </div>
    <button
      v-for="skill in filteredSkills"
      :key="skill.id"
      class="skill-item"
      :class="{ active: selectedSkillId === skill.id }"
      @click="emit('select', skill)"
    >
      <div class="skill-info">
        <span class="skill-name">{{ skill.name }}</span>
        <span v-if="skill.description" class="skill-desc">{{ skill.description }}</span>
      </div>
    </button>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.skill-list {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
}

.skill-empty {
  padding: 24px 16px;
  font-size: 13px;
  color: $text-muted;
  text-align: center;
}

.skill-item {
  display: flex;
  flex-direction: row;
  align-items: center;
  width: 100%;
  padding: 8px 12px;
  border: none;
  background: none;
  color: $text-secondary;
  font-size: 13px;
  text-align: left;
  cursor: pointer;
  border-radius: $radius-sm;
  transition: all $transition-fast;
  gap: 8px;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.06);
    color: $text-primary;
  }

  &.active {
    background: rgba(var(--accent-primary-rgb), 0.1);
    color: $text-primary;
    font-weight: 500;
  }
}

.skill-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

.skill-name {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.skill-desc {
  font-size: 11px;
  color: $text-muted;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-top: 1px;
}
</style>
