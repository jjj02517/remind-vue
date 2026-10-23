<script setup lang="ts">
import { computed, ref } from 'vue'
import { useMutation, useQueryClient } from '@tanstack/vue-query'
import { supabase } from '@/lib/supabase'

// 부모 컴포넌트에서 이용권 ID 전달받기
const props = defineProps<{
  packageId: string
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 일시정지 등록 모달
const pauseDialog = ref<HTMLDialogElement | null>(null)

// 일시정지 입력 데이터
const pauseForm = ref({
  startsOn: '',
  endsOn: '',
  reason: '',
})

// 일시정지 등록 오류
const pauseError = ref('')

// 오늘 날짜를 YYYY-MM-DD 형식으로 반환
function getTodayString(): string {
  const now = new Date()

  const year = now.getFullYear()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const day = String(now.getDate()).padStart(2, '0')

  return `${year}-${month}-${day}`
}

// 날짜 선택 시 사용할 오늘 날짜
const today = ref(getTodayString())

// 일시정지 일수 계산
const pauseDays = computed(() => {
  const { startsOn, endsOn } = pauseForm.value

  if (!startsOn || !endsOn || endsOn < startsOn) {
    return 0
  }

  // UTC 기준으로 계산하여 일광절약시간제 영향을 방지
  const start = Date.parse(`${startsOn}T00:00:00Z`)
  const end = Date.parse(`${endsOn}T00:00:00Z`)

  return Math.round((end - start) / (1000 * 60 * 60 * 24)) + 1
})

// 일시정지 등록 Mutation
const { mutateAsync: registerPause, isPending: isRegistering } = useMutation({
  // Supabase 일시정지 예약 RPC 호출
  mutationFn: async () => {
    const { data, error } = await supabase.rpc('pause_member_package', {
      p_package_id: props.packageId,
      p_starts_on: pauseForm.value.startsOn,
      p_ends_on: pauseForm.value.endsOn,
      p_reason: pauseForm.value.reason.trim() || null,
    })

    if (error) throw error

    return data
  },

  // 등록 성공 시 일시정지 및 이용권 데이터 갱신
  onSuccess: async () => {
    await Promise.all([
      // 해당 이용권 일시정지 내역 갱신
      queryClient.invalidateQueries({
        queryKey: ['package-pauses', props.packageId],
      }),

      // 회원 상세 페이지의 이용권 정보 갱신
      queryClient.invalidateQueries({
        queryKey: ['member-packages'],
      }),

      // 회원 목록 데이터 갱신
      queryClient.invalidateQueries({
        queryKey: ['members'],
      }),
    ])
  },
})

// 일시정지 등록 버튼 비활성화 조건
const isSubmitDisabled = computed(() => {
  if (isRegistering.value) return true
  if (!props.packageId) return true

  // 시작일과 종료일 필수
  if (!pauseForm.value.startsOn || !pauseForm.value.endsOn) {
    return true
  }

  // 과거 날짜는 등록할 수 없음
  if (pauseForm.value.startsOn < today.value) {
    return true
  }

  // 종료일은 시작일보다 빠를 수 없음
  if (pauseForm.value.endsOn < pauseForm.value.startsOn) {
    return true
  }

  return pauseDays.value < 1
})

// 일시정지 등록 모달 열기
function openPauseDialog() {
  today.value = getTodayString()

  pauseForm.value = {
    startsOn: today.value,
    endsOn: today.value,
    reason: '',
  }

  pauseError.value = ''

  pauseDialog.value?.showModal()
}

// 일시정지 등록 모달 닫기
function closePauseDialog() {
  if (isRegistering.value) return

  pauseDialog.value?.close()
}

// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isRegistering.value) {
    event.preventDefault()
  }
}

// 일시정지 예약 등록
async function submitPause() {
  if (isSubmitDisabled.value) return

  pauseError.value = ''

  try {
    // Supabase RPC로 일시정지 등록
    await registerPause()

    // 등록 성공 시 모달 닫기
    closePauseDialog()
  } catch (error) {
    console.error('일시정지 등록 오류:', error)

    // Supabase에서 반환한 오류 메시지 표시
    pauseError.value = error instanceof Error ? error.message : '일시정지 등록에 실패했습니다.'
  }
}

// 부모 컴포넌트에서 모달 열기 함수 사용
defineExpose({
  open: openPauseDialog,
})
</script>

<template>
  <!-- 이용권 일시정지 등록 모달 -->
  <dialog
    ref="pauseDialog"
    aria-labelledby="pause-dialog-title"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @cancel="handleCancel"
  >
    <!-- 모달 제목 -->
    <h2 id="pause-dialog-title" class="text-xl font-bold text-slate-900">이용권 일시정지</h2>

    <!-- 모달 설명 -->
    <p class="mt-2 text-sm text-slate-500">
      일시정지 기간을 선택해 주세요. 미래 날짜로 예약할 수도 있습니다.
    </p>

    <!-- 일시정지 등록 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitPause">
      <!-- 일시정지 시작일 -->
      <div>
        <label for="pause-start-date" class="mb-2 block text-sm font-medium text-slate-700">
          일시정지 시작일
        </label>

        <input
          id="pause-start-date"
          v-model="pauseForm.startsOn"
          type="date"
          required
          :min="today"
          :disabled="isRegistering"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- 일시정지 종료일 -->
      <div>
        <label for="pause-end-date" class="mb-2 block text-sm font-medium text-slate-700">
          일시정지 종료일
        </label>

        <input
          id="pause-end-date"
          v-model="pauseForm.endsOn"
          type="date"
          required
          :min="pauseForm.startsOn || today"
          :disabled="isRegistering"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- 일시정지 사유 -->
      <div>
        <label for="pause-reason" class="mb-2 block text-sm font-medium text-slate-700">
          일시정지 사유 (선택)
        </label>

        <textarea
          id="pause-reason"
          v-model="pauseForm.reason"
          rows="3"
          maxlength="500"
          placeholder="예: 여행, 개인 사정, 부상 등"
          :disabled="isRegistering"
          class="w-full resize-none rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- 일시정지 기간 안내 -->
      <div v-if="pauseDays > 0" class="rounded-lg bg-blue-50 p-4">
        <div class="flex items-center justify-between">
          <span class="text-sm text-blue-700"> 일시정지 기간 </span>

          <span class="text-lg font-bold text-blue-700"> {{ pauseDays }}일 </span>
        </div>

        <p class="mt-2 text-xs text-blue-600">
          만료일이 있는 이용권은 일시정지 일수만큼 자동 연장됩니다.
        </p>
      </div>

      <!-- 일시정지 등록 오류 -->
      <p v-if="pauseError" role="alert" class="text-sm text-red-600">
        {{ pauseError }}
      </p>

      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <button
          type="button"
          :disabled="isRegistering"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closePauseDialog"
        >
          취소
        </button>

        <!-- 일시정지 예약 등록 -->
        <button
          type="submit"
          :disabled="isSubmitDisabled"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-500"
        >
          {{ isRegistering ? '등록 중...' : '일시정지 등록' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
