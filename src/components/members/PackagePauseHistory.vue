<script setup lang="ts">
import { computed } from 'vue'
import { useQuery } from '@tanstack/vue-query'

import { getPackagePauses } from '@/api/packagePauses'
import { getPackagePauseStatus, getPackagePauseStatusLabel } from '@/utils/packagePauseStatus'
import type { PackagePauseStatus } from '@/utils/packagePauseStatus'

// 부모 컴포넌트에서 이용권 ID 전달받기
const props = defineProps<{
  packageId: string
}>()

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
      </div>
    </div>
  </div>
</template>
