<script setup lang="ts">
import { ref, computed, watch, nextTick } from "vue";
import { useI18n } from "vue-i18n";
import MessageItem from "./MessageItem.vue";
import OutlinePanel from "./OutlinePanel.vue";
import { useChatStore } from "@/stores/hermes/chat";
import { useProfilesStore } from "@/stores/hermes/profiles";
import { extractOutline, type OutlineItem } from "@/utils/outline";
import {
  initialWindowState,
  hiddenCount,
  expandWindow,
  applyWindow,
  type WindowState,
} from "@/utils/message-window";

const chatStore = useChatStore();
const profilesStore = useProfilesStore();
const { t } = useI18n();
const listRef = ref<HTMLElement>();

const activeSoul = computed(() => {
  const soulId = chatStore.activeSession?.soul_id || profilesStore.currentSoulId;
  return profilesStore.availableSouls.find(s => s.id === soulId) ?? null;
});

// Show GolemGarden thinking indicator while a run is active but no assistant
// message has arrived yet for the current turn. Once the first delta lands
// (last message is assistant), the bubble itself shows streaming content.
// Tool messages also indicate the model is actively producing, so treat them
// the same as assistant — hide the indicator to avoid flicker between tool calls.
const showThinking = computed(() => {
  if (!chatStore.isRunActive) return false;
  const msgs = chatStore.messages;
  if (msgs.length === 0) return true;
  const last = msgs[msgs.length - 1];
  // Only show during the initial pre-first-event window (last msg is user or system).
  return last.role === "user" || last.role === "system";
});

const allDisplayMessages = computed(() =>
  chatStore.messages.filter((m) => m.role !== "tool"),
);

// --- Message windowing ---
// window tracks which slice of allDisplayMessages is currently rendered.
// Reset on session change; expand on user request (scroll anchor preserved).
const windowState = ref<WindowState>(
  initialWindowState(allDisplayMessages.value.length),
);

// Reset window whenever the active session changes.
watch(
  () => chatStore.activeSessionId,
  () => {
    windowState.value = initialWindowState(allDisplayMessages.value.length);
  },
);

// When new messages arrive (e.g. user sends a message), keep the tail visible
// by re-anchoring the window to the end — but only if we were already showing
// the tail (startIndex === 0 after accounting for growth means "all visible").
watch(
  () => allDisplayMessages.value.length,
  (newLen, oldLen) => {
    if (newLen <= oldLen) return;
    const ws = windowState.value;
    // If the window already starts at 0 (all shown), keep it that way.
    // If window is anchored to the tail, re-anchor to the new tail.
    const wasAtTail = ws.startIndex === Math.max(0, oldLen - 80);
    if (wasAtTail) {
      windowState.value = initialWindowState(newLen);
    }
  },
);

const olderCount = computed(() => hiddenCount(windowState.value));
const showOlderButton = computed(() => olderCount.value > 0);

const displayMessages = computed(() =>
  applyWindow(allDisplayMessages.value, windowState.value),
);

// Load older messages: preserve scroll position by scrolling to the element
// that was previously first in the rendered list (scroll anchor).
function handleShowOlder() {
  // Capture the first currently-rendered message id before expanding.
  const firstVisible = displayMessages.value[0];
  windowState.value = expandWindow(windowState.value);
  if (!firstVisible) return;
  nextTick(() => {
    const el = document.getElementById(`message-${firstVisible.id}`);
    if (el) {
      el.scrollIntoView({ block: "start" });
    }
  });
}

const currentToolCalls = computed(() => {
  const msgs = chatStore.messages;
  // Find the last user message index
  let lastUserIdx = -1;
  for (let i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].role === "user") {
      lastUserIdx = i;
      break;
    }
  }
  // Only tool calls after the last user message, newest on top
  const tools = msgs.filter((m, i) => m.role === "tool" && i > lastUserIdx);
  return [...tools].reverse();
});

// Aggregated outline of all assistant messages, reactive to streaming
// content updates. Hidden until at least 5 headings exist (auto-hide).
const outlineItems = computed<OutlineItem[]>(() =>
  chatStore.messages
    .filter((m) => m.role === "assistant" && m.content)
    .flatMap((m) => extractOutline(m.content, m.id)),
);

const showOutline = computed(() => outlineItems.value.length >= 5);

// Rendered markdown carries no per-heading anchors, so navigate in two
// steps: jump to the message container by id, then correct to the Nth
// h1–h3 element inside it (same order as extractOutline emits).
function handleOutlineNavigate(item: OutlineItem) {
  const container = document.getElementById(`message-${item.messageId}`);
  if (!container) return;
  const headings = container.querySelectorAll("h1, h2, h3");
  const target = headings[item.headingIndex] ?? container;
  target.scrollIntoView({ behavior: "smooth", block: "start" });
}

function isNearBottom(threshold = 200): boolean {
  const el = listRef.value;
  if (!el) return true;
  return el.scrollHeight - el.scrollTop - el.clientHeight < threshold;
}

function scrollToBottom() {
  nextTick(() => {
    if (listRef.value) {
      listRef.value.scrollTop = listRef.value.scrollHeight;
    }
  });
}

function scrollToMessage(messageId: string) {
  nextTick(() => {
    const el = document.getElementById(`message-${messageId}`);
    if (el) {
      el.scrollIntoView({ block: 'center' });
    }
  });
}

// Scroll to bottom once when messages are first loaded
watch(
  () => chatStore.activeSessionId,
  (id) => {
    if (!id) return;
    if (chatStore.focusMessageId) {
      scrollToMessage(chatStore.focusMessageId);
      return;
    }
    scrollToBottom();
  },
  { immediate: true },
);

watch(
  () => chatStore.focusMessageId,
  (messageId) => {
    if (!messageId) return;
    scrollToMessage(messageId);
  },
);

// When a run starts (user just sent a message), always scroll to bottom once
watch(
  () => chatStore.isRunActive,
  (v) => {
    if (v) scrollToBottom();
  },
);

// During streaming, only auto-scroll if the user is already near the bottom
watch(
  () => chatStore.messages[chatStore.messages.length - 1]?.content,
  () => {
    if (chatStore.focusMessageId) {
      scrollToMessage(chatStore.focusMessageId);
      return;
    }
    if (!chatStore.isStreaming) { scrollToBottom(); return; }
    if (!isNearBottom()) return;
    scrollToBottom();
  },
);
watch(currentToolCalls, () => {
  if (chatStore.focusMessageId) {
    scrollToMessage(chatStore.focusMessageId);
    return;
  }
  if (!chatStore.isStreaming) { scrollToBottom(); return; }
  if (!isNearBottom()) return;
  scrollToBottom();
});
</script>

<template>
  <div class="message-list-wrap">
    <div ref="listRef" class="message-list">
    <div v-if="chatStore.messages.length === 0" class="empty-state">
      <img src="/logo.png" alt="Hermes" class="empty-logo" />
      <p>{{ t("chat.emptyState") }}</p>
    </div>
    <button
      v-if="showOlderButton"
      class="show-older-btn"
      type="button"
      @click="handleShowOlder"
    >
      {{ t("chat.showOlder", { n: olderCount }) }}
    </button>
    <MessageItem
      v-for="msg in displayMessages"
      :key="msg.id"
      :message="msg"
      :highlight="chatStore.focusMessageId === msg.id"
    />
    <Transition name="fade">
      <div v-if="chatStore.isRunActive" class="streaming-indicator">
        <div v-if="showThinking" class="thinking-indicator">
          <span class="dot" :class="`rank-${activeSoul?.rank || 'novice'}`"></span>
          <span class="thinking-text">{{ activeSoul?.name || 'SOUL' }} 생각 중...</span>
        </div>
        <div v-if="currentToolCalls.length > 0" class="tool-calls-panel">
          <div
            v-for="tc in currentToolCalls"
            :key="tc.id"
            class="tool-call-item"
          >
            <svg
              width="12"
              height="12"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              class="tool-call-icon"
              aria-hidden="true"
            >
              <path
                d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"
              />
            </svg>
            <span class="tool-call-name">{{ tc.toolName }}</span>
            <span v-if="tc.toolPreview" class="tool-call-preview">{{
              tc.toolPreview
            }}</span>
            <span
              v-if="tc.toolStatus === 'running'"
              class="tool-call-spinner"
              aria-hidden="true"
            ></span>
            <span v-if="tc.toolStatus === 'error'" class="tool-call-error">{{
              t("chat.error")
            }}</span>
          </div>
        </div>
      </div>
    </Transition>
    </div>
    <OutlinePanel
      v-if="showOutline"
      :items="outlineItems"
      @navigate="handleOutlineNavigate"
    />
  </div>
</template>

<style scoped lang="scss">
@use "@/styles/variables" as *;

// Wrapper keeps `flex: 1` for ChatPanel's column layout while providing a
// non-scrolling positioning context for the OutlinePanel overlay (an
// absolute child of the scroll container itself would scroll with content).
.message-list-wrap {
  flex: 1;
  min-height: 0;
  position: relative;
  display: flex;
}

.message-list {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 16px;
  background-color: $bg-card;

  .dark & {
    background-color: #333333;
  }
}

.show-older-btn {
  align-self: center;
  padding: 5px 14px;
  font-size: 12px;
  color: $text-secondary;
  background: $bg-card;
  border: 1px solid $border-light;
  border-radius: $radius-md;
  cursor: pointer;
  transition: background 0.15s ease, color 0.15s ease;
  flex-shrink: 0;

  &:hover {
    background: $bg-secondary;
    color: $text-primary;
  }

  .dark & {
    background: #3a3a3a;
    border-color: rgba(255, 255, 255, 0.12);

    &:hover {
      background: #444444;
    }
  }
}

.empty-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: $text-muted;
  gap: 12px;

  .empty-logo {
    width: 48px;
    height: 48px;
    opacity: 0.25;
  }

  p {
    font-size: 14px;
  }
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.4s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.streaming-indicator {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 4px 0;
}

.thinking-indicator {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  font-size: 13px;
  opacity: 0.85;

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
    animation: thinking-pulse 1.5s ease-in-out infinite;

    &.rank-novice { background: #888888; }
    &.rank-junior { background: #4a9eff; }
    &.rank-senior { background: #52a770; }
    &.rank-master { background: #a855f7; }
  }

  .thinking-text {
    color: $text-secondary;
  }
}

.tool-calls-panel {
  display: flex;
  flex-direction: column;
  gap: 4px;
  max-height: 213px;
  overflow-y: auto;
  padding-top: 4px;
  scrollbar-width: none;
  -ms-overflow-style: none;
  &::-webkit-scrollbar {
    display: none;
  }
}

.tool-call-item {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: $text-secondary;
  padding: 3px 8px;
  background: rgba(0, 0, 0, 0.03);
  border-radius: $radius-sm;

  .dark & {
    background: rgba(255, 255, 255, 0.06);
  }

  .tool-call-icon {
    flex-shrink: 0;
    color: $text-muted;
  }

  .tool-call-name {
    font-family: $font-code;
    flex-shrink: 0;
  }

  .tool-call-preview {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 300px;
    color: $text-muted;
  }
}

.tool-call-spinner {
  width: 10px;
  height: 10px;
  border: 1.5px solid $text-muted;
  border-top-color: transparent;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
  flex-shrink: 0;
}

.tool-call-error {
  font-size: 9px;
  color: $error;
  background: rgba($error, 0.08);
  padding: 0 4px;
  border-radius: 3px;
  line-height: 14px;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

@keyframes thinking-pulse {
  0%, 100% { opacity: 0.4; transform: scale(1); }
  50% { opacity: 1; transform: scale(1.3); }
}
</style>
