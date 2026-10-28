<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Download,
  LoaderCircle,
} from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'
import { getTrainerContext } from '@/api/trainerContext'
import type { TrainerContext } from '@/api/trainerContext'
import { getMonthlySessionExport } from '@/api/sessionExports'
import { downloadMonthlySessionExcel } from '@/utils/sessionExportExcel'
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

// 데모 통계 계산에 사용할 수업 데이터
interface DemoSession {
  id: string
  session_type: string
  status: string
}

// ============================================
// 트레이너 데이터 조회 컨텍스트
// ============================================

// 일반 사용자: 본인 데이터
// 데모 방문자: 데모 트레이너의 샘플 데이터
const trainerContext = ref<TrainerContext | null>(null)
const isContextLoading = ref(true)
const contextError = ref('')

// 현재 사용자에 맞는 데이터 조회 기준 확인
onMounted(async () => {
  try {
    trainerContext.value = await getTrainerContext()
  } catch (error) {
    console.error('월간 수업 트레이너 컨텍스트 조회 오류:', error)
    contextError.value = '트레이너 정보를 확인하지 못했습니다.'
  } finally {
    isContextLoading.value = false
  }
})

const isContextReady = computed(() => !!trainerContext.value?.trainerId)
const isDemo = computed(() => trainerContext.value?.isDemo ?? false)

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

// 엑셀 다운로드 상태
const isExporting = ref(false)
const exportError = ref('')
const exportMessage = ref('')

// 다른 월로 이동하면 이전 다운로드 안내 초기화
watch([selectedYear, selectedMonth], () => {
  exportError.value = ''
  exportMessage.value = ''
})

const monthTitle = computed(() => `${selectedYear.value}년 ${selectedMonth.value}월`)

const isCurrentMonth = computed(
  () => selectedYear.value === initialMonth.year && selectedMonth.value === initialMonth.month,
)

function moveMonth(offset: number) {
  if (isExporting.value) return

  // UTC 날짜 계산으로 연말/연초 이동을 안전하게 처리
  const next = new Date(Date.UTC(selectedYear.value, selectedMonth.value - 1 + offset, 1))

  selectedYear.value = next.getUTCFullYear()
  selectedMonth.value = next.getUTCMonth() + 1
}

function goToCurrentMonth() {
  if (isExporting.value) return

  const current = getKoreaYearMonth()

  selectedYear.value = current.year
  selectedMonth.value = current.month
}

// ============================================
// 데모 월간 수업 통계 조회
// ============================================

// 기존 RPC는 auth.uid() 기준으로 조회하므로
// 데모 방문자는 RLS로 허용된 데모 트레이너 데이터를 직접 집계
async function getDemoMonthlyStats(
  trainerId: string,
  year: number,
  month: number,
): Promise<MonthlySessionStats> {
  // 한국 시간 기준 해당 월의 시작과 다음 달 시작
  const startIso = new Date(Date.UTC(year, month - 1, 1, -9)).toISOString()
  const endIso = new Date(Date.UTC(year, month, 1, -9)).toISOString()

  const sessions: DemoSession[] = []
  const pageSize = 1000

  // 삭제되지 않은 해당 월 수업 전체 조회
  // Supabase 기본 조회 행 제한에 걸리지 않도록 페이지 단위 조회
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase
      .from('sessions')
      .select('id, session_type, status')
      .eq('trainer_id', trainerId)
      .is('deleted_at', null)
      .gte('starts_at', startIso)
      .lt('starts_at', endIso)
      .order('id', { ascending: true })
      .range(offset, offset + pageSize - 1)

    if (error) throw error

    const rows = data ?? []
    sessions.push(...rows)

    if (rows.length < pageSize) break
  }

  // 수업 및 출석 통계 초기값
  const result: MonthlySessionStats = {
    total_sessions: sessions.length,
    pt_sessions: 0,
    group_sessions: 0,
    completed_sessions: 0,
    scheduled_sessions: 0,
    cancelled_sessions: 0,
    attended_count: 0,
    no_show_count: 0,
    same_day_cancelled_count: 0,
    attendance_cancelled_count: 0,
    attendance_scheduled_count: 0,
  }

  // 수업 종류 및 진행 상태별 집계
  for (const session of sessions) {
    if (session.session_type === 'pt') {
      result.pt_sessions++
    }

    if (session.session_type === 'group') {
      result.group_sessions++
    }

    if (session.status === 'completed') {
      result.completed_sessions++
    }

    if (session.status === 'scheduled') {
      result.scheduled_sessions++
    }

    if (session.status === 'cancelled') {
      result.cancelled_sessions++
    }
  }

  // 해당 월에 수업이 없다면 빈 통계 반환
  if (sessions.length === 0) {
    return result
  }

  // 그룹 수업은 참여 회원별로 출석 기록이 존재하므로
  // 수업 건수와 회원별 출석 건수를 별도로 집계
  const sessionIds = sessions.map((session) => session.id)
  const batchSize = 100

  for (let i = 0; i < sessionIds.length; i += batchSize) {
    const ids = sessionIds.slice(i, i + batchSize)

    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await supabase
        .from('session_attendances')
        .select('attendance_status')
        .eq('trainer_id', trainerId)
        .in('session_id', ids)
        .order('id', { ascending: true })
        .range(offset, offset + pageSize - 1)

      if (error) throw error

      const rows = data ?? []

      for (const attendance of rows) {
        switch (attendance.attendance_status) {
          case 'attended':
            result.attended_count++
            break
          case 'no_show':
            result.no_show_count++
            break
          case 'same_day_cancelled':
            result.same_day_cancelled_count++
            break
          case 'cancelled':
            result.attendance_cancelled_count++
            break
          case 'scheduled':
            result.attendance_scheduled_count++
            break
        }
      }

      if (rows.length < pageSize) break
    }
  }

  return result
}

// ============================================
// Supabase 월간 수업 통계 조회
// ============================================

// 수업 관리에서 ['sessions'] 캐시를 무효화하면 이 통계도 함께 갱신
const {
  data: stats,
  isPending: isStatsLoading,
  isFetching,
  error: statsError,
} = useQuery({
  // 트레이너 및 월별 캐시 구분
  queryKey: computed(
    () =>
      [
        'sessions',
        'dashboard-monthly-stats',
        trainerContext.value?.trainerId ?? '',
        isDemo.value,
        selectedYear.value,
        selectedMonth.value,
      ] as const,
  ),

  // 데이터 소유자 확인 후 조회
  enabled: isContextReady,

  queryFn: async ({ queryKey }): Promise<MonthlySessionStats> => {
    // 빠르게 월을 전환해도 각 요청의 조회 월을 유지
    const [, , trainerId, demoMode, year, month] = queryKey

    if (!trainerId) {
      throw new Error('트레이너 정보가 없습니다.')
    }

    // 데모 방문자: 샘플 수업과 출석 데이터를 조회하여 집계
    if (demoMode) {
      return getDemoMonthlyStats(trainerId, year, month)
    }

    // 일반 사용자: 기존 월간 수업 통계 RPC 유지
    const { data, error } = await supabase.rpc('get_dashboard_monthly_stats', {
      p_year: year,
      p_month: month,
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
// 대시보드 조회 상태
// ============================================

const isLoading = computed(
  () => isContextLoading.value || (isContextReady.value && isStatsLoading.value),
)

const hasError = computed(() => !!contextError.value || !!statsError.value)

// ============================================
// 선택한 월의 엑셀 다운로드
// ============================================

async function downloadSelectedMonth() {
  if (isExporting.value || isLoading.value || hasError.value || !stats.value || isDemo.value) {
    return
  }

  // 버튼을 누른 시점의 월로 다운로드 대상을 고정
  const year = selectedYear.value
  const month = selectedMonth.value

  isExporting.value = true
  exportError.value = ''
  exportMessage.value = ''

  try {
    // 화면 캐시가 아닌 다운로드용 최신 전체 데이터 조회
    const data = await getMonthlySessionExport({ year, month })

    // 전체 / 근무처별 / 회원별 기록을 하나의 엑셀 파일로 생성
    await downloadMonthlySessionExcel(data)

    // 실제 저장 완료 여부는 브라우저에서 결정되므로 다운로드 시작으로 안내
    exportMessage.value = `${year}년 ${month}월 엑셀 다운로드를 시작했습니다.`
  } catch (error) {
    console.error('월별 수업 내역 엑셀 다운로드 오류:', error)

    exportError.value =
      error instanceof Error
        ? error.message
        : '월별 수업 내역을 다운로드하지 못했습니다. 다시 시도해 주세요.'
  } finally {
    isExporting.value = false
  }
}

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
  <!-- 월간 수업 현황 -->
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

      <div class="flex flex-wrap items-center gap-2">
        <div class="flex items-center gap-1">
          <button
            v-if="!isCurrentMonth"
            type="button"
            :disabled="isExporting"
            class="mr-1 rounded-lg border border-slate-200 px-3 py-2 text-xs font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
            @click="goToCurrentMonth"
          >
            이번 달
          </button>

          <button
            type="button"
            aria-label="이전 달 수업 통계"
            :disabled="isExporting"
            class="rounded-lg p-2 text-slate-600 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
            @click="moveMonth(-1)"
          >
            <ChevronLeft :size="18" />
          </button>

          <span
            class="min-w-26 text-center text-sm font-semibold text-slate-900"
            aria-live="polite"
          >
            {{ monthTitle }}
          </span>

          <button
            type="button"
            aria-label="다음 달 수업 통계"
            :disabled="isExporting"
            class="rounded-lg p-2 text-slate-600 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
            @click="moveMonth(1)"
          >
            <ChevronRight :size="18" />
          </button>
        </div>

        <!-- 선택한 월의 전체 내역 다운로드 -->
        <button
          type="button"
          :disabled="isExporting || isLoading || hasError || !stats || isDemo"
          :aria-busy="isExporting"
          :aria-label="`${monthTitle} 수업 내역 엑셀 다운로드`"
          :title="isDemo ? '데모 엑셀 다운로드는 추후 연결 예정입니다.' : undefined"
          class="inline-flex items-center justify-center gap-2 rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-2 text-xs font-semibold text-emerald-700 transition hover:bg-emerald-100 disabled:cursor-not-allowed disabled:opacity-50"
          @click="downloadSelectedMonth"
        >
          <LoaderCircle v-if="isExporting" :size="16" class="animate-spin" aria-hidden="true" />
          <Download v-else :size="16" aria-hidden="true" />

          {{ isExporting ? '엑셀 생성 중...' : '엑셀 다운로드' }}
        </button>
      </div>
    </div>

    <!-- 다운로드 오류 및 결과 안내 -->
    <p
      v-if="exportError"
      role="alert"
      class="mt-4 rounded-lg bg-rose-50 px-4 py-3 text-sm text-rose-700"
    >
      {{ exportError }}
    </p>

    <p v-else-if="exportMessage" role="status" class="mt-3 text-xs text-emerald-700">
      {{ exportMessage }}
    </p>

    <!-- 데모 엑셀 다운로드 안내 -->
    <p v-if="isDemo" class="mt-3 text-xs text-slate-400">
      데모 모드의 엑셀 다운로드는 추후 연결 예정입니다.
    </p>

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
      v-else-if="hasError"
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

        <!-- PT + 그룹 통합 비율 막대 -->
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
