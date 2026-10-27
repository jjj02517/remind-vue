<script setup lang="ts">
import { computed } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import { Building2, CircleAlert, LoaderCircle } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'

// ============================================
// Props
// 기존 월간 수업 통계에서 선택한 연도와 월 사용
// ============================================

const props = defineProps<{
  year: number
  month: number
}>()

// ============================================
// 근무처별 월간 수업 통계 타입
// ============================================

interface CompanyMonthlyStats {
  company_id: string
  company_name: string
  company_type: string
  is_active: boolean
  total_sessions: number
  pt_sessions: number
  group_sessions: number
  completed_sessions: number
  scheduled_sessions: number
  cancelled_sessions: number
}

// ============================================
// Supabase 근무처별 월간 통계 조회
// ============================================

// 수업이 등록·수정·삭제되면 ['sessions'] 캐시 무효화로 갱신
const {
  data: companyStats,
  isPending: isLoading,
  isFetching,
  error: statsError,
} = useQuery({
  queryKey: computed(() => [
    'sessions',
    'dashboard-company-monthly-stats',
    props.year,
    props.month,
  ]),

  queryFn: async (): Promise<CompanyMonthlyStats[]> => {
    const { data, error } = await supabase.rpc('get_dashboard_company_monthly_stats', {
      p_year: props.year,
      p_month: props.month,
    })

    if (error) {
      throw error
    }

    return (data ?? []) as CompanyMonthlyStats[]
  },

  staleTime: 1000 * 30,
})

// ============================================
// 근무처별 수업 막대그래프 데이터
// ============================================

// 가장 수업이 많은 근무처를 100% 기준으로 사용
// 모든 근무처의 막대 길이를 동일한 기준으로 비교
const maxSessionCount = computed(() => {
  const counts = (companyStats.value ?? []).map((company) => Number(company.total_sessions))

  return Math.max(1, ...counts)
})

// PT와 그룹 수업을 하나의 막대에 나누어 표시
const companyBars = computed(() =>
  (companyStats.value ?? []).map((company) => {
    const total = Number(company.total_sessions)
    const pt = Number(company.pt_sessions)
    const group = Number(company.group_sessions)

    return {
      id: company.company_id,
      name: company.company_name,
      isPersonal: company.company_type === 'personal',
      isActive: company.is_active,

      total,
      pt,
      group,

      completed: Number(company.completed_sessions),
      scheduled: Number(company.scheduled_sessions),
      cancelled: Number(company.cancelled_sessions),

      // 가장 수업이 많은 근무처를 기준으로 너비 계산
      ptWidth: (pt / maxSessionCount.value) * 100,
      groupWidth: (group / maxSessionCount.value) * 100,
    }
  }),
)

// ============================================
// 전체 근무처 수업 합계
// ============================================

const totalCompanySessions = computed(() =>
  companyBars.value.reduce((total, company) => total + company.total, 0),
)

// 실제 수업이 등록된 근무처 수
const companiesWithSessions = computed(
  () => companyBars.value.filter((company) => company.total > 0).length,
)
</script>

<template>
  <!-- ============================================ -->
  <!-- 근무처별 월간 수업 현황 -->
  <!-- ============================================ -->
  <div class="mt-7 border-t border-slate-100 pt-6">
    <!-- 제목 및 설명 -->
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <div class="flex items-center gap-2">
          <Building2 :size="18" class="text-blue-600" aria-hidden="true" />

          <h3 class="text-sm font-semibold text-slate-900">근무처별 월간 수업 현황</h3>
        </div>

        <p class="mt-2 text-xs text-slate-500">근무처별 PT·그룹 수업 횟수를 비교합니다.</p>
      </div>

      <p v-if="!isLoading && !statsError" class="text-xs text-slate-500">
        {{ companiesWithSessions }}곳 · 총 {{ totalCompanySessions }}회
      </p>
    </div>

    <!-- ============================================ -->
    <!-- 조회 중 -->
    <!-- ============================================ -->
    <div
      v-if="isLoading"
      class="mt-5 flex items-center justify-center gap-2 py-8 text-sm text-slate-500"
    >
      <LoaderCircle :size="18" class="animate-spin" aria-hidden="true" />
      근무처별 통계를 불러오는 중...
    </div>

    <!-- ============================================ -->
    <!-- 조회 오류 -->
    <!-- ============================================ -->
    <div
      v-else-if="statsError"
      role="alert"
      class="mt-5 flex items-center gap-2 rounded-lg bg-rose-50 p-4 text-sm text-rose-700"
    >
      <CircleAlert :size="18" aria-hidden="true" />
      근무처별 통계를 불러오지 못했습니다.
    </div>

    <!-- ============================================ -->
    <!-- 조회 결과 -->
    <!-- ============================================ -->
    <template v-else>
      <!-- 수업 종류 범례 -->
      <div class="mt-5 flex flex-wrap items-center gap-4">
        <div class="flex items-center gap-1.5">
          <span class="h-2.5 w-2.5 rounded-sm bg-blue-500" />
          <span class="text-xs text-slate-500">PT</span>
        </div>

        <div class="flex items-center gap-1.5">
          <span class="h-2.5 w-2.5 rounded-sm bg-violet-500" />
          <span class="text-xs text-slate-500">그룹</span>
        </div>

        <span v-if="isFetching" class="text-xs text-slate-400"> 갱신 중... </span>
      </div>

      <!-- 근무처가 없는 경우 -->
      <p
        v-if="companyBars.length === 0"
        class="mt-5 rounded-lg bg-slate-50 px-4 py-8 text-center text-sm text-slate-500"
      >
        등록된 근무처가 없습니다.
      </p>

      <!-- ============================================ -->
      <!-- 근무처별 막대그래프 목록 -->
      <!-- ============================================ -->
      <div v-else class="mt-5 space-y-6">
        <div v-for="company in companyBars" :key="company.id">
          <!-- 근무처 이름 및 전체 횟수 -->
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span class="text-sm font-semibold text-slate-800">
                {{ company.name }}
              </span>

              <!-- 기본 개인 고객 근무처 -->
              <span
                v-if="company.isPersonal"
                class="rounded-md bg-blue-50 px-2 py-0.5 text-xs text-blue-600"
              >
                개인
              </span>

              <!-- 보관된 근무처 -->
              <span
                v-if="!company.isActive"
                class="rounded-md bg-slate-100 px-2 py-0.5 text-xs text-slate-500"
              >
                보관
              </span>
            </div>

            <span class="text-sm font-semibold tabular-nums text-slate-700">
              {{ company.total }}회
            </span>
          </div>

          <!-- ============================================ -->
          <!-- PT + 그룹 누적 막대그래프 -->
          <!-- ============================================ -->
          <div
            class="mt-3 flex h-3 overflow-hidden rounded-full bg-slate-100"
            role="img"
            :aria-label="`${company.name}: PT ${company.pt}회, 그룹 ${company.group}회`"
          >
            <!-- PT 수업 -->
            <div
              class="h-full bg-blue-500 transition-all duration-300"
              :style="{ width: `${company.ptWidth}%` }"
            />

            <!-- 그룹 수업 -->
            <div
              class="h-full bg-violet-500 transition-all duration-300"
              :style="{ width: `${company.groupWidth}%` }"
            />
          </div>

          <!-- ============================================ -->
          <!-- 근무처별 상세 횟수 -->
          <!-- ============================================ -->
          <div class="mt-2 flex flex-wrap gap-x-2 gap-y-1">
            <div class="flex items-center gap-1">
              <span class="text-xs text-slate-500"> PT {{ company.pt }}회 ·</span>

              <span class="text-xs text-slate-500"> 그룹 {{ company.group }}회 </span>
            </div>

            <p class="text-xs text-slate-500">/</p>

            <div class="flex items-center gap-1">
              <span class="text-xs text-emerald-600"> 처리 완료 {{ company.completed }}회 ·</span>

              <span class="text-xs text-slate-400"> 예정 {{ company.scheduled }}회 ·</span>

              <span class="text-xs text-slate-400"> 취소 {{ company.cancelled }}회 </span>
            </div>
          </div>
        </div>
      </div>

      <!-- 수업이 없는 월 안내 -->
      <p
        v-if="companyBars.length > 0 && totalCompanySessions === 0"
        class="mt-5 rounded-lg bg-slate-50 px-4 py-4 text-center text-xs text-slate-500"
      >
        선택한 월에는 등록된 수업이 없습니다.
      </p>

      <!-- 집계 안내 -->
      <p class="mt-5 text-xs leading-relaxed text-slate-400">
        수업 1건을 1회로 계산합니다. 취소된 수업은 포함하고 삭제된 수업은 제외합니다. 보관된
        근무처의 과거 수업도 표시합니다.
      </p>
    </template>
  </div>
</template>
