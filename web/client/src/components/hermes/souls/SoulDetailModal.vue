<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { NModal, NTag, NSpin, NSkeleton, NIcon } from 'naive-ui'
import { CheckmarkCircle, CloseCircle, InformationCircle } from '@vicons/ionicons5'
import type { SoulDetail, SoulActivity, SkillTreeData } from '@/api/hermes/souls'
import { fetchSoul, fetchSoulActivity, fetchSkillTree } from '@/api/hermes/souls'
import MarkdownRenderer from '@/components/hermes/chat/MarkdownRenderer.vue'
import RankProgress from '@/components/common/RankProgress.vue'
import SkillTreeBranches from './SkillTreeBranches.vue'
import { useI18n } from 'vue-i18n'
import { effortTagType, isolationTagType, formatMaxTurns, showDisallowedTools } from './soulDetailHelpers'

const props = defineProps<{
  projectId: string
  soulId: string | null
  open: boolean
}>()

const emit = defineEmits<{ (e: 'close'): void }>()

const { t, locale } = useI18n()

const detail = ref<SoulDetail | null>(null)
const loading = ref(false)
const error = ref(false)

const activity = ref<SoulActivity | null>(null)
const activityLoading = ref(false)

const skillTree = ref<SkillTreeData | null>(null)
const skillTreeLoading = ref(false)

function formatDate(ts: string): string {
  if (!ts) return ''
  const d = new Date(ts)
  if (isNaN(d.getTime())) return ts
  return d.toLocaleDateString(locale.value, { month: 'short', day: 'numeric' })
}

function truncateTask(task: string, max = 60): string {
  if (!task) return ''
  return task.length > max ? task.slice(0, max) + '…' : task
}

type ResultKind = 'success' | 'fail' | 'info'

function resultKind(result: string): ResultKind {
  if (!result) return 'info'
  const r = result.toLowerCase()
  if (r === 'success' || r === '성공') return 'success'
  if (r === 'error' || r === 'fail' || r === 'failed' || r === '실패') return 'fail'
  return 'info'
}

// whether coordinator card border should be highlighted
const isCoordinator = computed(() => detail.value?.is_coordinator === true)

watch(
  () => [props.open, props.soulId] as const,
  async ([open, soulId]) => {
    if (!open || !soulId || !props.projectId) {
      detail.value = null
      activity.value = null
      skillTree.value = null
      return
    }
    loading.value = true
    error.value = false
    activityLoading.value = true
    skillTreeLoading.value = true

    const detailPromise = fetchSoul(props.projectId, soulId)
      .then((d) => { detail.value = d })
      .catch(() => { error.value = true; detail.value = null })
      .finally(() => { loading.value = false })

    const activityPromise = fetchSoulActivity(props.projectId, soulId)
      .then((a) => { activity.value = a })
      .catch(() => { activity.value = null })
      .finally(() => { activityLoading.value = false })

    const skillTreePromise = fetchSkillTree(props.projectId, soulId)
      .then((s) => { skillTree.value = s })
      .catch(() => { skillTree.value = null })
      .finally(() => { skillTreeLoading.value = false })

    await Promise.allSettled([detailPromise, activityPromise, skillTreePromise])
  },
  { immediate: true },
)
</script>

<template>
  <NModal
    :show="open"
    preset="card"
    :title="detail ? detail.name : t('souls.detail')"
    :style="{
      width: 'min(720px, 90vw)',
      maxHeight: '85vh',
      display: 'flex',
      flexDirection: 'column',
      ...(isCoordinator ? { border: '2px solid #c8922a' } : {}),
    }"
    :segmented="{ content: true }"
    @close="emit('close')"
    @mask-click="emit('close')"
  >
    <template v-if="detail" #header-extra>
      <span class="rank-tag" :class="`rank-${detail.rank}`">{{ detail.rank }}</span>
    </template>

    <NSpin :show="loading">
      <div v-if="error" class="modal-error">
        {{ t('souls.loadFailed') }}
      </div>

      <div v-else-if="detail" class="modal-body">
        <div v-if="detail.specialty?.length" class="specialty-chips">
          <NTag
            v-for="spec in detail.specialty"
            :key="spec"
            size="small"
            :bordered="false"
            class="specialty-tag"
          >
            {{ spec }}
          </NTag>
        </div>

        <!-- N3: Capability & Isolation Fields -->
        <h4 class="section-label">{{ t('souls.sectionCapabilities') }}</h4>
        <div class="capability-panel" :class="{ 'coordinator-panel': isCoordinator }">
          <!-- Director badge -->
          <div v-if="isCoordinator" class="capability-row">
            <span class="cap-label">{{ t('souls.fields.coordinator') }}</span>
            <NTag type="warning" size="small" :bordered="false" class="coordinator-tag">
              👑 Director
            </NTag>
          </div>

          <!-- Effort level -->
          <div v-if="detail.effort" class="capability-row">
            <span class="cap-label">{{ t('souls.fields.effort') }}</span>
            <NTag :type="effortTagType(detail.effort)" size="small" :bordered="false">
              {{ t(`souls.fields.effort${detail.effort.charAt(0).toUpperCase()}${detail.effort.slice(1)}`) }}
            </NTag>
          </div>

          <!-- Isolation mode -->
          <div class="capability-row">
            <span class="cap-label">{{ t('souls.fields.isolation') }}</span>
            <NTag :type="isolationTagType(detail.isolation)" size="small" :bordered="false">
              {{ detail.isolation === 'worktree' ? t('souls.fields.isolationWorktree') : t('souls.fields.isolationNone') }}
            </NTag>
          </div>

          <!-- Max turns -->
          <div class="capability-row">
            <span class="cap-label">{{ t('souls.fields.maxTurns') }}</span>
            <span class="cap-value">{{ formatMaxTurns(detail.max_turns, t('souls.fields.maxTurnsDefault')) }}</span>
          </div>

          <!-- Allowed tools -->
          <div v-if="detail.tools?.length" class="capability-row capability-row--wrap">
            <span class="cap-label">{{ t('souls.fields.allowedTools') }}</span>
            <div class="cap-tags">
              <NTag
                v-for="tool in detail.tools"
                :key="tool"
                type="success"
                size="small"
                :bordered="false"
                class="tool-tag"
              >
                {{ tool }}
              </NTag>
            </div>
          </div>

          <!-- Disallowed tools — only shown when non-empty -->
          <div v-if="showDisallowedTools(detail.disallowed_tools ?? [])" class="capability-row capability-row--wrap">
            <span class="cap-label cap-label--warn">{{ t('souls.fields.permissionRestrictions') }}</span>
            <div class="cap-tags">
              <NTag
                v-for="tool in detail.disallowed_tools"
                :key="tool"
                type="warning"
                size="small"
                :bordered="false"
                class="tool-tag"
              >
                {{ tool }}
              </NTag>
            </div>
          </div>
        </div>
        <!-- /N3 Capability Fields -->

        <!-- Skill Tree Section -->
        <template v-if="skillTreeLoading || (skillTree && skillTree.branches.length > 0)">
          <h4 class="section-label">{{ t('souls.sectionSpecialization') }}</h4>
          <div v-if="skillTreeLoading" class="activity-skeleton">
            <NSkeleton text style="width: 80%; height: 13px; margin-bottom: 6px;" />
            <NSkeleton text style="width: 60%; height: 13px; margin-bottom: 6px;" />
          </div>
          <div v-else-if="skillTree && skillTree.branches.length > 0" class="skill-tree-panel">
            <SkillTreeBranches :branches="skillTree.branches" />
          </div>
        </template>
        <!-- /Skill Tree Section -->

        <!-- Activity Panel -->
        <h4 class="section-label">{{ t('souls.sectionActivity') }}</h4>

        <div v-if="activityLoading" class="activity-skeleton">
          <NSkeleton text style="width: 60%; height: 14px; margin-bottom: 8px;" />
          <NSkeleton text style="width: 100%; height: 10px; margin-bottom: 12px; border-radius: 4px;" />
          <NSkeleton text :repeat="3" style="height: 13px; margin-bottom: 6px;" />
        </div>

        <div v-else-if="activity" class="activity-panel">
          <!-- Counters line -->
          <div class="activity-counters">
            <span class="counter-item">
              {{ t('souls.statsTotal') }} <strong>{{ activity.tasks_total }}</strong>
            </span>
            <span class="counter-sep">·</span>
            <span class="counter-item">
              {{ t('souls.statsSuccess') }} <strong>{{ activity.tasks_success }}</strong>
              <span class="counter-pct">
                ({{ activity.tasks_total > 0 ? Math.round((activity.tasks_success / activity.tasks_total) * 100) : 0 }}%)
              </span>
            </span>
            <span class="counter-sep">·</span>
            <span class="counter-item">
              {{ t('souls.statsStreak') }} <strong>{{ activity.streak }}</strong>
            </span>
          </div>

          <!-- Rank progress -->
          <RankProgress
            :current="activity.rank_progress.current"
            :next="activity.rank_progress.next"
            :tasks-to-promote="activity.rank_progress.tasks_to_promote"
          />

          <!-- Recent tasks -->
          <div v-if="activity.recent_tasks?.length" class="recent-tasks">
            <div class="recent-tasks-title">{{ t('souls.recentTasks') }}</div>
            <div
              v-for="(entry, idx) in activity.recent_tasks.slice(0, 5)"
              :key="idx"
              class="task-row"
            >
              <span class="task-icon" :class="`icon-${resultKind(entry.result)}`">
                <NIcon size="14">
                  <CheckmarkCircle v-if="resultKind(entry.result) === 'success'" />
                  <CloseCircle v-else-if="resultKind(entry.result) === 'fail'" />
                  <InformationCircle v-else />
                </NIcon>
              </span>
              <span class="task-text">{{ truncateTask(entry.task) }}</span>
              <span class="task-date">{{ formatDate(entry.ts) }}</span>
            </div>
          </div>
        </div>
        <!-- /Activity Panel (hidden on error — intentional) -->

        <h4 class="section-label">{{ t('souls.sectionProfile') }}</h4>

        <p v-if="detail.description" class="soul-description">{{ detail.description }}</p>

        <div class="content-section">
          <MarkdownRenderer v-if="detail.content" :content="detail.content" />
          <pre v-else class="content-empty">{{ t('souls.empty') }}</pre>
        </div>
      </div>

      <div v-else-if="!loading" class="modal-empty">
        {{ t('souls.loading') }}
      </div>
    </NSpin>
  </NModal>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.rank-tag {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: $radius-sm;
  text-transform: capitalize;

  &.rank-novice  { color: #888888; background: rgba(136, 136, 136, 0.12); }
  &.rank-junior  { color: #4a90d9; background: rgba(74, 144, 217, 0.12); }
  &.rank-senior  { color: #52a770; background: rgba(82, 167, 112, 0.12); }
  &.rank-master  { color: #9b59b6; background: rgba(155, 89, 182, 0.12); }
}

.modal-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
  overflow-y: auto;
  max-height: calc(85vh - 120px);
}

.specialty-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.specialty-tag {
  font-size: 11px;
}

.section-label {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin: 6px 0 -4px;
}

.activity-skeleton {
  padding: 8px 0;
}

/* ── Activity Panel ── */
.activity-panel {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.activity-counters {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: $text-secondary;
  flex-wrap: wrap;
}

.counter-item strong {
  color: $text-primary;
  font-weight: 600;
}

.counter-pct {
  color: $text-muted;
  font-size: 12px;
}

.counter-sep {
  color: $text-muted;
}

/* Rank progress bar */
.rank-progress {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.rank-progress-label {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  color: $text-secondary;
}

.rp-current {
  font-weight: 600;
  color: $text-primary;
  text-transform: capitalize;
}

.rp-arrow {
  color: $text-muted;
}

.rp-next {
  font-weight: 600;
  color: $text-primary;
  text-transform: capitalize;
}

.rp-max {
  font-size: 12px;
  color: #52a770;
  font-weight: 600;
}

.rp-remaining {
  margin-left: auto;
  color: $text-muted;
  font-size: 11px;
}

.rp-bar-track {
  height: 6px;
  border-radius: 3px;
  background: $border-color;
  overflow: hidden;
}

.rp-bar-fill {
  height: 100%;
  border-radius: 3px;
  background: linear-gradient(90deg, #4a90d9, #52a770);
  transition: width 0.4s ease;
}

/* Recent tasks */
.recent-tasks {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.recent-tasks-title {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  margin-bottom: 2px;
}

.task-row {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: $text-secondary;
  min-width: 0;
}

.task-icon {
  flex-shrink: 0;
  display: flex;
  align-items: center;

  &.icon-success { color: #52a770; }
  &.icon-fail    { color: #e05c5c; }
  &.icon-info    { color: #4a90d9; }
}

.task-text {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.task-date {
  flex-shrink: 0;
  color: $text-muted;
  font-size: 11px;
}

/* ── Skill Tree Panel ── */
.skill-tree-panel {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 10px 14px;
}

/* ── below activity ── */
.soul-description {
  font-size: 13px;
  color: $text-secondary;
  line-height: 1.5;
  margin: 0;
  padding-bottom: 8px;
  border-bottom: 1px solid $border-light;
}

.content-section {
  font-size: 13px;
}

.content-empty {
  font-size: 12px;
  color: $text-muted;
}

.modal-error,
.modal-empty {
  padding: 24px 0;
  text-align: center;
  color: $text-muted;
  font-size: 13px;
}

/* ── N3 Capability Panel ── */
.capability-panel {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 10px 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

// coordinator: gold left-border accent inside the panel
.coordinator-panel {
  border-left: 3px solid #c8922a;
}

.capability-row {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;

  &--wrap {
    align-items: flex-start;
    flex-wrap: wrap;
  }
}

.cap-label {
  flex-shrink: 0;
  min-width: 80px;
  color: $text-muted;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.4px;

  &--warn {
    color: #c8922a;
  }
}

.cap-value {
  color: $text-secondary;
  font-size: 12px;
}

.cap-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.tool-tag {
  font-size: 11px;
}

.coordinator-tag {
  font-weight: 600;
}
</style>
