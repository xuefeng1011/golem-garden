<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { NSpin } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchSouls } from '@/api/hermes/souls'
import type { Soul } from '@/api/hermes/souls'
import SoulCard from '@/components/hermes/souls/SoulCard.vue'
import SoulDetailModal from '@/components/hermes/souls/SoulDetailModal.vue'

const { t } = useI18n()
const profilesStore = useProfilesStore()

const souls = ref<Soul[]>([])
const loading = ref(false)
const error = ref(false)
const selectedSoulId = ref<string | null>(null)
const modalOpen = ref(false)

async function loadSouls(projectId: string) {
  loading.value = true
  error.value = false
  try {
    souls.value = await fetchSouls(projectId)
  } catch {
    error.value = true
    souls.value = []
  } finally {
    loading.value = false
  }
}

function openSoul(soul: Soul) {
  selectedSoulId.value = soul.id
  modalOpen.value = true
}

function closeModal() {
  modalOpen.value = false
}

onMounted(() => {
  if (profilesStore.activeProfile?.id) {
    loadSouls(profilesStore.activeProfile.id)
  }
})

watch(
  () => profilesStore.activeProfile?.id,
  (id) => {
    if (id) {
      loadSouls(id)
    } else {
      souls.value = []
    }
  },
)
</script>

<template>
  <div class="souls-view">
    <header class="page-header">
      <h2 class="header-title">{{ t('souls.title') }}</h2>
      <span v-if="profilesStore.activeProfile" class="project-name">
        {{ profilesStore.activeProfile.name }}
      </span>
    </header>

    <div class="souls-content">
      <div v-if="!profilesStore.activeProfile" class="empty-state">
        {{ t('souls.noProject') }}
      </div>

      <NSpin v-else :show="loading">
        <div v-if="error" class="empty-state">
          {{ t('souls.loadFailed') }}
        </div>

        <div v-else-if="!loading && souls.length === 0" class="empty-state">
          {{ t('souls.empty') }}
        </div>

        <div v-else class="souls-grid">
          <SoulCard
            v-for="soul in souls"
            :key="soul.id"
            :soul="soul"
            @click="openSoul(soul)"
          />
        </div>
      </NSpin>
    </div>

    <SoulDetailModal
      v-if="profilesStore.activeProfile?.id"
      :project-id="profilesStore.activeProfile.id"
      :soul-id="selectedSoulId"
      :open="modalOpen"
      @close="closeModal"
    />
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.souls-view {
  height: calc(100 * var(--vh));
  display: flex;
  flex-direction: column;
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid $border-color;
}

.header-title {
  font-size: 16px;
  font-weight: 600;
  color: $text-primary;
}

.project-name {
  font-size: 13px;
  color: $text-muted;
}

.souls-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}

.souls-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;

  @media (max-width: 900px) {
    grid-template-columns: repeat(2, 1fr);
  }

  @media (max-width: $breakpoint-mobile) {
    grid-template-columns: 1fr;
  }
}

.empty-state {
  padding: 60px 0;
  text-align: center;
  color: $text-muted;
  font-size: 14px;
}
</style>
