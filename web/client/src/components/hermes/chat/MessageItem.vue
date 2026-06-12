<script setup lang="ts">
import type { Message } from "@/stores/hermes/chat";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { useMessage } from "naive-ui";
import { useProfilesStore } from "@/stores/hermes/profiles";
import { useChatStore } from "@/stores/hermes/chat";
import { copyToClipboard } from "@/utils/clipboard";
import { repairUnclosedFences } from "@/utils/fence-repair";
import MarkdownRenderer from "./MarkdownRenderer.vue";
import SoulHandoffCard from "./SoulHandoffCard.vue";
import {
  copyTextToClipboard,
  handleCodeBlockCopyClick,
  renderHighlightedCodeBlock,
} from "./highlight";

const TOOL_PAYLOAD_DISPLAY_LIMIT = 2000;

const props = defineProps<{ message: Message; highlight?: boolean }>();
const { t } = useI18n();
const toast = useMessage();

const profilesStore = useProfilesStore();
const chatStore = useChatStore();

const currentSoul = computed(() => {
  // Prefer active session's soul_id for correct per-tab attribution;
  // fall back to global default for sessions that pre-date this field.
  const sessionSoul = chatStore.activeSession?.soul_id;
  const targetId = sessionSoul || profilesStore.currentSoulId;
  return profilesStore.availableSouls.find(s => s.id === targetId) ?? null;
});

const isSystem = computed(() => props.message.role === "system");
const toolExpanded = ref(false);

// Streaming-only fence repair: while a reply is still streaming, an opening
// ``` may not have its closing fence yet — temporarily close it so the
// partial render doesn't swallow the rest of the message into a code block.
const renderContent = computed(() =>
  props.message.isStreaming
    ? repairUnclosedFences(props.message.content)
    : props.message.content,
);

// Whole-message copy (assistant bubbles): copies the raw markdown source.
const messageCopied = ref(false);
let messageCopiedTimer: ReturnType<typeof setTimeout> | null = null;

const showCopyButton = computed(
  () =>
    props.message.role === "assistant" &&
    !props.message.isStreaming &&
    !!props.message.content,
);

async function handleCopyMessage(): Promise<void> {
  const ok = await copyToClipboard(props.message.content || "");
  if (!ok) return;
  messageCopied.value = true;
  if (messageCopiedTimer) clearTimeout(messageCopiedTimer);
  messageCopiedTimer = setTimeout(() => {
    messageCopied.value = false;
    messageCopiedTimer = null;
  }, 1500);
}

const timeStr = computed(() => {
  const d = new Date(props.message.timestamp);
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
});

function isImage(type: string): boolean {
  return type.startsWith("image/");
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

/**
 * Extract the upload file path from message content for a given attachment.
 * Upload format in content: [File: name.txt](/tmp/hermes-uploads/abc123.txt)
 */
function getFilePathFromContent(attName: string): string | null {
  const content = props.message.content || "";
  const regex = /\[File:\s*([^\]]+)\]\(([^)]+)\)/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(content)) !== null) {
    if (match[1].trim() === attName.trim()) return match[2];
  }
  return null;
}

function handleAttachmentDownload(att: { name: string; url: string; type: string }) {
  const filePath = getFilePathFromContent(att.name);
  if (filePath) {
    // TODO(gateway): Gateway has no download endpoint; ignore for now.
    toast.info(t("download.downloading"));
    return;
  }
  if (att.url && att.url.startsWith("blob:")) {
    const a = document.createElement("a");
    a.href = att.url;
    a.download = att.name;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  }
}

type ToolPayload = {
  full: string;
  display: string;
  language?: string;
};

function formatToolPayload(raw?: string): ToolPayload {
  if (!raw) {
    return { full: "", display: "" };
  }

  try {
    const full = JSON.stringify(JSON.parse(raw), null, 2);
    return {
      full,
      display:
        full.length > TOOL_PAYLOAD_DISPLAY_LIMIT
          ? full.slice(0, TOOL_PAYLOAD_DISPLAY_LIMIT) + "\n" + t("chat.truncated")
          : full,
      language: "json",
    };
  } catch {
    return {
      full: raw,
      display:
        raw.length > TOOL_PAYLOAD_DISPLAY_LIMIT
          ? raw.slice(0, TOOL_PAYLOAD_DISPLAY_LIMIT) + "\n" + t("chat.truncated")
          : raw,
    };
  }
}

function renderToolPayload(content: string, language?: string): string {
  return renderHighlightedCodeBlock(content, language, t("common.copy"), {
    maxHighlightLength: TOOL_PAYLOAD_DISPLAY_LIMIT,
  });
}

async function handleToolDetailClick(event: MouseEvent): Promise<void> {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;

  const button = target.closest<HTMLElement>("[data-copy-code=\"true\"]");
  if (!button) return;

  event.preventDefault();

  const source = button.closest<HTMLElement>("[data-copy-source]")?.dataset.copySource;
  if (source === "tool-args" && fullToolArgs.value) {
    await copyTextToClipboard(fullToolArgs.value);
    return;
  }
  if (source === "tool-result" && fullToolResult.value) {
    await copyTextToClipboard(fullToolResult.value);
    return;
  }

  await handleCodeBlockCopyClick(event);
}

/** Parse toolArgs JSON for Task tool — returns null if not a Task or parse fails */
const taskInput = computed(() => {
  if (props.message.toolName !== 'Task') return null
  if (!props.message.toolArgs) return null
  try {
    return JSON.parse(props.message.toolArgs) as Record<string, unknown>
  } catch {
    return null
  }
})

const isTaskTool = computed(() => props.message.toolName === 'Task')

const hasAttachments = computed(
  () => (props.message.attachments?.length ?? 0) > 0,
);

const hasToolDetails = computed(
  () => !!(props.message.toolArgs || props.message.toolResult),
);

const toolArgsPayload = computed(() => formatToolPayload(props.message.toolArgs));
const toolResultPayload = computed(() => formatToolPayload(props.message.toolResult));

const fullToolArgs = computed(() => toolArgsPayload.value.full);
const formattedToolArgs = computed(() => toolArgsPayload.value.display);
const fullToolResult = computed(() => toolResultPayload.value.full);
const formattedToolResult = computed(() => toolResultPayload.value.display);

const renderedToolArgs = computed(() => {
  if (!formattedToolArgs.value) return "";
  return renderToolPayload(
    formattedToolArgs.value,
    toolArgsPayload.value.language,
  );
});

const renderedToolResult = computed(() => {
  if (!formattedToolResult.value) return "";
  return renderToolPayload(
    formattedToolResult.value,
    toolResultPayload.value.language,
  );
});
</script>

<template>
  <div
    class="message"
    :class="[message.role, { highlight }]"
    :id="`message-${message.id}`"
  >
    <template v-if="message.role === 'tool'">
      <!-- SOUL handoff card for Task tool -->
      <SoulHandoffCard
        v-if="isTaskTool"
        :task-input="taskInput"
        :result="message.toolResult"
        :is-error="message.toolStatus === 'error'"
        :running="message.toolStatus === 'running'"
      />
      <!-- Generic tool line for all other tools -->
      <template v-else>
        <div
          class="tool-line"
          :class="{ expandable: hasToolDetails }"
          @click="hasToolDetails && (toolExpanded = !toolExpanded)"
        >
          <svg
            v-if="hasToolDetails"
            width="10"
            height="10"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            class="tool-chevron"
            :class="{ rotated: toolExpanded }"
          >
            <polyline points="9 18 15 12 9 6" />
          </svg>
          <svg
            v-else
            width="12"
            height="12"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            class="tool-icon"
          >
            <path
              d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"
            />
          </svg>
          <span class="tool-name">{{ message.toolName }}</span>
          <span
            v-if="message.toolPreview && !toolExpanded"
            class="tool-preview"
            >{{ message.toolPreview }}</span
          >
          <span
            v-if="message.toolStatus === 'running'"
            class="tool-spinner"
          ></span>
          <span v-if="message.toolStatus === 'error'" class="tool-error-badge">{{
            t("chat.error")
          }}</span>
        </div>
        <div v-if="toolExpanded && hasToolDetails" class="tool-details" @click="handleToolDetailClick">
          <div v-if="formattedToolArgs" class="tool-detail-section" data-copy-source="tool-args">
            <div class="tool-detail-label">{{ t("chat.arguments") }}</div>
            <div class="tool-detail-code-block" v-html="renderedToolArgs"></div>
          </div>
          <div v-if="formattedToolResult" class="tool-detail-section" data-copy-source="tool-result">
            <div class="tool-detail-label">{{ t("chat.result") }}</div>
            <div class="tool-detail-code-block" v-html="renderedToolResult"></div>
          </div>
        </div>
      </template>
    </template>
    <template v-else>
      <div class="msg-body">
        <img
          v-if="message.role === 'assistant'"
          src="/logo.png"
          alt="Hermes"
          class="msg-avatar"
        />
        <div class="msg-content" :class="message.role">
          <div class="message-bubble" :class="{ system: isSystem }">
            <div v-if="message.role === 'assistant'" class="soul-attribution">
              <span class="soul-name">{{ currentSoul?.name ?? 'SOUL' }}</span>
              <span class="soul-dot">·</span>
              <span class="soul-rank" :class="`rank-${currentSoul?.rank ?? 'novice'}`">{{ currentSoul?.rank ?? 'novice' }}</span>
            </div>
            <div v-if="hasAttachments" class="msg-attachments">
              <div
                v-for="att in message.attachments"
                :key="att.id"
                class="msg-attachment"
                :class="{ image: isImage(att.type) }"
              >
                <template v-if="isImage(att.type) && att.url">
                  <img
                    :src="att.url"
                    :alt="att.name"
                    class="msg-attachment-thumb"
                  />
                </template>
                <template v-else>
                  <div class="msg-attachment-file" @click="handleAttachmentDownload(att)" style="cursor: pointer;" :title="t('download.downloadFile')">
                    <svg
                      width="16"
                      height="16"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="1.5"
                    >
                      <path
                        d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"
                      />
                      <polyline points="14 2 14 8 20 8" />
                    </svg>
                    <span class="att-name">{{ att.name }}</span>
                    <span class="att-size">{{ formatSize(att.size) }}</span>
                    <svg class="att-download-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                      <polyline points="7 10 12 15 17 10" />
                      <line x1="12" y1="15" x2="12" y2="3" />
                    </svg>
                  </div>
                </template>
              </div>
            </div>
            <MarkdownRenderer
              v-if="message.content"
              :content="renderContent"
            />

            <button
              v-if="showCopyButton"
              type="button"
              class="msg-copy-btn"
              :class="{ copied: messageCopied }"
              :title="messageCopied ? t('chat.messageCopied') : t('chat.copyMessage')"
              :aria-label="t('chat.copyMessage')"
              @click="handleCopyMessage"
            >
              <svg
                v-if="messageCopied"
                width="13"
                height="13"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.5"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <polyline points="20 6 9 17 4 12" />
              </svg>
              <svg
                v-else
                width="13"
                height="13"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
              </svg>
            </button>

            <span v-if="message.isStreaming && !message.content" class="streaming-dots">
              <span></span><span></span><span></span>
            </span>
          </div>
          <div class="message-time">{{ timeStr }}</div>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped lang="scss">
@use "@/styles/variables" as *;

.message {
  display: flex;
  flex-direction: column;

  &.user {
    align-items: flex-end;

    .msg-body {
      max-width: 75%;
    }

    .msg-content.user {
      align-items: flex-end;
    }

    .message-bubble {
      background-color: $msg-user-bg;
      border-radius: 10px;
    }
  }

  &.assistant {
    flex-direction: row;
    align-items: flex-start;
    gap: 8px;

    .msg-body {
      max-width: 80%;
    }

    .msg-avatar {
      width: 40px;
      height: 40px;
      flex-shrink: 0;
      margin-top: 2px;
    }

    .message-bubble {
      background-color: $msg-assistant-bg;
      border-radius: 10px;
    }
  }

  &.tool {
    align-items: flex-start;
  }

  &.system {
    align-items: flex-start;

    .message-bubble.system {
      border-left: 3px solid $warning;
      border-radius: $radius-sm;
      max-width: 80%;
      background-color: rgba(var(--warning-rgb), 0.06);
    }
  }

  &.highlight {
    .message-bubble {
      box-shadow: 0 0 0 1px rgba(var(--accent-primary-rgb), 0.45);
    }
  }
}

.msg-body {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  max-width: 85%;
}

.msg-content {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.message-bubble {
  position: relative;
  padding: 10px 14px;
  font-size: 14px;
  line-height: 1.65;
  word-break: break-word;
  border-radius: 10px;

  &:hover .msg-copy-btn,
  &:focus-within .msg-copy-btn {
    opacity: 1;
  }
}

.msg-copy-btn {
  position: absolute;
  top: 6px;
  right: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  padding: 0;
  border: 1px solid $border-light;
  border-radius: $radius-sm;
  background: $msg-assistant-bg;
  color: $text-muted;
  cursor: pointer;
  opacity: 0;
  transition: opacity 0.15s ease, color 0.15s ease;

  &:hover {
    color: $text-primary;
  }

  &.copied {
    color: $success;
    opacity: 1;
  }
}

.msg-attachments {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 8px;
}

.msg-attachment {
  border-radius: $radius-sm;
  overflow: hidden;
  background-color: rgba(0, 0, 0, 0.04);
  border: 1px solid $border-light;

  &.image {
    max-width: 200px;
  }
}

.msg-attachment-thumb {
  display: block;
  max-width: 200px;
  max-height: 160px;
  object-fit: contain;
}

.msg-attachment-file {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 10px;
  font-size: 12px;
  color: $text-secondary;

  .att-name {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 160px;
  }

  .att-size {
    color: $text-muted;
    font-size: 11px;
    flex-shrink: 0;
  }
}

.message-time {
  font-size: 11px;
  color: $text-muted;
  margin-top: 4px;
  padding: 0 4px;

  .dark & {
    color: #999999;
  }
}

.tool-line {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: $text-muted;
  padding: 2px 4px;
  border-radius: $radius-sm;

  &.expandable {
    cursor: pointer;

    &:hover {
      background: rgba(0, 0, 0, 0.03);
    }
  }

  .tool-name {
    font-family: $font-code;
    flex-shrink: 0;
  }

  .tool-preview {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 400px;
  }
}

.tool-chevron {
  flex-shrink: 0;
  transition: transform 0.15s ease;

  &.rotated {
    transform: rotate(90deg);
  }
}

.tool-spinner {
  width: 10px;
  height: 10px;
  border: 1.5px solid $text-muted;
  border-top-color: transparent;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
  flex-shrink: 0;
}

.tool-error-badge {
  font-size: 9px;
  color: $error;
  background: rgba(var(--error-rgb), 0.08);
  padding: 0 4px;
  border-radius: 3px;
  line-height: 14px;
}

.tool-details {
  margin-left: 16px;
  margin-top: 2px;
  border-left: 2px solid $border-light;
  padding-left: 10px;
}

.tool-detail-section {
  margin-bottom: 6px;
}

.tool-detail-label {
  font-size: 10px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  margin-bottom: 2px;
}

.tool-detail-code-block {
  :deep(.hljs-code-block) {
    margin: 0;
  }

  :deep(.code-header) {
    background: rgba(0, 0, 0, 0.02);
  }

  :deep(code.hljs) {
    font-size: 11px;
    max-height: 300px;
    overflow-y: auto;
    white-space: pre-wrap;
    word-break: break-word;
  }
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.streaming-cursor {
  display: inline-block;
  width: 2px;
  height: 1em;
  background-color: $text-muted;
  margin-left: 2px;
  vertical-align: text-bottom;
  animation: blink 0.8s infinite;
}

.streaming-dots {
  display: flex;
  gap: 4px;
  padding: 4px 0;

  span {
    width: 6px;
    height: 6px;
    background-color: $text-muted;
    border-radius: 50%;
    animation: pulse 1.4s infinite ease-in-out;

    &:nth-child(2) { animation-delay: 0.2s; }
    &:nth-child(3) { animation-delay: 0.4s; }
  }
}

@keyframes blink {
  0%,
  50% {
    opacity: 1;
  }
  51%,
  100% {
    opacity: 0;
  }
}

@keyframes pulse {
  0%,
  80%,
  100% {
    opacity: 0.3;
    transform: scale(0.8);
  }
  40% {
    opacity: 1;
    transform: scale(1);
  }
}

@media (max-width: $breakpoint-mobile) {
  .message.user .msg-body {
    max-width: 100%;
  }

  .message.assistant .msg-body {
    max-width: 100%;
  }

  .message.system .msg-body {
    max-width: 100%;
  }
}

.soul-attribution {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  margin-bottom: 6px;
  opacity: 0.75;
}

.soul-name {
  font-weight: 600;
  color: $text-secondary;
}

.soul-dot {
  color: $text-muted;
}

.soul-rank {
  font-size: 11px;
  font-weight: 500;

  &.rank-novice  { color: #888888; }
  &.rank-junior  { color: #4a90d9; }
  &.rank-senior  { color: #52a770; }
  &.rank-master  { color: #9b59b6; }
}
</style>
