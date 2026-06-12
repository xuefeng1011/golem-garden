<script setup lang="ts">
import { onMounted } from "vue";
import {
  NTabs,
  NTabPane,
  NSpin,
  NAlert,
  NTag,
} from "naive-ui";
import { useI18n } from "vue-i18n";
import { useSettingsStore } from "@/stores/hermes/settings";
import DisplaySettings from "@/components/hermes/settings/DisplaySettings.vue";
import AgentSettings from "@/components/hermes/settings/AgentSettings.vue";
import MemorySettings from "@/components/hermes/settings/MemorySettings.vue";
import SessionSettings from "@/components/hermes/settings/SessionSettings.vue";
import PrivacySettings from "@/components/hermes/settings/PrivacySettings.vue";
import ModelSettings from "@/components/hermes/settings/ModelSettings.vue";

const settingsStore = useSettingsStore();
const { t } = useI18n();

onMounted(() => {
  settingsStore.fetchSettings();
});
</script>

<template>
  <div class="settings-view">
    <header class="page-header">
      <h2 class="header-title">{{ t("settings.title") }}</h2>
    </header>

    <div class="settings-content">
      <NAlert type="info" :show-icon="false" style="margin-bottom: 16px">
        <template #header>{{ t('settings.statusNote.title') }}</template>
        <ul style="margin: 4px 0 0 0; padding-left: 20px; font-size: 13px; line-height: 1.6">
          <li>{{ t('settings.statusNote.display') }}</li>
          <li>{{ t('settings.statusNote.others') }}</li>
        </ul>
      </NAlert>
      <NSpin
        :show="settingsStore.loading || settingsStore.saving"
        size="large"
        :description="t('common.loading')"
      >
        <NTabs type="line" animated>
          <NTabPane name="display" :tab="t('settings.tabs.display')">
            <DisplaySettings />
          </NTabPane>
          <NTabPane name="agent">
            <template #tab>
              <span class="tab-with-badge">
                {{ t('settings.tabs.agent') }}
                <NTag size="tiny" :bordered="false">{{ t('settings.comingSoon') }}</NTag>
              </span>
            </template>
            <AgentSettings />
          </NTabPane>
          <NTabPane name="memory">
            <template #tab>
              <span class="tab-with-badge">
                {{ t('settings.tabs.memory') }}
                <NTag size="tiny" :bordered="false">{{ t('settings.comingSoon') }}</NTag>
              </span>
            </template>
            <MemorySettings />
          </NTabPane>
          <NTabPane name="session">
            <template #tab>
              <span class="tab-with-badge">
                {{ t('settings.tabs.session') }}
                <NTag size="tiny" :bordered="false">{{ t('settings.comingSoon') }}</NTag>
              </span>
            </template>
            <SessionSettings />
          </NTabPane>
          <NTabPane name="privacy">
            <template #tab>
              <span class="tab-with-badge">
                {{ t('settings.tabs.privacy') }}
                <NTag size="tiny" :bordered="false">{{ t('settings.comingSoon') }}</NTag>
              </span>
            </template>
            <PrivacySettings />
          </NTabPane>
          <NTabPane name="models" :tab="t('settings.tabs.models')">
            <ModelSettings />
          </NTabPane>
        </NTabs>
      </NSpin>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use "@/styles/variables" as *;

.settings-view {
  height: calc(100 * var(--vh));
  display: flex;
  flex-direction: column;
}

.settings-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}

.tab-with-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
</style>
