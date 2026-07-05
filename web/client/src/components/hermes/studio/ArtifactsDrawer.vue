<script setup lang="ts">
/**
 * ArtifactsDrawer — output/ 산출물 브라우저 (BACKLOG P0-2).
 * 스튜디오/편집기 양쪽에서 재사용 — projectId 를 prop 으로 받아 목록/에디터
 * 라우트 상태와 독립적으로 동작한다. 목록 -> 클릭 -> 인라인 뷰어(뒤로가기) 흐름.
 */
import { ref, watch } from 'vue'
import { NDrawer, NDrawerContent, NButton, NIcon, NSpin } from 'naive-ui'
import { RefreshOutline, ArrowBackOutline, AlertCircleOutline, DocumentTextOutline } from '@vicons/ionicons5'
import { useI18n } from 'vue-i18n'
import { fetchArtifacts, fetchArtifactContent } from '@/api/hermes/artifacts'
import type { Artifact, ArtifactContent } from '@/api/hermes/artifacts'
import { fmtBytes } from '@/utils/format'
import EmptyState from '@/components/common/EmptyState.vue'

const props = defineProps<{
  show: boolean
  projectId: string
  dir?: string
}>()

const emit = defineEmits<{
  (e: 'update:show', v: boolean): void
}>()

const { t } = useI18n()

const artifacts = ref<Artifact[]>([])
const loading = ref(false)
const loadError = ref<string | null>(null)

const selected = ref<Artifact | null>(null)
const content = ref<ArtifactContent | null>(null)
const contentLoading = ref(false)
const contentError = ref<string | null>(null)

async function loadArtifacts() {
  if (!props.projectId) return
  loading.value = true
  loadError.value = null
  try {
    artifacts.value = await fetchArtifacts(props.projectId, props.dir ?? 'output')
  } catch (err) {
    loadError.value = err instanceof Error ? err.message : String(err)
  } finally {
    loading.value = false
  }
}

async function openArtifact(artifact: Artifact) {
  selected.value = artifact
  content.value = null
  contentError.value = null
  contentLoading.value = true
  try {
    content.value = await fetchArtifactContent(props.projectId, artifact.path)
  } catch (err) {
    contentError.value = err instanceof Error ? err.message : String(err)
  } finally {
    contentLoading.value = false
  }
}

function backToList() {
  selected.value = null
  content.value = null
  contentError.value = null
}

function dirOf(artifact: Artifact): string {
  const idx = artifact.path.lastIndexOf('/')
  return idx > 0 ? artifact.path.slice(0, idx) : ''
}

function formatMtime(iso: string): string {
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString()
}

function handleUpdateShow(v: boolean) {
  emit('update:show', v)
}

watch(
  () => props.show,
  (visible) => {
    if (visible) {
      backToList()
      loadArtifacts()
    }
  },
  { immediate: true },
)

// FlowEditorView 가 실행 종료 시(드로어 열린 상태라면) 강제 새로고침할 때 사용.
defineExpose({ refresh: loadArtifacts })
</script>

<template>
  <NDrawer :show="show" :width="420" placement="right" @update:show="handleUpdateShow">
    <NDrawerContent :title="selected ? selected.name : t('flowStudio.artifacts.title')" closable>
      <!-- List pane -->
      <template v-if="!selected">
        <div class="pane-toolbar">
          <NButton size="small" secondary :loading="loading" @click="loadArtifacts">
            <template #icon><NIcon><RefreshOutline /></NIcon></template>
          </NButton>
        </div>

        <div v-if="loading" class="center-state">
          <NSpin size="medium" />
        </div>
        <div v-else-if="loadError" class="center-state error">
          <NIcon size="20" color="var(--error)"><AlertCircleOutline /></NIcon>
          <span class="center-label">{{ loadError }}</span>
        </div>
        <EmptyState v-else-if="artifacts.length === 0" :title="t('flowStudio.artifacts.empty')">
          <template #icon><NIcon><DocumentTextOutline /></NIcon></template>
        </EmptyState>
        <ul v-else class="artifact-list">
          <li
            v-for="artifact in artifacts"
            :key="artifact.path"
            class="artifact-item"
            @click="openArtifact(artifact)"
          >
            <div class="artifact-name">{{ artifact.name }}</div>
            <div class="artifact-meta">
              <span v-if="dirOf(artifact)" class="artifact-dir">{{ dirOf(artifact) }}</span>
              <span class="artifact-size">{{ fmtBytes(artifact.size) }}</span>
              <span class="artifact-mtime">{{ formatMtime(artifact.mtime) }}</span>
            </div>
          </li>
        </ul>
      </template>

      <!-- Viewer pane -->
      <template v-else>
        <div class="pane-toolbar">
          <NButton size="small" secondary @click="backToList">
            <template #icon><NIcon><ArrowBackOutline /></NIcon></template>
            {{ t('flowStudio.artifacts.back') }}
          </NButton>
        </div>

        <div v-if="contentLoading" class="center-state">
          <NSpin size="medium" />
        </div>
        <div v-else-if="contentError" class="center-state error">
          <NIcon size="20" color="var(--error)"><AlertCircleOutline /></NIcon>
          <span class="center-label">{{ contentError }}</span>
        </div>
        <template v-else-if="content">
          <div v-if="content.binary" class="binary-notice">
            {{ t('flowStudio.artifacts.binary', { size: fmtBytes(content.size) }) }}
          </div>
          <template v-else>
            <pre class="content-viewer">{{ content.content }}</pre>
            <div v-if="content.truncated" class="truncated-notice">
              {{ t('flowStudio.artifacts.truncated') }}
            </div>
          </template>
        </template>
      </template>
    </NDrawerContent>
  </NDrawer>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.pane-toolbar {
  display: flex;
  justify-content: flex-end;
  margin-bottom: 10px;
}

.center-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 40px 0;

  &.error {
    color: $error;
  }
}

.center-label {
  font-size: 13px;
  color: $text-secondary;
  text-align: center;
}

.artifact-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.artifact-item {
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  padding: 8px 10px;
  cursor: pointer;
  background: $bg-card;
  transition: border-color $transition-fast, background $transition-fast;

  &:hover {
    border-color: $accent-primary;
    background: $bg-card-hover;
  }
}

.artifact-name {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
  word-break: break-all;
}

.artifact-meta {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  margin-top: 3px;
  font-size: 11px;
  color: $text-muted;
}

.artifact-dir {
  font-family: $font-code;
  word-break: break-all;
}

.binary-notice,
.truncated-notice {
  font-size: 12px;
  color: $text-muted;
  padding: 8px 0;
}

.content-viewer {
  font-family: $font-code;
  font-size: 12px;
  line-height: 1.6;
  color: $text-secondary;
  white-space: pre-wrap;
  word-break: break-all;
  max-height: calc(100vh - 220px);
  overflow-y: auto;
  margin: 0;
  padding: 10px;
  background: $bg-secondary;
  border-radius: $radius-sm;
}
</style>
