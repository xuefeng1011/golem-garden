<script setup lang="ts">
/**
 * StepFormPanel — right-side panel shown when an editor node is selected.
 * Emits update events; parent replaces node.data (shallowRef — G7).
 *
 * kind=input : textarea(task=입력값) 만 표시
 * kind=agent : 기존 폼 + 상류 단계 참조 칩
 */
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  NForm,
  NFormItem,
  NInput,
  NInputNumber,
  NSelect,
  NSwitch,
  NIcon,
} from 'naive-ui'
import { CloseOutline, AlertCircleOutline } from '@vicons/ionicons5'
import type { EditorNodeData } from '@/utils/canvas-graph'
import { resolveTaskPreview } from '@/utils/canvas-graph'
import type { Soul } from '@/api/hermes/souls'

const props = defineProps<{
  data: EditorNodeData
  souls: Soul[]
  allStepOptions: { label: string; value: string }[]
  // stepId -> 단계 출력 (해석된 입력 미리보기·출력 표시용)
  outputMap?: Record<string, string>
}>()

const emit = defineEmits<{
  (e: 'update', patch: Partial<EditorNodeData>): void
  (e: 'close'): void
  (e: 'delete'): void
  (e: 'view-result', runId: string): void
}>()

const { t } = useI18n()

// 입력 노드 여부
const isInput = computed(() => props.data.kind === 'input')

// 선택된 소울이 위임 전용 Director(쓰기 도구 없음)인지 — 콘텐츠 생성을 직접 못 해
// 헤드리스 실행 시 위임만 시도하며 공회전한다. 에이전트 단계에 배정되면 경고.
const isDirectorSoul = computed(() => {
  if (isInput.value) return false
  const soul = props.souls.find((s) => s.id === props.data.soul)
  return soul?.is_coordinator === true
})

// task 에 {{단계}} 참조가 있는지
const hasRef = computed(() => /\{\{[A-Za-z0-9_-]+\}\}/.test(props.data.task ?? ''))

// 해석된 입력(미리보기): {{id}} 를 상류 출력으로 치환한 결과 (엔진 _flow_subst 미러)
const resolvedInput = computed(() =>
  resolveTaskPreview(props.data.task ?? '', props.outputMap ?? {}),
)

// 이 단계의 출력 (실행 후 state.json 에 저장된 산출 텍스트)
const stepOutput = computed(() => props.data.output ?? '')

// soul options: empty = host
const soulOptions = computed(() => [
  { label: t('flowEditor.soulHost'), value: '' },
  ...props.souls.map((s) => ({ label: s.name, value: s.id })),
])

const onFailOptions = computed(() => [
  { label: t('flowEditor.onFailAbort'), value: 'abort' },
  { label: t('flowEditor.onFailContinue'), value: 'continue' },
  { label: t('flowEditor.onFailGoto'), value: '__goto__' },
])

// Derive whether current on_fail is a goto
const isGoto = computed(() => props.data.on_fail?.startsWith('goto:'))
const gotoTarget = computed(() =>
  isGoto.value ? props.data.on_fail.slice('goto:'.length) : '',
)

const onFailSelectValue = computed(() =>
  isGoto.value ? '__goto__' : (props.data.on_fail ?? 'abort'),
)

// goto step options: all steps except self
const gotoOptions = computed(() =>
  props.allStepOptions.filter((opt) => opt.value !== props.data.stepId),
)

// 상류 단계 칩: 자기 자신 제외 전체 단계 (에이전트 노드용 참조 삽입)
const upstreamOptions = computed(() =>
  props.allStepOptions.filter((opt) => opt.value !== props.data.stepId),
)

function onSoulChange(val: string) {
  emit('update', { soul: val })
}

function onTaskChange(val: string) {
  emit('update', {
    task: val,
    label: val.length > 40 ? val.slice(0, 37) + '…' : val,
  })
}

function onRetryChange(val: number | null) {
  emit('update', { retry: val ?? 0 })
}

function onApprovalChange(val: boolean) {
  emit('update', { approval: val })
}

function onOnFailChange(val: string) {
  if (val === '__goto__') {
    emit('update', { on_fail: 'goto:' })
  } else {
    emit('update', { on_fail: val })
  }
}

function onGotoTargetChange(val: string) {
  emit('update', { on_fail: `goto:${val}` })
}

// 참조 칩 클릭 — task 끝에 {{stepId}} 삽입
function insertRef(stepId: string) {
  const current = props.data.task ?? ''
  const ref = `{{${stepId}}}`
  const newTask = current ? `${current} ${ref}` : ref
  emit('update', {
    task: newTask,
    label: newTask.length > 40 ? newTask.slice(0, 37) + '…' : newTask,
  })
}
</script>

<template>
  <aside class="step-form-panel">
    <header class="panel-header">
      <span class="panel-title">{{ t('flowEditor.stepDetail') }}</span>
      <button class="close-btn" :title="t('common.cancel')" @click="emit('close')">
        <NIcon :size="16"><CloseOutline /></NIcon>
      </button>
    </header>

    <!-- ── 입력 노드 폼 ── -->
    <NForm v-if="isInput" label-placement="top" class="panel-form" size="small">
      <NFormItem
        :label="t('flowEditor.inputValueLabel')"
        :feedback="data.hasError ? t('flowEditor.taskRequired') : undefined"
        :validation-status="data.hasError ? 'error' : undefined"
      >
        <NInput
          :value="data.task"
          type="textarea"
          :rows="4"
          :placeholder="t('flowEditor.inputValuePlaceholder')"
          @update:value="onTaskChange"
        />
      </NFormItem>
    </NForm>

    <!-- ── 에이전트 노드 폼 ── -->
    <NForm v-else label-placement="top" class="panel-form" size="small">
      <!-- SOUL -->
      <NFormItem :label="t('flowEditor.labelSoul')">
        <NSelect
          :value="data.soul"
          :options="soulOptions"
          :placeholder="t('flowEditor.soulHost')"
          clearable
          @update:value="onSoulChange"
        />
      </NFormItem>

      <!-- Director(위임 전용) 소울 경고 — 콘텐츠 단계엔 쓰기 가능한 소울 권장 -->
      <div v-if="isDirectorSoul" class="soul-warning">
        <NIcon :size="14"><AlertCircleOutline /></NIcon>
        <span>{{ t('flowEditor.directorWarning') }}</span>
      </div>

      <!-- Task content -->
      <NFormItem
        :label="t('flowEditor.labelTask')"
        :feedback="data.hasError ? t('flowEditor.taskRequired') : undefined"
        :validation-status="data.hasError ? 'error' : undefined"
      >
        <NInput
          :value="data.task"
          type="textarea"
          :rows="3"
          :placeholder="t('flowEditor.taskPlaceholder')"
          @update:value="onTaskChange"
        />
      </NFormItem>

      <!-- 상류 단계 참조 칩 -->
      <div v-if="upstreamOptions.length > 0" class="ref-chips-section">
        <div class="ref-chips-label">{{ t('flowEditor.refChipsLabel') }}</div>
        <div class="ref-chips">
          <button
            v-for="opt in upstreamOptions"
            :key="opt.value"
            class="ref-chip"
            :title="`{{${opt.value}}}`"
            @click="insertRef(opt.value)"
          >
            {{ opt.label }}
          </button>
        </div>
        <div class="ref-hint">{{ t('flowEditor.insertRefHint') }}</div>
      </div>

      <!-- Retry -->
      <NFormItem :label="t('flowEditor.labelRetry')">
        <NInputNumber
          :value="data.retry ?? 1"
          :min="0"
          :max="3"
          @update:value="onRetryChange"
        />
      </NFormItem>

      <!-- Approval gate -->
      <NFormItem :label="t('flowEditor.labelApproval')">
        <NSwitch
          :value="data.approval"
          @update:value="onApprovalChange"
        />
      </NFormItem>

      <!-- On fail -->
      <NFormItem :label="t('flowEditor.labelOnFail')">
        <NSelect
          :value="onFailSelectValue"
          :options="onFailOptions"
          @update:value="onOnFailChange"
        />
      </NFormItem>

      <!-- Goto target (only when on_fail is goto) -->
      <NFormItem v-if="isGoto" :label="t('flowEditor.labelGotoStep')">
        <NSelect
          :value="gotoTarget"
          :options="gotoOptions"
          :placeholder="t('flowEditor.gotoPlaceholder')"
          @update:value="onGotoTargetChange"
        />
      </NFormItem>
    </NForm>

    <!-- ── 실행 입출력(에이전트 노드) ── -->
    <div v-if="!isInput && (hasRef || stepOutput)" class="io-section">
      <!-- 해석된 입력: {{id}} 가 실제 무엇으로 치환됐는지 -->
      <div v-if="hasRef" class="io-block">
        <div class="io-label">{{ t('flowEditor.resolvedInputLabel') }}</div>
        <pre class="io-text io-text--in">{{ resolvedInput }}</pre>
      </div>
      <!-- 이 단계가 낸 출력 -->
      <div v-if="stepOutput" class="io-block">
        <div class="io-label">{{ t('flowEditor.outputLabel') }}</div>
        <pre class="io-text io-text--out">{{ stepOutput }}</pre>
      </div>
    </div>

    <!-- 입력 노드: 이 값이 하류로 흐른다는 안내 -->
    <div v-else-if="isInput && stepOutput" class="io-section">
      <div class="io-block">
        <div class="io-label">{{ t('flowEditor.outputLabel') }}</div>
        <pre class="io-text io-text--out">{{ stepOutput }}</pre>
      </div>
    </div>

    <!-- 액션 버튼 -->
    <div class="panel-actions">
      <button
        v-if="data.runId"
        class="action-btn action-btn--result"
        @click="emit('view-result', data.runId!)"
      >
        {{ t('flowEditor.btnViewResult') }}
      </button>
      <button
        class="action-btn action-btn--delete"
        @click="emit('delete')"
      >
        {{ t('flowEditor.btnDeleteStep') }}
      </button>
    </div>
  </aside>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.step-form-panel {
  position: absolute;
  top: 0;
  right: 0;
  width: 280px;
  height: 100%;
  background: $bg-card;
  border-left: 1px solid $border-color;
  display: flex;
  flex-direction: column;
  z-index: 10;
  overflow-y: auto;
}

.panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 14px;
  border-bottom: 1px solid $border-color;
  flex-shrink: 0;
}

.panel-title {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
}

.close-btn {
  display: flex;
  align-items: center;
  background: none;
  border: none;
  cursor: pointer;
  color: $text-muted;
  padding: 2px;
  border-radius: $radius-sm;

  &:hover {
    color: $text-primary;
  }
}

.panel-form {
  padding: 14px;
  flex: 1;
}

// ── Director 경고 ─────────────────────────────────────────────
.soul-warning {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  margin: -6px 0 14px;
  padding: 7px 9px;
  border-radius: $radius-sm;
  background: rgba(var(--warning-rgb), 0.1);
  border: 1px solid rgba(var(--warning-rgb), 0.28);
  color: $warning;
  font-size: 11.5px;
  line-height: 1.45;
}

// ── 참조 칩 ──────────────────────────────────────────────────
.ref-chips-section {
  margin-bottom: 16px;
}

.ref-chips-label {
  font-size: 12px;
  font-weight: 500;
  color: $text-muted;
  margin-bottom: 6px;
}

.ref-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-bottom: 4px;
}

.ref-chip {
  padding: 2px 8px;
  background: rgba(var(--accent-primary-rgb), 0.08);
  border: 1px solid rgba(var(--accent-primary-rgb), 0.22);
  border-radius: 10px;
  font-size: 11px;
  font-weight: 500;
  color: $accent-primary;
  cursor: pointer;
  transition: background $transition-fast, border-color $transition-fast;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.16);
    border-color: $accent-primary;
  }
}

.ref-hint {
  font-size: 11px;
  color: $text-muted;
  line-height: 1.4;
}

// ── 실행 입출력 ───────────────────────────────────────────────
.io-section {
  padding: 0 14px 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.io-block {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.io-label {
  font-size: 12px;
  font-weight: 600;
  color: $text-muted;
}

.io-text {
  margin: 0;
  padding: 8px 10px;
  border-radius: $radius-sm;
  font-size: 11.5px;
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-word;
  max-height: 180px;
  overflow-y: auto;
  font-family: inherit;

  &--in {
    background: rgba(139, 92, 246, 0.08);
    border: 1px solid rgba(139, 92, 246, 0.22);
    color: $text-primary;
  }

  &--out {
    background: rgba(34, 197, 94, 0.08);
    border: 1px solid rgba(34, 197, 94, 0.2);
    color: $text-primary;
  }
}

// ── 액션 버튼 ─────────────────────────────────────────────────
.panel-actions {
  padding: 10px 14px 14px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  border-top: 1px solid $border-color;
  flex-shrink: 0;
}

.action-btn {
  width: 100%;
  padding: 7px 12px;
  border-radius: $radius-sm;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background $transition-fast, border-color $transition-fast, color $transition-fast;

  &--result {
    background: rgba(var(--accent-primary-rgb), 0.08);
    border-color: rgba(var(--accent-primary-rgb), 0.25);
    color: $accent-primary;

    &:hover {
      background: rgba(var(--accent-primary-rgb), 0.15);
      border-color: $accent-primary;
    }
  }

  &--delete {
    background: rgba(var(--error-rgb), 0.07);
    border-color: rgba(var(--error-rgb), 0.2);
    color: $error;

    &:hover {
      background: rgba(var(--error-rgb), 0.14);
      border-color: $error;
    }
  }
}
</style>
