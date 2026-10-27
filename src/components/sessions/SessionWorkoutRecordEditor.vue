<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useQueryClient } from '@tanstack/vue-query'
import { LoaderCircle, Save, NotebookPen } from 'lucide-vue-next'

import {
  saveSessionWorkoutRecord,
  type AttendanceStatus,
  type SessionAttendanceDetail,
} from '@/api/sessions'

// ============================================
// Props / Emits
// ============================================

const props = defineProps<{
  attendance: SessionAttendanceDetail
}>()

// 저장 후 부모 수업 상세 팝업에 변경 사실 전달
const emit = defineEmits<{
  updated: [status: AttendanceStatus | null]
}>()

// ============================================
// 운동 기록 입력 상태
// ============================================

const workoutNotes = ref(props.attendance.workoutNotes ?? '')
const isSaving = ref(false)
const errorMessage = ref('')
const successMessage = ref('')

const queryClient = useQueryClient()

// 서버에서 최신 기록을 불러오면 입력창에도 반영
watch(
  () => props.attendance.workoutNotes,
  (notes) => {
    if (!isSaving.value) {
      workoutNotes.value = notes ?? ''
    }
  },
)

// 다른 회원의 기록으로 전환되면 입력값 초기화
watch(
  () => props.attendance.id,
  () => {
    workoutNotes.value = props.attendance.workoutNotes ?? ''
    errorMessage.value = ''
    successMessage.value = ''
  },
)

// 기존 기록과 달라졌는지 확인
const hasChanges = computed(() => {
  return workoutNotes.value.trim() !== (props.attendance.workoutNotes ?? '').trim()
})

// ============================================
// 출석 상태 옵션
// ============================================

const statusOptions: {
  value: AttendanceStatus
  label: string
}[] = [
  { value: 'scheduled', label: '예정' },
  { value: 'attended', label: '출석' },
  { value: 'no_show', label: '노쇼' },
  { value: 'same_day_cancelled', label: '당일 취소' },
  { value: 'cancelled', label: '일반 취소' },
]

// 이용권 차감 대상
function isDeducted(status: AttendanceStatus): boolean {
  return status === 'attended' || status === 'no_show' || status === 'same_day_cancelled'
}

// 선택된 출석 상태 버튼 스타일
function getStatusClass(status: AttendanceStatus, selected: boolean): string {
  if (!selected) {
    return 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50'
  }

  switch (status) {
    case 'attended':
      return 'border-emerald-500 bg-emerald-50 text-emerald-700'
    case 'no_show':
      return 'border-rose-500 bg-rose-50 text-rose-700'
    case 'same_day_cancelled':
      return 'border-amber-500 bg-amber-50 text-amber-700'
    case 'cancelled':
      return 'border-slate-500 bg-slate-100 text-slate-700'
    default:
      return 'border-blue-500 bg-blue-50 text-blue-700'
  }
}

// ============================================
// 운동 기록 저장 및 출석 상태 변경
// ============================================

async function saveRecord(nextStatus: AttendanceStatus | null = null) {
  if (isSaving.value) return

  if (workoutNotes.value.length > 2000) {
    errorMessage.value = '운동 기록은 2000자 이하로 입력해 주세요.'
    return
  }

  // 출석 변경 시 이용권 차감 또는 복구 여부 안내
  if (nextStatus !== null && nextStatus !== props.attendance.status) {
    const previousDeducted = isDeducted(props.attendance.status)

    const nextDeducted = isDeducted(nextStatus)

    let message = '이용권 잔여 횟수는 변경되지 않습니다.'

    if (!previousDeducted && nextDeducted) {
      message = '이용권이 1회 차감됩니다.'
    } else if (previousDeducted && !nextDeducted) {
      message = '이용권이 1회 복구됩니다.'
    }

    const label = statusOptions.find((option) => option.value === nextStatus)?.label

    const confirmed = window.confirm(
      `${props.attendance.memberName}님의 출석을 ` +
        `'${label}' 상태로 변경할까요?\n\n` +
        '작성한 운동 기록도 함께 저장됩니다.\n' +
        message,
    )

    if (!confirmed) return
  }

  isSaving.value = true
  errorMessage.value = ''
  successMessage.value = ''

  try {
    // ============================================
    // 1. DB에 운동 기록과 출석 상태 저장
    // ============================================

    await saveSessionWorkoutRecord({
      attendanceId: props.attendance.id,
      workoutNotes: workoutNotes.value,
      ...(nextStatus !== null ? { newStatus: nextStatus } : {}),
    })
  } catch (error) {
    console.error('운동 기록 저장 오류:', error)

    errorMessage.value = error instanceof Error ? error.message : '운동 기록을 저장하지 못했습니다.'

    isSaving.value = false
    return
  }

  // ============================================
  // 2. 관련 데이터 캐시 갱신
  // ============================================

  try {
    await Promise.all([
      queryClient.invalidateQueries({
        queryKey: ['session-detail'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['sessions'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['member-packages'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['members'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['session-member-options'],
      }),
    ])
  } catch (error) {
    // DB 저장은 성공했으므로 캐시 오류와 구분
    console.error('운동 기록 캐시 갱신 오류:', error)
  }

  isSaving.value = false
  successMessage.value = '저장되었습니다.'

  // 부모 팝업에 저장 결과 전달
  emit('updated', nextStatus)
}
</script>

<template>
  <!-- ============================================ -->
  <!-- 회원별 운동 기록 카드 -->
  <!-- ============================================ -->
  <div class="rounded-xl border border-slate-200 bg-white p-4">
    <!-- 회원 정보 -->
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div>
        <h4 class="text-sm font-semibold text-slate-900">
          {{ attendance.memberName }}
        </h4>

        <p class="mt-1 text-xs text-slate-500">
          이용권 잔여
          {{ attendance.packageRemaining ?? '확인 필요' }}회 / 총
          {{ attendance.packageTotal ?? '확인 필요' }}회
        </p>
      </div>

      <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-600">
        {{ statusOptions.find((option) => option.value === attendance.status)?.label }}
      </span>
    </div>

    <!-- ============================================ -->
    <!-- 실제 운동 기록 입력 -->
    <!-- ============================================ -->
    <div class="mt-4">
      <label
        :for="`workout-notes-${attendance.id}`"
        class="mb-2 flex items-center gap-2 text-sm font-semibold text-slate-700"
      >
        <NotebookPen :size="16" class="text-blue-600" />
        실제 운동 기록
      </label>

      <textarea
        :id="`workout-notes-${attendance.id}`"
        v-model="workoutNotes"
        :disabled="isSaving"
        maxlength="2000"
        rows="4"
        placeholder="예: 스쿼트 40kg × 10회 3세트&#10;런지 8kg × 12회&#10;다음 수업: 상체 운동"
        class="w-full resize-y rounded-lg border border-slate-200 px-3 py-2.5 text-sm text-slate-800 outline-none focus:border-blue-500 disabled:opacity-50"
      />

      <div class="mt-1 flex items-center justify-between">
        <p class="text-xs text-slate-500">회원별로 기록됩니다.</p>
        <p class="text-xs text-slate-400">{{ workoutNotes.length }} / 2000</p>
      </div>

      <!-- 운동 기록만 저장 -->
      <button
        type="button"
        :disabled="isSaving || !hasChanges"
        class="mt-3 flex w-full items-center justify-center gap-2 rounded-lg border border-blue-200 bg-blue-50 px-3 py-2.5 text-sm font-semibold text-blue-700 transition hover:bg-blue-100 disabled:cursor-not-allowed disabled:opacity-40"
        @click="saveRecord()"
      >
        <LoaderCircle v-if="isSaving" :size="16" class="animate-spin" />
        <Save v-else :size="16" />

        {{ isSaving ? '저장 중...' : '운동 기록만 저장' }}
      </button>
    </div>

    <!-- ============================================ -->
    <!-- 출석 상태 변경 -->
    <!-- ============================================ -->
    <div class="mt-5 border-t border-slate-100 pt-4">
      <p class="mb-2 text-sm font-semibold text-slate-700">출석 상태</p>

      <p class="mb-3 text-xs text-slate-500">
        출석 상태를 변경하면 작성한 운동 기록도 함께 저장됩니다.
      </p>

      <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
        <button
          v-for="option in statusOptions"
          :key="option.value"
          type="button"
          :disabled="isSaving || option.value === attendance.status"
          :aria-pressed="option.value === attendance.status"
          class="min-h-10 rounded-lg border px-2 py-2 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-70"
          :class="getStatusClass(option.value, option.value === attendance.status)"
          @click="saveRecord(option.value)"
        >
          {{ option.label }}
        </button>
      </div>
    </div>

    <!-- ============================================ -->
    <!-- 저장 결과 -->
    <!-- ============================================ -->
    <p
      v-if="errorMessage"
      role="alert"
      class="mt-3 rounded-lg bg-rose-50 p-3 text-xs text-rose-700"
    >
      {{ errorMessage }}
    </p>

    <p v-if="successMessage" role="status" class="mt-3 text-xs text-emerald-700">
      {{ successMessage }}
    </p>
  </div>
</template>
