<script setup lang="ts">
/**
 * FlowStudioView — Flow Studio 목록 (R2/R6/R8).
 * 프로젝트와 완전 독립된 스튜디오 폴더 목록을 보여주고, 생성/편집기 진입을 제공한다.
 */
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { NButton, NIcon, NSpin } from 'naive-ui'
import { AlertCircleOutline, FolderOpenOutline, ArrowForwardOutline } from '@vicons/ionicons5'
import { fetchStudios } from '@/api/hermes/studios'
import type { Studio } from '@/api/hermes/studios'
import EmptyState from '@/components/common/EmptyState.vue'
import StudioCreateModal from '@/components/hermes/studio/StudioCreateModal.vue'

const { t } = useI18n()
const router = useRouter()

const studios = ref<Studio[]>([])
const loading = ref(false)
const loadError = ref<string | null>(null)
const showCreateModal = ref(false)

async function loadStudios() {
  loading.value = true
  loadError.value = null
  try {
    studios.value = await fetchStudios()
  } catch (err) {
    loadError.value = err instanceof Error ? err.message : String(err)
  } finally {
    loading.value = false
  }
}

function openStudio(studio: Studio) {
  router.push({ name: 'hermes.flowStudio.editor', params: { projectId: studio.id } })
}

function formatDate(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleDateString()
}

function handleCreated() {
  loadStudios()
}

onMounted(loadStudios)
</script>

<template>
  <div class="flow-studio-view">
    <header class="page-header">
      <h2 class="header-title">{{ t('flowStudio.title') }}</h2>
      <NButton type="primary" size="small" @click="showCreateModal = true">
        {{ t('flowStudio.create') }}
      </NButton>
    </header>

    <div v-if="loading" class="center-state">
      <NSpin size="medium" />
      <span class="center-label">{{ t('common.loading') }}</span>
    </div>

    <div v-else-if="loadError" class="center-state">
      <NIcon size="24" color="var(--error)"><AlertCircleOutline /></NIcon>
      <span class="center-label">{{ loadError }}</span>
    </div>

    <EmptyState
      v-else-if="studios.length === 0"
      :title="t('flowStudio.emptyTitle')"
      :description="t('flowStudio.emptyDesc')"
      :action="{ label: t('flowStudio.create'), handler: () => (showCreateModal = true) }"
    >
      <template #icon>
        <NIcon><FolderOpenOutline /></NIcon>
      </template>
    </EmptyState>

    <div v-else class="studio-grid">
      <div v-for="studio in studios" :key="studio.id" class="studio-card">
        <div class="studio-card-name">{{ studio.name }}</div>
        <div class="studio-card-path">{{ studio.path }}</div>
        <div class="studio-card-footer">
          <span class="studio-card-date">{{ formatDate(studio.createdAt) }}</span>
          <NButton size="small" @click="openStudio(studio)">
            {{ t('flowStudio.open') }}
            <template #icon><NIcon><ArrowForwardOutline /></NIcon></template>
          </NButton>
        </div>
      </div>
    </div>

    <StudioCreateModal
      v-if="showCreateModal"
      @close="showCreateModal = false"
      @created="handleCreated"
    />
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.flow-studio-view {
  height: calc(100 * var(--vh));
  overflow-y: auto;
  padding: 20px;
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
}

.header-title {
  font-size: 16px;
  font-weight: 600;
  color: $text-primary;
  margin: 0;
}

.center-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 60px 0;
}

.center-label {
  color: $text-muted;
  font-size: 13px;
}

.studio-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 280px), 1fr));
  gap: 14px;
}

.studio-card {
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 14px;
  background: $bg-card;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.studio-card-name {
  font-size: 14px;
  font-weight: 600;
  color: $text-primary;
}

.studio-card-path {
  font-size: 12px;
  color: $text-muted;
  font-family: $font-code;
  word-break: break-all;
}

.studio-card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 8px;
}

.studio-card-date {
  font-size: 11px;
  color: $text-muted;
}
</style>
