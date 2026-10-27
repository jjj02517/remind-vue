<script setup lang="ts">
import { computed, ref } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import { CalendarDays, ChevronLeft, ChevronRight, CircleAlert, LoaderCircle } from 'lucide-vue-next'
import { supabase } from '@/lib/supabase'
import DashboardCompanyMonthlyStats from '@/components/dashboard/DashboardCompanyMonthlyStats.vue'
// ============================================
// 대시보드 월간 수업 통계 타입
// ============================================

interface MonthlySessionStats {
  total_sessions: number
  pt_sessions: number
  group_sessions: number
  completed_sessions: number
  scheduled_sessions: number
  cancelled_sessions: number
  attended_count: number
  no_show_count: number
  same_day_cancelled_count: number
  attendance_cancelled_count: number
  attendance_scheduled_count: number
}

// ============================================
// 한국 시간 기준 조회 월
// ============================================

// 컴퓨터의 로컬 시간대와 무관하게 한국 날짜를 사용
function getKoreaYearMonth() {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: 'numeric',
  }).formatToParts(new Date())

  const year = Number(parts.find((part) => part.type === 'year')?.value)
  const month = Number(parts.find((part) => part.type === 'month')?.value)
  return { year, month }
}

const initialMonth = getKoreaYearMonth()
const selectedYear = ref(initialMonth.year)
const selectedMonth = ref(initialMonth.month)

const monthTitle = computed(() => `${selectedYear.value}년 ${selectedMonth.value}월`)
const isCurrentMonth = computed(
  () => selectedYear.value === initialMonth.year && selectedMonth.value === initialMonth.month,
)

function moveMonth(offset: number) {
  // UTC 날짜 계산으로 연말/연초 이동을 안전하게 처리
  const next = new Date(Date.UTC(selectedYear.value, selectedMonth.value - 1 + offset, 1))
  selectedYear.value = next.getUTCFullYear()
  selectedMonth.value = next.getUTCMonth() + 1
}

function goToCurrentMonth() {
  const current = getKoreaYearMonth()
  selectedYear.value = current.year
  selectedMonth.value = current.month
}

// ============================================
// Supabase 월간 수업 통계 조회
// ============================================

// 수업 관리에서 ['sessions'] 캐시를 무효화하면 이 통계도 함께 갱신
const {
  data: stats,
  isPending: isLoading,
  isFetching,
  error: statsError,
} = useQuery({
  queryKey: computed(() => [
    'sessions',
    'dashboard-monthly-stats',
    selectedYear.value,
    selectedMonth.value,
  ]),
  queryFn: async (): Promise<MonthlySessionStats> => {
    const { data, error } = await supabase.rpc('get_dashboard_monthly_stats', {
      p_year: selectedYear.value,
      p_month: selectedMonth.value,
    })

    if (error) throw error

    // 집계 RPC는 수업이 없는 월에도 0이 담긴 한 행을 반환함
    const row = (data?.[0] ?? null) as MonthlySessionStats | null
    if (!row) throw new Error('월간 수업 통계를 불러오지 못했습니다.')

    return row
  },
  staleTime: 1000 * 30,
})

// ============================================
// 수업 종류별 비율 (PT + 그룹 = 100%)
// ============================================

const sessionTypeSummary = computed(() => {
  const ptCount = Number(stats.value?.pt_sessions ?? 0)
  const groupCount = Number(stats.value?.group_sessions ?? 0)

  const total = ptCount + groupCount

  const ptPercent = total > 0 ? Math.round((ptCount / total) * 100) : 0

  const groupPercent = total > 0 ? 100 - ptPercent : 0

  return {
    total,
    ptCount,
    groupCount,
    ptPercent,
    groupPercent,
  }
})

const sessionStatusCards = computed(() => [
  {
    label: '전체 수업',
    value: Number(stats.value?.total_sessions ?? 0),
    valueClass: 'text-slate-900',
  },
  {
    label: '처리 완료',
    value: Number(stats.value?.completed_sessions ?? 0),
    valueClass: 'text-emerald-700',
  },
  {
    label: '예정',
    value: Number(stats.value?.scheduled_sessions ?? 0),
    valueClass: 'text-blue-700',
  },
  {
    label: '취소',
    value: Number(stats.value?.cancelled_sessions ?? 0),
    valueClass: 'text-slate-600',
  },
])

// 그룹 수업 한 건에 회원 여러 명이 있을 수 있으므로 별도로 집계
const attendanceCards = computed(() => [
  { label: '출석', value: Number(stats.value?.attended_count ?? 0) },
  { label: '노쇼', value: Number(stats.value?.no_show_count ?? 0) },
  { label: '당일 취소', value: Number(stats.value?.same_day_cancelled_count ?? 0) },
  { label: '일반 취소', value: Number(stats.value?.attendance_cancelled_count ?? 0) },
  { label: '미처리', value: Number(stats.value?.attendance_scheduled_count ?? 0) },
])
</script>

<template>
  <!-- ============================================ -->
  <!-- 월간 수업 현황 -->
  <!-- ============================================ -->
  <section class="rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
    <!-- 월간 수업 제목 및 월 변경 -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <div class="flex items-center gap-2">
          <CalendarDays :size="20" class="text-blue-600" aria-hidden="true" />
          <h2 class="text-lg font-semibold text-slate-900">월간 수업 현황</h2>
        </div>
        <p class="mt-1 text-sm text-slate-500">선택한 월의 PT·그룹 수업과 출석 현황입니다.</p>
      </div>
      <div class="flex items-center gap-1">
        <button
          v-if="!isCurrentMonth"
          type="button"
          class="mr-1 rounded-lg border border-slate-200 px-3 py-2 text-xs font-medium text-slate-700 hover:bg-slate-50"
          @click="goToCurrentMonth"
        >
          이번 달
        </button>
        <button
          type="button"
          aria-label="이전 달 수업 통계"
          class="rounded-lg p-2 text-slate-600 hover:bg-slate-100"
          @click="moveMonth(-1)"
        >
          <ChevronLeft :size="18" />
        </button>
        <span class="min-w-26 text-center text-sm font-semibold text-slate-900" aria-live="polite">
          {{ monthTitle }}
        </span>
        <button
          type="button"
          aria-label="다음 달 수업 통계"
          class="rounded-lg p-2 text-slate-600 hover:bg-slate-100"
          @click="moveMonth(1)"
        >
          <ChevronRight :size="18" />
        </button>
      </div>
    </div>

    <!-- 조회 중 -->
    <div
      v-if="isLoading"
      class="flex items-center justify-center gap-2 py-14 text-sm text-slate-500"
    >
      <LoaderCircle :size="18" class="animate-spin" aria-hidden="true" />
      통계를 불러오는 중...
    </div>

    <!-- 조회 오류 -->
    <div
      v-else-if="statsError"
      role="alert"
      class="mt-5 flex items-center gap-2 rounded-lg bg-rose-50 p-4 text-sm text-rose-700"
    >
      <CircleAlert :size="18" aria-hidden="true" />
      월간 수업 통계를 불러오지 못했습니다.
    </div>

    <template v-else-if="stats">
      <!-- 수업 전체 / 완료 / 예정 / 취소 -->
      <div class="mt-5 grid grid-cols-2 gap-3 xl:grid-cols-4">
        <div
          v-for="card in sessionStatusCards"
          :key="card.label"
          class="rounded-xl bg-slate-50 p-4"
        >
          <p class="text-xs font-medium text-slate-500">{{ card.label }}</p>
          <p class="mt-2 text-2xl font-bold tabular-nums" :class="card.valueClass">
            {{ card.value }}<span class="ml-1 text-sm font-medium">회</span>
          </p>
        </div>
      </div>

      <p v-if="isFetching" class="mt-3 text-xs text-slate-400" aria-live="polite">
        통계 갱신 중...
      </p>

      <!-- 수업 종류별 현황 -->
      <div class="mt-7">
        <!-- 제목 및 수업 횟수 -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h3 class="text-sm font-semibold text-slate-900">수업 종류별 현황</h3>

          <!-- 우측 상단 회색 라벨 -->
          <div class="flex flex-wrap items-center gap-1 text-sm text-slate-500">
            <span>PT {{ sessionTypeSummary.ptCount }}회</span> ·
            <span>그룹 수업 {{ sessionTypeSummary.groupCount }}회</span>
          </div>
        </div>

        <!-- ============================================ -->
        <!-- PT + 그룹 통합 비율 막대 -->
        <!-- ============================================ -->
        <div v-if="sessionTypeSummary.total > 0" class="mt-4">
          <div
            class="flex h-3 overflow-hidden rounded-full"
            role="img"
            :aria-label="`PT ${sessionTypeSummary.ptPercent}%, 그룹 ${sessionTypeSummary.groupPercent}%`"
          >
            <!-- PT 비율 -->
            <div
              class="h-full bg-blue-500 transition-all duration-300"
              :style="{
                width: `${(sessionTypeSummary.ptCount / sessionTypeSummary.total) * 100}%`,
              }"
            />

            <!-- 그룹 비율 -->
            <div
              class="h-full bg-violet-500 transition-all duration-300"
              :style="{
                width: `${(sessionTypeSummary.groupCount / sessionTypeSummary.total) * 100}%`,
              }"
            />
          </div>

          <!-- 하단 비율 표시 -->
          <div class="mt-3 flex items-center justify-between gap-3">
            <div class="flex items-center gap-2">
              <span class="h-2.5 w-2.5 rounded-sm bg-blue-500" />
              <span class="text-xs text-slate-500"> PT {{ sessionTypeSummary.ptPercent }}% </span>
            </div>

            <div class="flex items-center gap-2">
              <span class="h-2.5 w-2.5 rounded-sm bg-violet-500" />
              <span class="text-xs text-slate-500">
                그룹 {{ sessionTypeSummary.groupPercent }}%
              </span>
            </div>
          </div>
        </div>

        <!-- 수업이 없는 경우 -->
        <p v-else class="mt-4 rounded-lg bg-slate-50 px-4 py-5 text-center text-sm text-slate-400">
          선택한 월에 등록된 수업이 없습니다.
        </p>
      </div>

      <!-- 회원별 출석 통계 -->
      <div class="mt-7 border-t border-slate-100 pt-6">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h3 class="text-sm font-semibold text-slate-900">회원별 출석 현황</h3>
          <p class="text-xs text-slate-400">그룹 수업은 참여 회원마다 각각 1건으로 계산</p>
        </div>
        <div class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
          <div
            v-for="card in attendanceCards"
            :key="card.label"
            class="rounded-lg border border-slate-100 p-3"
          >
            <p class="text-xs text-slate-500">{{ card.label }}</p>
            <p class="mt-1 text-xl font-semibold tabular-nums text-slate-800">
              {{ card.value }}<span class="ml-1 text-xs font-normal text-slate-500">건</span>
            </p>
          </div>
        </div>
      </div>

      <!-- 수업이 없는 월 안내 -->
      <p v-if="Number(stats.total_sessions) === 0" class="mt-5 text-center text-xs text-slate-400">
        선택한 월에 등록된 수업이 없습니다.
      </p>

      <!-- 근무처별 월간 수업 현황 -->
      <DashboardCompanyMonthlyStats :year="selectedYear" :month="selectedMonth" />
    </template>
  </section>
</template>
