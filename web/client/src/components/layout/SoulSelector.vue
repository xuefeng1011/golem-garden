<script setup lang="ts">
import { computed } from 'vue'
import { NSelect } from 'naive-ui'
import { useProfilesStore } from '@/stores/hermes/profiles'

const profilesStore = useProfilesStore()

const options = computed(() =>
  profilesStore.availableSouls.map(s => ({
    label: `${s.name} · ${s.rank}`,
    value: s.id,
  })),
)

function handleChange(value: string | number | Array<string | number>) {
  if (typeof value === 'string') {
    profilesStore.setCurrentSoul(value)
  }
}
</script>

<template>
  <div class="soul-selector">
    <div class="selector-label">기본 에이전트</div>
    <NSelect
      :value="profilesStore.currentSoulId"
      :options="options"
      :disabled="profilesStore.availableSouls.length === 0"
      :placeholder="profilesStore.availableSouls.length === 0 ? '프로젝트를 먼저 선택하세요' : ''"
      size="small"
      @update:value="handleChange"
    />
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.soul-selector {
  padding: 0 12px;
  margin-bottom: 8px;
}

.selector-label {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 6px;
}
</style>
