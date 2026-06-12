<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import {
  NTabs, NTabPane, NCollapse, NCollapseItem,
  NCard, NTag, NEmpty, NSpin, NAlert,
} from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchAchievements, fetchChemistry } from '@/api/hermes/meta'
import type { Achievement, ChemistryPair, ChemistryData } from '@/api/hermes/meta'

const { t, locale } = useI18n()
const profilesStore = useProfilesStore()

// ── State ─────────────────────────────────────────────────────────
const achievements = ref<Achievement[]>([])
const chemistry = ref<ChemistryData | null>(null)

const achievementsLoading = ref(false)
const chemistryLoading = ref(false)
const achievementsError = ref(false)
const chemistryError = ref(false)

const activeTab = ref('achievements')

// ── Data loading ──────────────────────────────────────────────────
async function loadAchievements(projectId: string) {
  achievementsLoading.value = true
  achievementsError.value = false
  try {
    achievements.value = await fetchAchievements(projectId)
  } catch {
    achievementsError.value = true
    achievements.value = []
  } finally {
    achievementsLoading.value = false
  }
}

async function loadChemistry(projectId: string) {
  chemistryLoading.value = true
  chemistryError.value = false
  try {
    chemistry.value = await fetchChemistry(projectId)
  } catch {
    chemistryError.value = true
    chemistry.value = null
  } finally {
    chemistryLoading.value = false
  }
}

function load(projectId: string) {
  loadAchievements(projectId)
  loadChemistry(projectId)
}

onMounted(() => {
  if (profilesStore.activeProfile?.id) {
    load(profilesStore.activeProfile.id)
  }
})

watch(
  () => profilesStore.activeProfile?.id,
  (id) => {
    if (id) {
      load(id)
    } else {
      achievements.value = []
      chemistry.value = null
    }
  }
)

// ── Achievements: group by SOUL ───────────────────────────────────
const achievementsBySoul = computed(() => {
  const map: Record<string, Achievement[]> = {}
  for (const a of achievements.value) {
    if (!map[a.soul]) map[a.soul] = []
    map[a.soul].push(a)
  }
  return map
})

const soulNames = computed(() => Object.keys(achievementsBySoul.value))

// ── Chemistry: sorted pairs ───────────────────────────────────────
const sortedPairs = computed<ChemistryPair[]>(() => {
  if (!chemistry.value) return []
  return [...chemistry.value.pairs].sort((a, b) => b.interactions - a.interactions)
})

const showRawEvents = ref(false)

const recentEvents = computed(() => {
  if (!chemistry.value) return []
  return chemistry.value.raw_events.slice(0, 30)
})

// ── Helpers ───────────────────────────────────────────────────────
function formatDate(raw: string): string {
  if (!raw) return '—'
  const d = new Date(raw)
  if (isNaN(d.getTime())) return '—'
  return d.toLocaleDateString(locale.value)
}

function scoreBar(score: number | null): string {
  if (score === null) return '—'
  const filled = Math.round(score * 12)
  const empty = 12 - filled
  return '█'.repeat(filled) + '░'.repeat(empty)
}

function scoreLabel(score: number | null): string {
  if (score === null) return '—'
  return score.toFixed(2)
}
</script>

<template>
  <div class="meta-view">
    <!-- Header -->
    <header class="page-header">
      <div class="header-left">
        <h2 class="header-title">{{ t('meta.title') }}</h2>
        <span v-if="profilesStore.activeProfile" class="header-project">
          {{ profilesStore.activeProfile.name }}
        </span>
      </div>
    </header>

    <div class="meta-content">
      <!-- No project -->
      <div v-if="!profilesStore.activeProfile" class="empty-state">
        {{ t('meta.noProject') }}
      </div>

      <template v-else>
        <NTabs v-model:value="activeTab" type="line" animated>

          <!-- Tab 1: Achievements -->
          <NTabPane name="achievements" :tab="t('meta.tabAchievements')">
            <NSpin :show="achievementsLoading">
              <NAlert v-if="achievementsError" type="error" class="tab-alert">
                {{ t('meta.achievementsError') }}
              </NAlert>

              <template v-else-if="!achievementsLoading">
                <div v-if="soulNames.length === 0" class="empty-state">
                  {{ t('meta.achievementsEmpty') }}
                </div>

                <NCollapse v-else class="soul-collapse">
                  <NCollapseItem
                    v-for="soul in soulNames"
                    :key="soul"
                    :name="soul"
                    :title="`${soul} (${achievementsBySoul[soul].length}${t('meta.countSuffix')})`"
                  >
                    <div class="badges-grid">
                      <div
                        v-for="ach in achievementsBySoul[soul]"
                        :key="ach.id"
                        class="badge-card"
                      >
                        <NTag type="warning" size="medium" class="badge-tag">
                          🏆 {{ ach.badge }}
                        </NTag>
                        <p class="badge-desc">{{ ach.description }}</p>
                        <span class="badge-date">{{ formatDate(ach.earned_at) }}</span>
                      </div>
                    </div>
                  </NCollapseItem>
                </NCollapse>
              </template>
            </NSpin>
          </NTabPane>

          <!-- Tab 2: Chemistry -->
          <NTabPane name="chemistry" :tab="t('meta.tabChemistry')">
            <NSpin :show="chemistryLoading">
              <NAlert v-if="chemistryError" type="error" class="tab-alert">
                {{ t('meta.chemistryError') }}
              </NAlert>

              <template v-else-if="!chemistryLoading">
                <NEmpty
                  v-if="sortedPairs.length === 0"
                  :description="t('meta.chemistryEmpty')"
                  class="chemistry-empty"
                />

                <div v-else class="chemistry-list">
                  <NCard
                    v-for="pair in sortedPairs"
                    :key="`${pair.souls[0]}-${pair.souls[1]}`"
                    size="small"
                    class="pair-card"
                  >
                    <div class="pair-header">
                      <span class="pair-names">{{ pair.souls[0] }} ↔ {{ pair.souls[1] }}</span>
                      <span class="pair-interactions">{{ pair.interactions }}{{ t('meta.interactionsSuffix') }}</span>
                    </div>
                    <div class="pair-bar-row">
                      <span class="pair-score-label">{{ t('meta.synergy') }} {{ scoreLabel(pair.score) }}</span>
                      <span class="pair-bar">{{ scoreBar(pair.score) }}</span>
                    </div>
                  </NCard>
                </div>

                <!-- Raw events (collapsible) -->
                <div v-if="recentEvents.length > 0" class="raw-events-section">
                  <button class="raw-toggle" @click="showRawEvents = !showRawEvents">
                    {{ showRawEvents ? t('meta.hideRaw') : t('meta.showRaw') }}
                    ({{ recentEvents.length }})
                  </button>
                  <ul v-if="showRawEvents" class="raw-events-list">
                    <li v-for="(ev, idx) in recentEvents" :key="idx" class="raw-event-item">
                      <span class="raw-souls">{{ ev.souls[0] }} ↔ {{ ev.souls[1] }}</span>
                      <span class="raw-event-name">{{ ev.event }}</span>
                      <span class="raw-date">{{ formatDate(ev.ts) }}</span>
                    </li>
                  </ul>
                </div>
              </template>
            </NSpin>
          </NTabPane>

        </NTabs>
      </template>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.meta-view {
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

.meta-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}

.empty-state {
  padding: 60px 0;
  text-align: center;
  color: $text-muted;
  font-size: 14px;
}

.tab-alert {
  margin-bottom: 16px;
}

// ── Achievements ──────────────────────────────────────────────────

.soul-collapse {
  margin-top: 8px;
}

.badges-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  padding: 4px 0 8px;
}

.badge-card {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 4px;
  min-width: 140px;
  max-width: 200px;
}

.badge-tag {
  font-size: 13px;
  font-weight: 600;
}

.badge-desc {
  font-size: 12px;
  color: $text-secondary;
  margin: 0;
  line-height: 1.4;
}

.badge-date {
  font-size: 11px;
  color: $text-muted;
}

// ── Chemistry ─────────────────────────────────────────────────────

.chemistry-empty {
  padding: 48px 0;
}

.chemistry-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-top: 8px;
}

.pair-card {
  border: 1px solid $border-color;
  border-radius: $radius-md;
}

.pair-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 6px;
}

.pair-names {
  font-size: 14px;
  font-weight: 600;
  color: $text-primary;
}

.pair-interactions {
  font-size: 12px;
  color: $text-muted;
}

.pair-bar-row {
  display: flex;
  align-items: center;
  gap: 10px;
}

.pair-score-label {
  font-size: 12px;
  color: $text-secondary;
  white-space: nowrap;
  min-width: 90px;
}

.pair-bar {
  font-family: $font-code;
  font-size: 13px;
  color: $accent-primary;
  letter-spacing: 1px;
}

// ── Raw events ────────────────────────────────────────────────────

.raw-events-section {
  margin-top: 20px;
}

.raw-toggle {
  background: none;
  border: none;
  font-size: 12px;
  color: $text-muted;
  cursor: pointer;
  padding: 0;
  text-decoration: underline;

  &:hover {
    color: $text-secondary;
  }
}

.raw-events-list {
  list-style: none;
  padding: 0;
  margin: 10px 0 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.raw-event-item {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 12px;
  color: $text-secondary;
}

.raw-souls {
  font-weight: 600;
  color: $text-primary;
  min-width: 100px;
}

.raw-event-name {
  flex: 1;
}

.raw-date {
  color: $text-muted;
  white-space: nowrap;
}
</style>
