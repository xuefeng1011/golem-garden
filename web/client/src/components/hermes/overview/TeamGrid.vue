<script setup lang="ts">
import { useRouter } from 'vue-router'
import { NTag } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import type { BoardTeamMember } from '@/api/hermes/overview'

const { t } = useI18n()
const router = useRouter()

defineProps<{ team: BoardTeamMember[] }>()

function goToSouls() {
  router.push({ name: 'hermes.souls' })
}
</script>

<template>
  <div class="team-grid-wrap">
    <h3 class="section-title">{{ t('overview.teamTitle') }}</h3>
    <div v-if="team.length === 0" class="empty-state">
      {{ t('overview.teamEmpty') }}
    </div>
    <div v-else class="team-grid">
      <div
        v-for="member in team"
        :key="member.name"
        class="member-card"
        @click="goToSouls"
      >
        <div class="member-header">
          <span class="member-name">{{ member.name }}</span>
          <span class="rank-tag" :class="`rank-${member.rank?.toLowerCase()}`">
            {{ member.rank }}
          </span>
        </div>
        <div class="member-role">{{ member.role }}</div>
        <div v-if="member.agent" class="member-agent">
          <NTag size="small" :bordered="false" class="agent-tag">{{ member.agent }}</NTag>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.team-grid-wrap {
  height: 100%;
}

.section-title {
  font-size: 13px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 12px;
}

.team-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;

  @media (max-width: 900px) {
    grid-template-columns: 1fr;
  }
}

.member-card {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 12px 14px;
  cursor: pointer;
  transition: border-color $transition-fast, box-shadow $transition-fast;

  &:hover {
    border-color: rgba(var(--accent-primary-rgb), 0.4);
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  }
}

.member-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 4px;
}

.member-name {
  font-size: 14px;
  font-weight: 600;
  color: $text-primary;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.rank-tag {
  font-size: 10px;
  font-weight: 600;
  padding: 2px 6px;
  border-radius: $radius-sm;
  text-transform: capitalize;
  flex-shrink: 0;

  &.rank-novice  { color: #888888; background: rgba(136, 136, 136, 0.12); }
  &.rank-junior  { color: #4a90d9; background: rgba(74, 144, 217, 0.12); }
  &.rank-senior  { color: #52a770; background: rgba(82, 167, 112, 0.12); }
  &.rank-master  { color: #9b59b6; background: rgba(155, 89, 182, 0.12); }
}

.member-role {
  font-size: 12px;
  color: $text-secondary;
  margin-bottom: 6px;
}

.agent-tag {
  font-size: 11px;
}

.empty-state {
  padding: 40px 0;
  text-align: center;
  color: $text-muted;
  font-size: 13px;
}
</style>
