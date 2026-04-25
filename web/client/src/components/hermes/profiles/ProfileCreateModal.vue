<script setup lang="ts">
import { ref } from 'vue'
import { NModal, NForm, NFormItem, NInput, NButton, useMessage } from 'naive-ui'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { useI18n } from 'vue-i18n'

const emit = defineEmits<{
  close: []
  saved: []
}>()

const { t } = useI18n()
const profilesStore = useProfilesStore()
const message = useMessage()

const showModal = ref(true)
const loading = ref(false)
const name = ref('')
const path = ref('')

async function handleSave() {
  const trimmedName = name.value.trim()
  const trimmedPath = path.value.trim()
  if (!trimmedName) {
    message.warning('프로젝트 이름을 입력하세요')
    return
  }
  if (!trimmedPath) {
    message.warning('프로젝트 경로를 입력하세요 (예: C:/path/to/project)')
    return
  }

  loading.value = true
  try {
    const ok = await profilesStore.createProfile(trimmedName, trimmedPath)
    if (ok) {
      message.success(t('profiles.createSuccess', { name: trimmedName }))
      emit('saved')
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : '알 수 없는 오류'
    message.error(`등록 실패: ${msg}`)
  } finally {
    loading.value = false
  }
}

function handleClose() {
  showModal.value = false
  setTimeout(() => emit('close'), 200)
}
</script>

<template>
  <NModal
    v-model:show="showModal"
    preset="card"
    :title="t('profiles.create')"
    :style="{ width: 'min(420px, calc(100vw - 32px))' }"
    :mask-closable="!loading"
    @after-leave="emit('close')"
  >
    <NForm label-placement="top">
      <NFormItem label="이름" required>
        <NInput
          v-model:value="name"
          placeholder="예: 일정관리, CMS"
          @keyup.enter="handleSave"
        />
      </NFormItem>

      <NFormItem label="경로 (절대 경로)" required>
        <NInput
          v-model:value="path"
          placeholder="C:/01_xuefeng/my-project"
          @keyup.enter="handleSave"
        />
      </NFormItem>
    </NForm>

    <template #footer>
      <div class="modal-footer">
        <NButton @click="handleClose">{{ t('common.cancel') }}</NButton>
        <NButton type="primary" :loading="loading" @click="handleSave">
          {{ t('common.create') }}
        </NButton>
      </div>
    </template>
  </NModal>
</template>

<style scoped lang="scss">
.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
</style>
