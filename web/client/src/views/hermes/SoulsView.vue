<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { NIcon } from 'naive-ui'
import { FolderOpenOutline, AlertCircleOutline, PeopleOutline } from '@vicons/ionicons5'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchSouls } from '@/api/hermes/souls'
import type { Soul } from '@/api/hermes/souls'
import SoulCard from '@/components/hermes/souls/SoulCard.vue'
import SoulDetailModal from '@/components/hermes/souls/SoulDetailModal.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import SkeletonCard from '@/components/common/SkeletonCard.vue'
import { ApiError, kindToI18nKey } from '@/utils/api-error'

const { t } = useI18n()
const router = useRouter()
const profilesStore = useProfilesStore()

const souls = ref<Soul[]>([])
const loading = ref(false)
const loadError = ref<ApiError | null>(null)
const selectedSoulId = ref<string | null>(null)
const modalOpen = ref(false)

async function loadSouls(projectId: string) {
  loading.value = true
  loadError.value = null
  try {
    souls.value = await fetchSouls(projectId)
  } catch (e) {
    loadError.value = e instanceof ApiError ? e : new ApiError(String(e), null, 'client')
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

function onRetry() {
  const id = profilesStore.activeProfile?.id
  if (!id) return
  loadSouls(id)
}


function goToProfiles() {
  router.push({ name: 'hermes.profiles' })
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
      <EmptyState
        v-if="!profilesStore.activeProfile"
        :title="t('souls.noProject')"
        :description="t('souls.noProjectDescription')"
        :action="{ label: t('souls.selectProject'), handler: goToProfiles }"
      >
        <template #icon>
          <NIcon><FolderOpenOutline /></NIcon>
        </template>
      </EmptyState>

      <div v-else-if="loading" class="souls-grid" data-testid="souls-skeleton">
        <SkeletonCard v-for="i in 6" :key="i" :rows="3" show-avatar />
      </div>

      <EmptyState
        v-else-if="loadError"
        :title="t('souls.loadFailed')"
        :description="t(kindToI18nKey(loadError)) + (loadError.kind === 'network' ? '\n' + t('common.gatewayHint') : '')"
        :action="{ label: t('common.retry'), handler: onRetry }"
      >
        <template #icon>
          <NIcon><AlertCircleOutline /></NIcon>
        </template>
      </EmptyState>

      <EmptyState
        v-else-if="souls.length === 0"
        :title="t('souls.empty')"
        :description="t('souls.emptyDescription')"
      >
        <template #icon>
          <NIcon><PeopleOutline /></NIcon>
        </template>
      </EmptyState>

      <div v-else class="souls-grid">
        <SoulCard
          v-for="soul in souls"
          :key="soul.id"
          :soul="soul"
          @click="openSoul(soul)"
        />
      </div>
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
</style>
