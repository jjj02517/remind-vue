<script setup lang="ts">
import { computed, ref } from 'vue'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'
import { blockDemoWrite } from '@/utils/demoGuard'
import { supabase } from '@/lib/supabase'
import { getPackagePauses } from '@/api/packagePauses'
import { getPackagePauseStatus, getPackagePauseStatusLabel } from '@/utils/packagePauseStatus'

import type { PackagePause } from '@/api/packagePauses'
import type { PackagePauseStatus } from '@/utils/packagePauseStatus'

// 부모 컴포넌트에서 이용권 ID 전달받기
const props = defineProps<{
  packageId: string
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// TanStack Query로 이용권별 일시정지 내역 조회
const {
  data: pauses,
  isPending: isLoading,
  error: queryError,
} = useQuery({
  // 이용권 ID별로 캐시 구분
  queryKey: computed(() => ['package-pauses', props.packageId]),

  // Supabase에서 일시정지 이력 조회
  queryFn: () => getPackagePauses(props.packageId),

  // 이용권 ID가 있을 때만 조회
  enabled: computed(() => !!props.packageId),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,
})

// 일시정지 처리 종류
type PauseAction = 'cancel' | 'resume'

// 일시정지 변경 요청 데이터 타입
interface PauseActionParams {
  pauseId: string
  action: PauseAction
}

// 현재 처리 중인 일시정지 ID
const pendingPauseId = ref<string | null>(null)

// 일시정지 변경 오류
const actionError = ref<{
  pauseId: string
  message: string
} | null>(null)

// 일시정지 예약 취소 및 조기 복귀 Mutation
const { mutateAsync: updatePause, isPending: isUpdating } = useMutation({
  // 선택한 작업에 따라 Supabase RPC 호출
  mutationFn: async (params: PauseActionParams) => {
    // 시작 전 일시정지 예약 취소
    if (params.action === 'cancel') {
      const { data, error } = await supabase.rpc('cancel_member_package_pause', {
        p_pause_id: params.pauseId,
      })

      if (error) throw error

      return data
    }

    // 진행 중인 일시정지 조기 복귀
    const { data, error } = await supabase.rpc('resume_member_package_pause', {
      p_pause_id: params.pauseId,
    })

    if (error) throw error

    return data
  },

  // 처리 성공 시 일시정지 및 이용권 데이터 갱신
  onSuccess: async () => {
    await Promise.all([
      // 해당 이용권 일시정지 내역 갱신
      queryClient.invalidateQueries({
        queryKey: ['package-pauses', props.packageId],
      }),

      // 회원 상세 페이지 이용권 갱신
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

// 날짜 표시 형식
function formatDate(date: string) {
  return date.slice(0, 10).replaceAll('-', '.')
}

// 일시정지 상태별 배지 스타일
function getPauseStatusClass(status: PackagePauseStatus) {
  const statusClasses: Record<PackagePauseStatus, string> = {
    scheduled: 'bg-blue-50 text-blue-700',
    paused: 'bg-amber-50 text-amber-700',
    completed: 'bg-slate-100 text-slate-600',
    resumed: 'bg-green-50 text-green-700',
    cancelled: 'bg-slate-100 text-slate-400',
  }

  return statusClasses[status]
}

// 일시정지 예약 취소 및 조기 복귀 버튼 표시 여부
function canPerformAction(pause: PackagePause, action: PauseAction): boolean {
  const status = getPackagePauseStatus(pause)

  // 예약 상태일 때만 취소 가능
  if (action === 'cancel') {
    return status === 'scheduled'
  }

  // 일시정지 진행 중일 때만 조기 복귀 가능
  return status === 'paused'
}

// 현재 항목이 처리 중인지 확인
function isPendingPause(pauseId: string): boolean {
  return isUpdating.value && pendingPauseId.value === pauseId
}

// 일시정지 예약 취소 또는 조기 복귀
async function handlePauseAction(pause: PackagePause, action: PauseAction) {
  // 중복 요청 방지
  if (isUpdating.value) return

  // 현재 상태에서 허용되지 않는 작업 차단
  if (!canPerformAction(pause, action)) return

  // 작업 전 확인 메시지
  const confirmMessage =
    action === 'cancel'
      ? `일시정지 예약을 취소하시겠습니까?\n\n예약 기간: ${formatDate(pause.starts_on)} ~ ${formatDate(pause.ends_on)}\n\n예약 취소 시 연장된 이용권 만료일이 복구됩니다.`
      : `오늘부터 이용을 재개하시겠습니까?\n\n기존 일시정지 기간: ${formatDate(pause.starts_on)} ~ ${formatDate(pause.ends_on)}\n\n조기 복귀하면 오늘부터 정상 이용할 수 있으며, 남은 일시정지 기간만큼 만료일이 조정됩니다.`

  if (!window.confirm(confirmMessage)) {
    return
  }

  // 이전 작업 오류 초기화
  actionError.value = null
  pendingPauseId.value = pause.id

  try {
    if (await blockDemoWrite()) return

    // Supabase RPC로 예약 취소 또는 조기 복귀
    await updatePause({
      pauseId: pause.id,
      action,
    })
  } catch (error) {
    console.error('일시정지 변경 오류:', error)

    // 해당 항목에만 오류 메시지 표시
    actionError.value = {
      pauseId: pause.id,
      message:
        error instanceof Error
          ? error.message
          : action === 'cancel'
            ? '일시정지 예약 취소에 실패했습니다.'
            : '일시정지 조기 복귀에 실패했습니다.',
    }
  } finally {
    pendingPauseId.value = null
  }
}
</script>

<template>
  <!-- 이용권 일시정지 내역 -->
  <div class="mt-5 border-t border-slate-100 pt-4">
    <!-- 일시정지 내역 제목 -->
    <h4 class="text-sm font-semibold text-slate-800">일시정지 내역</h4>

    <!-- 일시정지 내역 조회 중 -->
    <p v-if="isLoading" class="mt-3 text-sm text-slate-500">일시정지 내역을 불러오는 중...</p>

    <!-- 일시정지 내역 조회 오류 -->
    <p v-else-if="queryError" role="alert" class="mt-3 text-sm text-red-600">
      일시정지 내역을 불러오지 못했습니다.
    </p>

    <!-- 일시정지 내역 없음 -->
    <p v-else-if="!pauses?.length" class="mt-3 text-sm text-slate-400">
      등록된 일시정지 내역이 없습니다.
    </p>

    <!-- 일시정지 이력 목록 -->
    <div v-else class="mt-3 space-y-3">
      <div v-for="pause in pauses" :key="pause.id" class="rounded-lg bg-slate-50 p-4">
        <!-- 일시정지 기간 및 상태 -->
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="text-sm font-medium text-slate-800">
            {{ formatDate(pause.starts_on) }}
            ~
            {{ formatDate(pause.ends_on) }}
          </p>

          <!-- 일시정지 상태 -->
          <span
            class="rounded-full px-2.5 py-1 text-xs font-medium"
            :class="getPauseStatusClass(getPackagePauseStatus(pause))"
          >
            {{ getPackagePauseStatusLabel(getPackagePauseStatus(pause)) }}
          </span>
        </div>

        <!-- 일시정지 사유 -->
        <p v-if="pause.reason" class="mt-2 text-xs text-slate-500">사유: {{ pause.reason }}</p>

        <!-- 조기 복귀일 -->
        <p v-if="pause.resumed_on" class="mt-2 text-xs text-slate-500">
          복귀일: {{ formatDate(pause.resumed_on) }}
        </p>

        <!-- 일시정지 예약 취소 -->
        <div v-if="canPerformAction(pause, 'cancel')" class="mt-4 flex justify-end">
          <button
            type="button"
            :disabled="isUpdating"
            class="rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs font-medium text-slate-700 transition hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
            @click="handlePauseAction(pause, 'cancel')"
          >
            {{ isPendingPause(pause.id) ? '취소 처리 중...' : '예약 취소' }}
          </button>
        </div>

        <!-- 진행 중인 일시정지 조기 복귀 -->
        <div v-if="canPerformAction(pause, 'resume')" class="mt-4 flex justify-end">
          <button
            type="button"
            :disabled="isUpdating"
            class="rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-xs font-medium text-green-700 transition hover:bg-green-100 disabled:cursor-not-allowed disabled:opacity-50"
            @click="handlePauseAction(pause, 'resume')"
          >
            {{ isPendingPause(pause.id) ? '복귀 처리 중...' : '조기 복귀' }}
          </button>
        </div>

        <!-- 일시정지 변경 오류 -->
        <p v-if="actionError?.pauseId === pause.id" role="alert" class="mt-3 text-xs text-red-600">
          {{ actionError.message }}
        </p>
      </div>
    </div>
  </div>
</template>
