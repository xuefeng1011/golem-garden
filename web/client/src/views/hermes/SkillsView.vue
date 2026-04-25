<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { NSpin, NButton, NTabs, NTabPane } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchSkills, fetchSkill, fetchGlobalSkills, fetchGlobalSkill } from '@/api/hermes/skills'
import type { Skill, SkillDetail } from '@/api/hermes/skills'
import SkillList from '@/components/hermes/skills/SkillList.vue'
import SkillDetailComp from '@/components/hermes/skills/SkillDetail.vue'

const { t } = useI18n()
const profilesStore = useProfilesStore()

type TabKey = 'project' | 'global'

const activeTab = ref<TabKey>('project')

const projectSkills = ref<Skill[]>([])
const globalSkills = ref<Skill[]>([])

const projectLoading = ref(false)
const globalLoading = ref(false)
const projectError = ref(false)
const globalError = ref(false)

const searchQuery = ref('')
const selectedSkill = ref<SkillDetail | null>(null)
const detailLoading = ref(false)
const showSidebar = ref(true)

let mobileQuery: MediaQueryList | null = null

function handleMobileChange(e: MediaQueryListEvent | MediaQueryList) {
  showSidebar.value = !e.matches
}

onMounted(() => {
  mobileQuery = window.matchMedia('(max-width: 768px)')
  handleMobileChange(mobileQuery)
  mobileQuery.addEventListener('change', handleMobileChange)

  const projectId = profilesStore.activeProfile?.id
  Promise.all([
    projectId ? loadProjectSkills(projectId) : Promise.resolve(),
    loadGlobalSkills(),
  ])
})

watch(
  () => profilesStore.activeProfile?.id,
  (id) => {
    selectedSkill.value = null
    if (activeTab.value === 'project') {
      // reset selection when project changes
    }
    if (id) {
      loadProjectSkills(id)
    } else {
      projectSkills.value = []
    }
  },
)

watch(activeTab, () => {
  selectedSkill.value = null
})

async function loadProjectSkills(projectId: string) {
  projectLoading.value = true
  projectError.value = false
  try {
    projectSkills.value = await fetchSkills(projectId)
  } catch {
    projectError.value = true
    projectSkills.value = []
  } finally {
    projectLoading.value = false
  }
}

async function loadGlobalSkills() {
  globalLoading.value = true
  globalError.value = false
  try {
    globalSkills.value = await fetchGlobalSkills()
  } catch {
    globalError.value = true
    globalSkills.value = []
  } finally {
    globalLoading.value = false
  }
}

async function handleSelect(skill: Skill) {
  detailLoading.value = true
  selectedSkill.value = null
  if (window.innerWidth <= 768) showSidebar.value = false
  try {
    if (activeTab.value === 'project') {
      const projectId = profilesStore.activeProfile?.id
      if (!projectId) return
      selectedSkill.value = await fetchSkill(projectId, skill.id)
    } else {
      selectedSkill.value = await fetchGlobalSkill(skill.id)
    }
  } catch {
    // leave selectedSkill null — empty detail shown
  } finally {
    detailLoading.value = false
  }
}

function retryProject() {
  const id = profilesStore.activeProfile?.id
  if (id) loadProjectSkills(id)
}

function retryGlobal() {
  loadGlobalSkills()
}
</script>

<template>
  <div class="skills-view">
    <header class="page-header">
      <div style="display: flex; align-items: center; gap: 8px;">
        <h2 class="header-title">{{ t('skills.title') }}</h2>
        <button v-if="!showSidebar" class="sidebar-toggle" @click="showSidebar = true">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="3" y1="12" x2="21" y2="12"/>
            <line x1="3" y1="6" x2="21" y2="6"/>
            <line x1="3" y1="18" x2="21" y2="18"/>
          </svg>
        </button>
      </div>
      <input
        v-model="searchQuery"
        class="search-input"
        :placeholder="t('skills.searchPlaceholder')"
      />
    </header>

    <div class="skills-content">
      <NTabs v-model:value="activeTab" type="line" class="skills-tabs">
        <NTabPane
          name="project"
          :tab="`${t('skills.projectTab')} (${projectSkills.length})`"
        >
          <!-- No active project -->
          <div v-if="!profilesStore.activeProfile" class="empty-state">
            {{ t('skills.noProject') }}
          </div>

          <NSpin v-else :show="projectLoading">
            <div v-if="projectError" class="empty-state">
              <span>{{ t('skills.loadFailed') }}</span>
              <NButton size="small" style="margin-top: 8px;" @click="retryProject">
                {{ t('common.retry') }}
              </NButton>
            </div>

            <div v-else-if="!projectLoading && projectSkills.length === 0" class="empty-state">
              {{ t('skills.empty') }}
            </div>

            <div v-else class="skills-layout">
              <div class="mobile-backdrop" :class="{ active: showSidebar }" @click="showSidebar = false" />

              <div v-if="showSidebar" class="skills-sidebar">
                <SkillList
                  :skills="projectSkills"
                  :selected-skill-id="selectedSkill?.id ?? null"
                  :search-query="searchQuery"
                  @select="handleSelect"
                />
              </div>

              <div class="skills-main">
                <div v-if="detailLoading" class="detail-loading">{{ t('common.loading') }}</div>
                <SkillDetailComp v-else-if="selectedSkill" :skill="selectedSkill" />
                <div v-else class="empty-detail">
                  <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" opacity="0.2">
                    <polygon points="12 2 2 7 12 12 22 7 12 2" />
                    <polyline points="2 17 12 22 22 17" />
                    <polyline points="2 12 12 17 22 12" />
                  </svg>
                  <span>{{ t('skills.selectPrompt') }}</span>
                </div>
              </div>
            </div>
          </NSpin>
        </NTabPane>

        <NTabPane
          name="global"
          :tab="`${t('skills.globalTab')} (${globalSkills.length})`"
        >
          <NSpin :show="globalLoading">
            <div v-if="globalError" class="empty-state">
              <span>{{ t('skills.loadFailed') }}</span>
              <NButton size="small" style="margin-top: 8px;" @click="retryGlobal">
                {{ t('common.retry') }}
              </NButton>
            </div>

            <div v-else-if="!globalLoading && globalSkills.length === 0" class="empty-state">
              {{ t('skills.globalEmpty') }}
            </div>

            <div v-else class="skills-layout">
              <div class="mobile-backdrop" :class="{ active: showSidebar }" @click="showSidebar = false" />

              <div v-if="showSidebar" class="skills-sidebar">
                <SkillList
                  :skills="globalSkills"
                  :selected-skill-id="selectedSkill?.id ?? null"
                  :search-query="searchQuery"
                  @select="handleSelect"
                />
              </div>

              <div class="skills-main">
                <div v-if="detailLoading" class="detail-loading">{{ t('common.loading') }}</div>
                <SkillDetailComp v-else-if="selectedSkill" :skill="selectedSkill" />
                <div v-else class="empty-detail">
                  <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" opacity="0.2">
                    <polygon points="12 2 2 7 12 12 22 7 12 2" />
                    <polyline points="2 17 12 22 22 17" />
                    <polyline points="2 12 12 17 22 12" />
                  </svg>
                  <span>{{ t('skills.selectPrompt') }}</span>
                </div>
              </div>
            </div>
          </NSpin>
        </NTabPane>
      </NTabs>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.skills-view {
  height: calc(100 * var(--vh));
  display: flex;
  flex-direction: column;
}

.skills-content {
  flex: 1;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.skills-tabs {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;

  :deep(.n-tabs-pane-wrapper) {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  :deep(.n-tab-pane) {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    padding: 0;
  }
}

.empty-state {
  padding: 60px 0;
  text-align: center;
  color: $text-muted;
  font-size: 14px;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.skills-layout {
  display: flex;
  height: 100%;
  min-height: 0;
  flex: 1;
}

.skills-sidebar {
  width: 280px;
  border-right: 1px solid $border-color;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  min-height: 0;
}

.skills-main {
  flex: 1;
  overflow-y: auto;
  padding: 16px 20px;
  min-width: 0;
}

.detail-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  font-size: 13px;
  color: $text-muted;
}

.empty-detail {
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  color: $text-muted;
  font-size: 13px;
}

.search-input {
  width: 160px;
  padding: 4px 8px;
  font-size: 13px;
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  background: $bg-secondary;
  color: $text-primary;
  outline: none;

  &:focus {
    border-color: $accent-primary;
  }

  @media (max-width: $breakpoint-mobile) {
    width: 100%;
  }
}

.sidebar-toggle {
  display: none;
  border: none;
  background: none;
  cursor: pointer;
  color: $text-secondary;
  padding: 4px;
  border-radius: $radius-sm;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.06);
  }
}

@media (max-width: $breakpoint-mobile) {
  .sidebar-toggle {
    display: flex;
  }

  .skills-sidebar {
    position: absolute;
    left: 0;
    top: 0;
    height: 100%;
    z-index: 10;
    background: $bg-card;
    box-shadow: 2px 0 8px rgba(0, 0, 0, 0.1);
  }

  .skills-layout {
    position: relative;
  }

  .mobile-backdrop {
    display: block;
    position: absolute;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    z-index: 9;
    opacity: 0;
    pointer-events: none;
    transition: opacity $transition-fast;

    &.active {
      opacity: 1;
      pointer-events: auto;
    }
  }
}
</style>
