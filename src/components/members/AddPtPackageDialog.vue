<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'

import { useMemberStore } from '@/stores/members'

// 부모 컴포넌트에서 회원 ID 전달받기
const props = defineProps<{
  memberId: string
}>()

// 회원 데이터 Store
const memberStore = useMemberStore()

// PT 이용권 추가 상태
const { isAddingPackage, addPackageError } = storeToRefs(memberStore)

// PT 이용권 추가 모달
const packageDialog = ref<HTMLDialogElement | null>(null)

// 추가할 PT 횟수
const totalSessions = ref(10)

// PT 이용권 추가 모달 열기
function openPackageDialog() {
  totalSessions.value = 10
  addPackageError.value = ''
  packageDialog.value?.showModal()
}

// PT 이용권 추가 모달 닫기
function closePackageDialog() {
  if (isAddingPackage.value) return

  packageDialog.value?.close()
}

// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isAddingPackage.value) {
    event.preventDefault()
  }
}

// PT 이용권 추가
async function submitPackage() {
  if (isAddingPackage.value) return

  // PT 횟수 유효성 검사
  if (!Number.isInteger(totalSessions.value) || totalSessions.value < 1) {
    addPackageError.value = 'PT 횟수는 1 이상의 정수여야 합니다.'
    return
  }

  // Supabase에 PT 이용권 추가
  const isSuccess = await memberStore.addPtPackage(props.memberId, totalSessions.value)

  // 추가 성공 시 모달 닫기
  if (isSuccess) {
    closePackageDialog()
  }
}

// 부모에서 모달 열기 함수를 사용할 수 있도록 공개
defineExpose({
  open: openPackageDialog,
})
</script>

<template>
  <!-- PT 이용권 추가 모달 -->
  <dialog
    ref="packageDialog"
    aria-labelledby="package-dialog-title"
    aria-describedby="package-dialog-description"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @cancel="handleCancel"
  >
    <!-- 모달 제목 -->
    <h2 id="package-dialog-title" class="text-xl font-bold text-slate-900">PT 이용권 추가</h2>

    <!-- 모달 설명 -->
    <p id="package-dialog-description" class="mt-2 text-sm text-slate-500">
      회원에게 추가할 PT 횟수를 입력해 주세요.
    </p>

    <!-- PT 이용권 입력 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitPackage">
      <!-- 추가 PT 횟수 -->
      <div>
        <label for="package-sessions" class="mb-2 block text-sm font-medium text-slate-700">
          추가 PT 횟수
        </label>

        <input
          id="package-sessions"
          v-model.number="totalSessions"
          type="number"
          min="1"
          step="1"
          required
          :disabled="isAddingPackage"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- PT 이용권 추가 오류 메시지 -->
      <p v-if="addPackageError" role="alert" class="text-sm text-red-600">
        {{ addPackageError }}
      </p>

      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <button
          type="button"
          :disabled="isAddingPackage"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closePackageDialog"
        >
          취소
        </button>

        <button
          type="submit"
          :disabled="isAddingPackage"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {{ isAddingPackage ? '추가 중...' : '이용권 추가' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
