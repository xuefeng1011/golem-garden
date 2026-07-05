<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { NButton, NModal, useMessage } from "naive-ui";
import { useAppStore } from "@/stores/hermes/app";
import ModelSelector from "./ModelSelector.vue";
import ProfileSelector from "./ProfileSelector.vue";
import LanguageSwitch from "./LanguageSwitch.vue";
import ThemeSwitch from "./ThemeSwitch.vue";
import { useSessionSearch } from '@/composables/useSessionSearch'
import { changelog } from "@/data/changelog";

const { t } = useI18n();
const message = useMessage();
const route = useRoute();
const router = useRouter();
const appStore = useAppStore();
const { openSessionSearch } = useSessionSearch();
const selectedKey = computed(() => route.name as string);
// Flow Studio 편집기(자식 라우트 hermes.flowStudio.editor)도 목록 항목의 active 로 간주
const isFlowStudioActive = computed(() => (route.name as string ?? '').startsWith('hermes.flowStudio'));

const collapsedGroups = reactive<Record<string, boolean>>({});

function toggleGroup(key: string) {
  collapsedGroups[key] = !collapsedGroups[key];
}

function isGroupCollapsed(key: string) {
  return !!collapsedGroups[key];
}

function handleNav(key: string) {
  router.push({ name: key });
}

async function handleUpdate() {
  const ok = await appStore.doUpdate();
  if (ok) {
    message.success(t('sidebar.updateSuccess'), { duration: 5000 });
  } else {
    message.error(t('sidebar.updateFailed'));
  }
}

// Changelog
const showChangelog = ref(false);

function openChangelog() {
  showChangelog.value = true;
}

function closeChangelog() {
  showChangelog.value = false;
}
</script>

<template>
  <aside class="sidebar" :class="{ open: appStore.sidebarOpen }">
    <div class="sidebar-logo" @click="router.push('/hermes/chat')">
      <svg width="24" height="24" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" class="logo-icon" aria-hidden="true">
        <rect width="64" height="64" rx="12" fill="#1a1a1a"/>
        <text x="32" y="44" text-anchor="middle" font-family="Inter, system-ui, sans-serif"
              font-weight="700" font-size="28" fill="#ffffff">GG</text>
      </svg>
      <span class="logo-text">GolemGarden</span>
    </div>

    <nav class="sidebar-nav">
      <!-- Overview (standalone) -->
      <button class="nav-item" :class="{ active: selectedKey === 'hermes.overview' }" @click="handleNav('hermes.overview')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="3" width="7" height="7" rx="1" />
          <rect x="14" y="3" width="7" height="7" rx="1" />
          <rect x="3" y="14" width="7" height="7" rx="1" />
          <rect x="14" y="14" width="7" height="7" rx="1" />
        </svg>
        <span>{{ t("sidebar.overview") }}</span>
      </button>

      <!-- Activity (standalone) -->
      <button class="nav-item" :class="{ active: selectedKey === 'hermes.activity' }" @click="handleNav('hermes.activity')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <line x1="8" y1="6" x2="21" y2="6" />
          <line x1="8" y1="12" x2="21" y2="12" />
          <line x1="8" y1="18" x2="21" y2="18" />
          <circle cx="3" cy="6" r="1" fill="currentColor" stroke="none" />
          <circle cx="3" cy="12" r="1" fill="currentColor" stroke="none" />
          <circle cx="3" cy="18" r="1" fill="currentColor" stroke="none" />
        </svg>
        <span>{{ t("sidebar.activity") }}</span>
      </button>

      <!-- Forge -->
      <button class="nav-item" :class="{ active: selectedKey === 'hermes.forge' }" @click="handleNav('hermes.forge')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z" />
        </svg>
        <span>{{ t("sidebar.forge") }}</span>
      </button>

      <!-- Team Board -->
      <button class="nav-item" :class="{ active: selectedKey === 'hermes.team' }" @click="handleNav('hermes.team')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="3" width="18" height="4" rx="1" />
          <rect x="3" y="10" width="18" height="4" rx="1" />
          <rect x="3" y="17" width="11" height="4" rx="1" />
        </svg>
        <span>{{ t("sidebar.team") }}</span>
      </button>

      <!-- Growth (Achievements & Chemistry) -->
      <button class="nav-item" :class="{ active: selectedKey === 'hermes.meta' }" @click="handleNav('hermes.meta')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
        </svg>
        <span>{{ t("sidebar.growth") }}</span>
      </button>

      <!-- Chat (standalone) -->
      <button class="nav-item" :class="{ active: selectedKey === 'hermes.chat' }" @click="handleNav('hermes.chat')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
        </svg>
        <span>{{ t("sidebar.chat") }}</span>
      </button>

      <button class="nav-item" @click="openSessionSearch">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="11" cy="11" r="7" />
          <path d="m20 20-3.5-3.5" />
        </svg>
        <span>{{ t("sidebar.search") }}</span>
      </button>

      <!-- Agent -->
      <div class="nav-group">
        <div class="nav-group-label" @click="toggleGroup('agent')">
          <span>{{ t("sidebar.groupAgent") }}</span>
          <svg class="nav-group-arrow" :class="{ collapsed: isGroupCollapsed('agent') }" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="6 9 12 15 18 9" />
          </svg>
        </div>
        <div v-show="!isGroupCollapsed('agent')">
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.skills' }" @click="handleNav('hermes.skills')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <polygon points="12 2 2 7 12 12 22 7 12 2" />
              <polyline points="2 17 12 22 22 17" />
              <polyline points="2 12 12 17 22 12" />
            </svg>
            <span>{{ t("sidebar.skills") }}</span>
          </button>
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.models' }" @click="handleNav('hermes.models')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="3" />
              <path d="M12 1v4" />
              <path d="M12 19v4" />
              <path d="M1 12h4" />
              <path d="M19 12h4" />
              <path d="M4.22 4.22l2.83 2.83" />
              <path d="M16.95 16.95l2.83 2.83" />
              <path d="M4.22 19.78l2.83-2.83" />
              <path d="M16.95 7.05l2.83-2.83" />
            </svg>
            <span>{{ t("sidebar.models") }}</span>
          </button>
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.souls' }" @click="handleNav('hermes.souls')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
              <circle cx="9" cy="7" r="4" />
              <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
              <path d="M16 3.13a4 4 0 0 1 0 7.75" />
            </svg>
            <span>{{ t("sidebar.souls") }}</span>
          </button>
        </div>
      </div>

      <!-- Monitoring -->
      <div class="nav-group">
        <div class="nav-group-label" @click="toggleGroup('monitoring')">
          <span>{{ t("sidebar.groupMonitoring") }}</span>
          <svg class="nav-group-arrow" :class="{ collapsed: isGroupCollapsed('monitoring') }" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="6 9 12 15 18 9" />
          </svg>
        </div>
        <div v-show="!isGroupCollapsed('monitoring')">
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.usage' }" @click="handleNav('hermes.usage')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <rect x="3" y="12" width="4" height="9" rx="1" />
              <rect x="10" y="7" width="4" height="14" rx="1" />
              <rect x="17" y="3" width="4" height="18" rx="1" />
            </svg>
            <span>{{ t("sidebar.usage") }}</span>
          </button>
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.console' }" @click="handleNav('hermes.console')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <rect x="2" y="4" width="20" height="16" rx="2" />
              <polyline points="8 10 5 13 8 16" />
              <line x1="12" y1="16" x2="19" y2="16" />
            </svg>
            <span>{{ t("sidebar.console") }}</span>
          </button>
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.canvas' }" @click="handleNav('hermes.canvas')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="5" cy="12" r="2" />
              <circle cx="19" cy="5" r="2" />
              <circle cx="19" cy="19" r="2" />
              <line x1="7" y1="11" x2="17" y2="6" />
              <line x1="7" y1="13" x2="17" y2="18" />
            </svg>
            <span>{{ t("sidebar.canvas") }}</span>
          </button>
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.flowEditor' }" @click="handleNav('hermes.flowEditor')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <rect x="3" y="8" width="5" height="5" rx="1" />
              <rect x="16" y="3" width="5" height="5" rx="1" />
              <rect x="16" y="16" width="5" height="5" rx="1" />
              <line x1="8" y1="10.5" x2="16" y2="5.5" />
              <line x1="8" y1="10.5" x2="16" y2="18.5" />
            </svg>
            <span>{{ t("sidebar.flowEditor") }}</span>
          </button>
          <button class="nav-item" :class="{ active: isFlowStudioActive }" @click="handleNav('hermes.flowStudio')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <rect x="3" y="3" width="18" height="18" rx="2" />
              <path d="M3 9h18" />
              <path d="M9 21V9" />
            </svg>
            <span>{{ t("sidebar.flowStudio") }}</span>
          </button>
        </div>
      </div>

      <!-- System -->
      <div class="nav-group">
        <div class="nav-group-label" @click="toggleGroup('system')">
          <span>{{ t("sidebar.groupSystem") }}</span>
          <svg class="nav-group-arrow" :class="{ collapsed: isGroupCollapsed('system') }" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="6 9 12 15 18 9" />
          </svg>
        </div>
        <div v-show="!isGroupCollapsed('system')">
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.profiles' }" @click="handleNav('hermes.profiles')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
              <circle cx="12" cy="7" r="4" />
            </svg>
            <span>{{ t("sidebar.profiles") }}</span>
          </button>
          <button class="nav-item" :class="{ active: selectedKey === 'hermes.settings' }" @click="handleNav('hermes.settings')">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
            </svg>
            <span>{{ t("sidebar.settings") }}</span>
          </button>
        </div>
      </div>
    </nav>

    <ProfileSelector />
    <ModelSelector />

    <div class="sidebar-footer">
      <div class="status-row">
        <div
          class="status-indicator"
          :class="{
            connected: appStore.connected,
            disconnected: !appStore.connected,
          }"
        >
          <span class="status-dot"></span>
          <span class="status-text">{{
            appStore.connected
              ? t("sidebar.connected")
              : t("sidebar.disconnected")
          }}</span>
        </div>
        <LanguageSwitch />
      </div>
      <div class="version-info">
        <a class="github-link" href="https://github.com/EKKOLearnAI/hermes-web-ui" target="_blank" rel="noopener noreferrer" title="GitHub">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/></svg>
        </a>
        <span class="version-text" @click="openChangelog">GolemGarden v{{ appStore.serverVersion || "0.1.0" }}</span>
        <ThemeSwitch />
      </div>
      <NButton v-if="appStore.updateAvailable" type="primary" size="tiny" block class="update-btn" :loading="appStore.updating" @click="handleUpdate">
        {{ appStore.updating ? t('sidebar.updating') : t('sidebar.updateVersion', { version: appStore.latestVersion }) }}
      </NButton>
    </div>

    <!-- Changelog modal -->
    <NModal
      :show="showChangelog"
      preset="dialog"
      :title="t('sidebar.changelog')"
      style="width: 520px;"
      @update:show="(v: boolean) => { if (!v) closeChangelog() }"
    >
      <div class="changelog-list">
        <div v-for="entry in changelog" :key="entry.version" class="changelog-version-block">
          <div class="changelog-version-header">
            <span class="changelog-version-tag">v{{ entry.version }}</span>
            <span class="changelog-date">{{ entry.date }}</span>
          </div>
          <ul class="changelog-changes">
            <li v-for="(change, idx) in entry.changes" :key="idx">{{ t(change) }}</li>
          </ul>
        </div>
      </div>
    </NModal>
  </aside>
</template>

<style scoped lang="scss">
@use "@/styles/variables" as *;

.sidebar {
  width: $sidebar-width;
  height: calc(100 * var(--vh));
  background-color: $bg-sidebar;
  border-right: 1px solid $border-color;
  display: flex;
  flex-direction: column;
  padding: 0 12px 20px;
  flex-shrink: 0;
  transition: width $transition-normal;
}

.logo-icon {
  width: 24px;
  height: 24px;
  flex-shrink: 0;
  border-radius: 6px;
}

.sidebar-logo {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 20px 12px;
  margin: 0 -12px;
  color: $text-primary;
  cursor: pointer;
  background-color: $bg-card;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);

  .dark & {
    background-color: #393939;
  }
  position: relative;
  overflow: hidden;

  .logo-text {
    font-size: 18px;
    font-weight: 600;
    letter-spacing: 0.5px;
  }

  .logo-dance {
    position: absolute;
    right: 12px;
    top: 50%;
    transform: translateY(-50%);
    height: 100px;
    border-radius: $radius-md;
    object-fit: contain;
    flex-shrink: 0;
    width: auto;
    pointer-events: none;
  }
}

.sidebar-nav {
  flex: 1;
  display: flex;
  padding-top: 12px;
  flex-direction: column;
  gap: 6px;
  overflow-y: auto;
  min-height: 0;
  scrollbar-width: none;

  &::-webkit-scrollbar {
    display: none;
  }
}

.nav-group {
  display: flex;
  flex-direction: column;
  gap: 2px;

  &.nav-group-bottom {
    margin-top: auto;
    padding-top: 8px;
    border-top: 1px solid $border-color;
  }
}

.nav-group-label {
  font-size: 10px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.8px;
  padding: 8px 12px 4px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  cursor: pointer;
  user-select: none;
  border-radius: $radius-sm;
  transition: color $transition-fast;

  &:hover {
    color: $text-secondary;
  }

  .nav-group:first-child & {
    padding-top: 0;
  }
}

.nav-group-arrow {
  transition: transform $transition-fast;
  flex-shrink: 0;

  &.collapsed {
    transform: rotate(-90deg);
  }
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px;
  border: none;
  background: none;
  color: $text-secondary;
  font-size: 14px;
  border-radius: $radius-sm;
  cursor: pointer;
  transition: all $transition-fast;
  width: 100%;
  text-align: left;

  &:hover {
    background-color: rgba(var(--accent-primary-rgb), 0.06);
    color: $text-primary;
  }

  &.active {
    background-color: rgba(var(--accent-primary-rgb), 0.12);
    color: $accent-primary;
  }
}

.sidebar-footer {
  padding-top: 8px;
  border-top: 1px solid $border-color;
}

.logout-item {
  margin: 0 -12px;
  padding: 10px 12px;
  border-radius: 0;
  font-size: 13px;
  color: $text-muted;

  &:hover {
    color: $error;
    background: rgba(var(--error-rgb, 239, 68, 68), 0.06);
  }
}

.status-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 12px;
}

.status-indicator {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;

  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  &.connected .status-dot {
    background-color: $success;
    box-shadow: 0 0 6px rgba(var(--success-rgb), 0.5);
  }

  &.disconnected .status-dot {
    background-color: $error;
  }

  .status-text {
    color: $text-secondary;
  }
}

.version-info {
  padding: 2px 12px 8px;
  font-size: 11px;
  color: $text-muted;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.github-link {
  color: $text-muted;
  display: flex;
  align-items: center;
  transition: color 0.2s;

  &:hover {
    color: $text-primary;
  }
}

.update-btn {
  margin: 4px 0 0;
  border-radius: 4px;
}

.version-text {
  cursor: pointer;
  transition: color 0.2s;

  &:hover {
    color: $accent-primary;
  }
}

.changelog-list {
  max-height: 400px;
  overflow-y: auto;
}

.changelog-version-block {
  margin-bottom: 20px;

  &:last-child {
    margin-bottom: 0;
  }
}

.changelog-version-header {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}

.changelog-version-tag {
  font-weight: 600;
  font-size: 14px;
  color: $text-primary;
  font-family: $font-code;
}

.changelog-changes {
  list-style: none;
  padding: 0;
  margin: 0;

  li {
    font-size: 13px;
    color: $text-secondary;
    padding: 4px 0 4px 16px;
    position: relative;

    &::before {
      content: '';
      position: absolute;
      left: 0;
      top: 12px;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: $text-muted;
    }
  }
}

@media (max-width: $breakpoint-mobile) {
  .logo-dance {
    display: none;
  }

  .status-row {
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }

  .sidebar {
    position: fixed;
    left: 0;
    top: 0;
    z-index: 1000;
    transform: translateX(-100%);
    transition: transform $transition-normal;

    &.open {
      transform: translateX(0);
    }

    // Override global utility — sidebar is always 240px wide
    .input-sm {
      width: 90px;
    }
  }
}
</style>
