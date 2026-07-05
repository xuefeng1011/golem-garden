<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { NSpin, NButton, NModal, NDataTable } from 'naive-ui'
import type { DataTableColumns } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchBoard } from '@/api/hermes/overview'
import type { ProjectBoard, HistoryEntry } from '@/api/hermes/overview'
import { fetchChemistry } from '@/api/hermes/chemistry'
import type { ChemistryPair } from '@/api/hermes/chemistry'
import MarkdownRenderer from '@/components/hermes/chat/MarkdownRenderer.vue'
import ChemistryPairCard from '@/components/hermes/team/ChemistryPairCard.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import SkeletonCard from '@/components/common/SkeletonCard.vue'
import { ApiError, kindToI18nKey } from '@/utils/api-error'

const { t } = useI18n()
const profilesStore = useProfilesStore()

const board = ref<ProjectBoard | null>(null)
const loading = ref(false)
const loadError = ref<ApiError | null>(null)
const showRawModal = ref(false)

function closeRawModal() {
  showRawModal.value = false
}

const allEmpty = computed(() =>
  board.value !== null &&
  board.value.team.length === 0 &&
  board.value.tech_debt.length === 0 &&
  board.value.history.length === 0
)

async function load(projectId: string) {
  loading.value = true
  loadError.value = null
  try {
    board.value = await fetchBoard(projectId)
  } catch (e) {
    loadError.value = e instanceof ApiError ? e : new ApiError(String(e), null, 'client')
    board.value = null
  } finally {
    loading.value = false
  }
}

// ── Chemistry ─────────────────────────────────────────────────────

const chemPairs = ref<ChemistryPair[]>([])
const chemLoading = ref(false)
const chemError = ref(false)

async function loadChemistry(projectId: string) {
  chemLoading.value = true
  chemError.value = false
  try {
    const data = await fetchChemistry(projectId)
    chemPairs.value = data.pairs
  } catch {
    chemError.value = true
    chemPairs.value = []
  } finally {
    chemLoading.value = false
  }
}

// score DESC (nulls last), then interactions DESC
const sortedPairs = computed<ChemistryPair[]>(() =>
  [...chemPairs.value].sort((a, b) => {
    if (a.score === null && b.score === null) return b.interactions - a.interactions
    if (a.score === null) return 1
    if (b.score === null) return -1
    return b.score - a.score || b.interactions - a.interactions
  })
)

const maxScore = computed(() =>
  Math.max(0, ...chemPairs.value.map((p) => p.score ?? 0))
)

onMounted(() => {
  if (profilesStore.activeProfile?.id) {
    load(profilesStore.activeProfile.id)
    loadChemistry(profilesStore.activeProfile.id)
  }
})

watch(
  () => profilesStore.activeProfile?.id,
  (id) => {
    if (id) {
      load(id)
      loadChemistry(id)
    } else {
      board.value = null
      chemPairs.value = []
    }
  }
)

// ── History NDataTable ────────────────────────────────────────────

function formatDate(raw: string): string {
  if (!raw) return ''
  const d = new Date(raw)
  if (isNaN(d.getTime())) return raw
  return `${d.getMonth() + 1}월 ${d.getDate()}일`
}

const historyCols = computed<DataTableColumns<HistoryEntry>>(() => [
  {
    title: t('team.colDate'),
    key: 'date',
    width: 90,
    sorter: (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
    render: (row) => formatDate(row.date),
  },
  {
    title: t('team.colTask'),
    key: 'task',
    ellipsis: { tooltip: true },
  },
  {
    title: t('team.colSoul'),
    key: 'soul',
    width: 90,
  },
  {
    title: t('team.colResult'),
    key: 'result',
    width: 100,
    ellipsis: { tooltip: true },
  },
])

const historyData = computed<HistoryEntry[]>(() =>
  (board.value?.history ?? []).slice(0, 20)
)
</script>

<template>
  <div class="team-view">
    <!-- Header -->
    <header class="page-header">
      <div class="header-left">
        <h2 class="header-title">{{ t('team.title') }}</h2>
        <span v-if="profilesStore.activeProfile" class="header-project">
          {{ profilesStore.activeProfile.name }}
        </span>
      </div>
      <NButton
        v-if="board && board.raw_md"
        size="small"
        @click="showRawModal = true"
      >
        {{ t('team.viewRaw') }}
      </NButton>
    </header>

    <div class="team-content">
      <!-- No project -->
      <div v-if="!profilesStore.activeProfile" class="empty-state">
        {{ t('team.noProject') }}
      </div>

      <NSpin v-else :show="loading">
        <!-- Error -->
        <div v-if="loadError" class="error-card">
          <p class="error-message">{{ t('team.loadFailed') }}</p>
          <p class="error-description">{{ t(kindToI18nKey(loadError)) }}</p>
          <p v-if="loadError.kind === 'network'" class="error-hint">{{ t('common.gatewayHint') }}</p>
          <NButton size="small" @click="load(profilesStore.activeProfile!.id ?? '')">
            {{ t('common.retry') }}
          </NButton>
        </div>

        <template v-else-if="!loading && board">
          <!-- All empty: no forge-board.md -->
          <div v-if="allEmpty" class="empty-state">
            <p>{{ t('team.noBoardFile') }}</p>
            <p class="empty-hint">{{ t('team.noBoardHint') }}</p>
          </div>

          <template v-else>
            <!-- Section 1: Team -->
            <section v-if="board.team.length > 0" class="board-section">
              <h3 class="section-title">{{ t('team.sectionTeam') }}</h3>
              <div class="table-wrap">
                <table class="team-table">
                  <thead>
                    <tr>
                      <th>{{ t('team.colSoulName') }}</th>
                      <th>{{ t('team.colRole') }}</th>
                      <th>{{ t('team.colAgent') }}</th>
                      <th>{{ t('team.colModel') }}</th>
                      <th>{{ t('team.colRank') }}</th>
                      <th>{{ t('team.colStatus') }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="member in board.team" :key="member.name">
                      <td class="cell-name">{{ member.name }}</td>
                      <td class="cell-role">{{ member.role }}</td>
                      <td class="cell-agent">{{ member.agent ?? '—' }}</td>
                      <td class="cell-model">{{ member.model ?? '—' }}</td>
                      <td>
                        <span class="rank-tag" :class="`rank-${member.rank?.toLowerCase()}`">
                          {{ member.rank }}
                        </span>
                      </td>
                      <td class="cell-status">
                        <span v-if="member.status === 'active' || !member.status" class="status-icon status-ok">✓</span>
                        <span v-else class="status-icon status-off">✗</span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>

            <!-- Section 2: Tech Debt -->
            <section v-if="board.tech_debt.length > 0" class="board-section">
              <h3 class="section-title">
                {{ t('team.sectionDebt') }}
                <span class="section-count">({{ board.tech_debt.length }}{{ t('team.countSuffix') }})</span>
              </h3>
              <ul class="debt-list">
                <li
                  v-for="(item, idx) in board.tech_debt"
                  :key="idx"
                  class="debt-item"
                  :class="{ resolved: item.resolved }"
                >
                  <span class="debt-check">
                    <span v-if="item.resolved" class="check-resolved">✓</span>
                    <span v-else class="check-dot"></span>
                  </span>
                  <span class="debt-text">{{ item.text }}</span>
                </li>
              </ul>
            </section>

            <!-- Section 3: History -->
            <section v-if="board.history.length > 0" class="board-section">
              <h3 class="section-title">{{ t('team.sectionHistory') }}</h3>
              <NDataTable
                :columns="historyCols"
                :data="historyData"
                :bordered="false"
                size="small"
                class="history-table"
              />
            </section>
          </template>
        </template>
      </NSpin>

      <!-- Section 4: Team Chemistry -->
      <section v-if="profilesStore.activeProfile" class="board-section">
        <h3 class="section-title">{{ t('team.sectionChemistry') }}</h3>
        <SkeletonCard v-if="chemLoading" :rows="2" />
        <p v-else-if="chemError" class="chem-error">
          {{ t('team.chemistryLoadFailed') }}
        </p>
        <EmptyState
          v-else-if="sortedPairs.length === 0"
          :title="t('team.chemistryEmpty')"
          :description="t('team.chemistryEmptyHint')"
        />
        <div v-else class="chemistry-grid">
          <ChemistryPairCard
            v-for="pair in sortedPairs"
            :key="pair.souls.join('+')"
            :pair="pair"
            :max-score="maxScore"
          />
        </div>
      </section>
    </div>

    <!-- Raw MD modal -->
    <NModal
      :show="showRawModal"
      preset="dialog"
      :title="t('team.rawModalTitle')"
      style="width: min(800px, 92vw);"
      @update:show="(v: boolean) => { if (!v) closeRawModal() }"
    >
      <div class="raw-md-wrap">
        <MarkdownRenderer v-if="board?.raw_md" :content="board.raw_md" />
      </div>
    </NModal>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.team-view {
  height: calc(100 * var(--vh));
  display: flex;
  flex-direction: column;
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 20px;
  border-bottom: 1px solid $border-color;
  flex-shrink: 0;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 10px;
}

.header-title {
  font-size: 16px;
  font-weight: 600;
  color: $text-primary;
}

.header-project {
  font-size: 12px;
  color: $text-muted;
}

.team-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 24px;
}

.empty-state {
  padding: 60px 0;
  text-align: center;
  color: $text-muted;
  font-size: 14px;
}

.empty-hint {
  margin-top: 8px;
  font-size: 12px;
  color: $text-muted;
  opacity: 0.7;
}

.error-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 60px 0;
  text-align: center;
}

.error-message {
  font-size: 14px;
  color: $text-secondary;
}

.error-description {
  font-size: 13px;
  color: $text-muted;
  max-width: 360px;
}

.error-hint {
  font-size: 12px;
  color: $text-muted;
  font-family: $font-code;
  opacity: 0.8;
  max-width: 360px;
}

// ── Sections ─────────────────────────────────────────────────────

.board-section {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 16px 20px;
}

.section-title {
  font-size: 13px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 14px;
  display: flex;
  align-items: center;
  gap: 6px;
}

.section-count {
  font-weight: 400;
  letter-spacing: 0;
  text-transform: none;
}

// ── Team Table ────────────────────────────────────────────────────

.table-wrap {
  overflow-x: auto;
}

.team-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;

  th {
    text-align: left;
    padding: 8px 12px;
    font-size: 11px;
    font-weight: 600;
    color: $text-muted;
    text-transform: uppercase;
    letter-spacing: 0.4px;
    border-bottom: 1px solid $border-color;
    white-space: nowrap;
  }

  td {
    padding: 10px 12px;
    color: $text-secondary;
    border-bottom: 1px solid $border-light;
    vertical-align: middle;
  }

  tr:last-child td {
    border-bottom: none;
  }

  tr:hover td {
    background-color: rgba(var(--accent-primary-rgb), 0.03);
  }
}

.cell-name {
  font-weight: 600;
  color: $text-primary;
  white-space: nowrap;
}

.cell-role {
  color: $text-secondary;
}

.cell-agent,
.cell-model {
  font-family: $font-code;
  font-size: 12px;
  white-space: nowrap;
}

.rank-tag {
  display: inline-block;
  font-size: 10px;
  font-weight: 600;
  padding: 2px 7px;
  border-radius: $radius-sm;
  text-transform: capitalize;
  white-space: nowrap;

  &.rank-novice  { color: #888888; background: rgba(136, 136, 136, 0.12); }
  &.rank-junior  { color: #4a90d9; background: rgba(74, 144, 217, 0.12); }
  &.rank-senior  { color: #52a770; background: rgba(82, 167, 112, 0.12); }
  &.rank-master  { color: #9b59b6; background: rgba(155, 89, 182, 0.12); }
}

.cell-status {
  text-align: center;
}

.status-icon {
  font-size: 14px;
  font-weight: 600;

  &.status-ok  { color: var(--success); }
  &.status-off { color: var(--error); }
}

// ── Tech Debt ─────────────────────────────────────────────────────

.debt-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.debt-item {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  font-size: 13px;
  color: $text-secondary;

  &.resolved .debt-text {
    text-decoration: line-through;
    color: $text-muted;
  }
}

.debt-check {
  flex-shrink: 0;
  width: 16px;
  height: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-top: 1px;
}

.check-resolved {
  color: var(--success);
  font-size: 12px;
  font-weight: 700;
}

.check-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--error);
  opacity: 0.7;
  display: block;
}

.debt-text {
  line-height: 1.5;
}

// ── Chemistry ─────────────────────────────────────────────────────

.chemistry-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 12px;
}

.chem-error {
  font-size: 13px;
  color: $text-muted;
  text-align: center;
  padding: 16px 0;
}

// ── History Table ─────────────────────────────────────────────────

.history-table {
  // NDataTable inherits naive-ui theming
}

// ── Raw MD Modal ──────────────────────────────────────────────────

.raw-md-wrap {
  max-height: 60vh;
  overflow-y: auto;
  padding: 4px 0;
}
</style>
