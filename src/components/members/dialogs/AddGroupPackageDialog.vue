<script setup lang="ts">
import { computed, ref } from 'vue'
import { useMutation, useQueryClient } from '@tanstack/vue-query'

import { addGroupPackage } from '@/api/memberPackages'

// 부모 컴포넌트에서 회원 ID 전달받기
const props = defineProps<{
  memberId: string
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 그룹 횟수제 이용권 추가 모달
const groupPackageDialog = ref<HTMLDialogElement | null>(null)

// 그룹 수업 횟수 입력
const totalSessions = ref<number>(10)

// 이용권 추가 오류 메시지
const registerError = ref('')

// 그룹 횟수제 이용권 추가 Mutation
const { mutateAsync: registerGroupPackage, isPending: isRegistering } = useMutation({
  // 기존 회원에게 그룹 횟수제 이용권 추가
  mutationFn: async (sessions: number) => {
    return addGroupPackage({
      memberId: props.memberId,
      totalSessions: sessions,
    })
  },

  // 등록 성공 시 회원 목록 및 상세 이용권 정보 갱신
  onSuccess: async () => {
    await Promise.all([
      // 회원 목록 갱신
      queryClient.invalidateQueries({
        queryKey: ['members'],
      }),

      // 회원 상세 이용권 갱신
      queryClient.invalidateQueries({
        queryKey: ['member-packages', props.memberId],
      }),
    ])
  },
})

// 이용권 추가 버튼 비활성화 조건
const isSubmitDisabled = computed(() => {
  if (isRegistering.value) return true
  if (!props.memberId) return true

  // 횟수는 1 이상의 정수만 허용
  return !Number.isInteger(totalSessions.value) || totalSessions.value < 1
})

// 그룹 이용권 추가 모달 열기
function openGroupPackageDialog() {
  // 입력값 초기화
  totalSessions.value = 10
  registerError.value = ''

  groupPackageDialog.value?.showModal()
}

// 그룹 이용권 추가 모달 닫기
function closeGroupPackageDialog() {
  if (isRegistering.value) return

  groupPackageDialog.value?.close()
}

// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isRegistering.value) {
    event.preventDefault()
  }
}

// 그룹 횟수제 이용권 등록
async function submitGroupPackage() {
  if (isSubmitDisabled.value) return

  registerError.value = ''

  try {
    // Supabase RPC로 그룹 횟수제 이용권 추가
    await registerGroupPackage(totalSessions.value)

    // 등록 성공 시 모달 닫기
    groupPackageDialog.value?.close()
  } catch (error) {
    console.error('그룹 이용권 추가 오류:', error)

    registerError.value =
      error instanceof Error ? error.message : '그룹 이용권 추가에 실패했습니다.'
  }
}

// 부모 컴포넌트에서 모달 열기 함수 사용
defineExpose({
  open: openGroupPackageDialog,
})
</script>

<template>
  <!-- 그룹 횟수제 이용권 추가 모달 -->
  <dialog
    ref="groupPackageDialog"
    aria-labelledby="group-package-dialog-title"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @cancel="handleCancel"
  >
    <!-- 모달 제목 -->
    <h2 id="group-package-dialog-title" class="text-xl font-bold text-slate-900">
      그룹 이용권 추가
    </h2>

    <!-- 모달 설명 -->
    <p class="mt-2 text-sm text-slate-500">기존 회원에게 그룹 수업 횟수제 이용권을 추가합니다.</p>

    <!-- 그룹 이용권 등록 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitGroupPackage">
      <!-- 총 그룹 수업 횟수 -->
      <div>
        <label for="group-total-sessions" class="mb-2 block text-sm font-medium text-slate-700">
          총 그룹 수업 횟수
        </label>

        <input
          id="group-total-sessions"
          v-model.number="totalSessions"
          type="number"
          min="1"
          step="1"
          required
          :disabled="isRegistering"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- 그룹 이용권 안내 -->
      <div class="rounded-lg bg-slate-50 p-4">
        <p class="text-sm text-slate-700">그룹 횟수제 이용권은 수업 참석 시 횟수가 차감됩니다.</p>

        <p class="mt-2 text-xs text-slate-500">기존 PT 및 월 회원권은 변경되지 않습니다.</p>
      </div>

      <!-- 그룹 이용권 등록 오류 -->
      <p v-if="registerError" role="alert" class="text-sm text-red-600">
        {{ registerError }}
      </p>

      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <button
          type="button"
          :disabled="isRegistering"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closeGroupPackageDialog"
        >
          취소
        </button>

        <!-- 그룹 이용권 추가 -->
        <button
          type="submit"
          :disabled="isSubmitDisabled"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-500"
        >
          {{ isRegistering ? '등록 중...' : '이용권 추가' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
