<script setup lang="ts">
import { ref, watch } from 'vue'
import ProfileCard from './ProfileCard.vue'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { useI18n } from 'vue-i18n'
import { fetchOverview } from '@/api/hermes/overview'
import type { ProjectOverview } from '@/api/hermes/overview'

defineEmits<{ rename: [name: string] }>()

const { t } = useI18n()
const profilesStore = useProfilesStore()

// Map<projectId, ProjectOverview | null>  (null = load failed or no id)
const overviewCache = ref<Map<string, ProjectOverview | null>>(new Map())

// Fetch overviews in parallel once the profile list is populated.
// Uses Promise.allSettled so one failure never blocks the rest.
watch(
  () => profilesStore.profiles,
  async (profiles) => {
    if (!profiles.length) return
    const entries = profiles.filter((p) => p.id)
    const results = await Promise.allSettled(
      entries.map((p) => fetchOverview(p.id!))
    )
    const next = new Map(overviewCache.value)
    results.forEach((result, i) => {
      const id = entries[i].id!
      next.set(id, result.status === 'fulfilled' ? result.value : null)
    })
    overviewCache.value = next
  },
  { immediate: false }
)
</script>

<template>
  <div v-if="profilesStore.profiles.length === 0" class="empty-state">
    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" class="empty-icon">
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </svg>
    <p>{{ t('profiles.noProfiles') }}</p>
  </div>
  <div v-else class="profiles-grid">
    <ProfileCard
      v-for="p in profilesStore.profiles"
      :key="p.name"
      :profile="p"
      :overview="p.id ? (overviewCache.get(p.id) ?? undefined) : undefined"
      @rename="$emit('rename', $event)"
    />
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: $text-muted;
  gap: 12px;

  .empty-icon {
    opacity: 0.3;
  }

  p {
    font-size: 14px;
  }
}

.profiles-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 420px), 1fr));
  gap: 14px;
}
</style>
