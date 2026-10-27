<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import { Building2, CircleAlert, LoaderCircle } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'
import { getTrainerContext } from '@/api/trainerContext'
import type { TrainerContext } from '@/api/trainerContext'

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

// 데모 근무처 조회 타입
interface DemoCompany {
  id: string
  name: string
  company_type: string
  is_active: boolean
}

// 데모 수업 조회 타입
interface DemoSession {
  id: string
  company_id: string
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
    console.error('근무처별 통계 트레이너 컨텍스트 조회 오류:', error)
    contextError.value = '트레이너 정보를 확인하지 못했습니다.'
  } finally {
    isContextLoading.value = false
  }
})

// 트레이너 컨텍스트 확인 후 조회
const isContextReady = computed(() => !!trainerContext.value?.trainerId)

// ============================================
// 데모 근무처별 월간 통계 조회
// ============================================

// 기존 RPC는 auth.uid() 기준으로 조회하므로
// 데모 방문자는 RLS로 허용된 데모 데이터를 직접 집계
async function getDemoCompanyMonthlyStats(
  trainerId: string,
  year: number,
  month: number,
): Promise<CompanyMonthlyStats[]> {
  // 한국 시간 기준 해당 월의 시작과 다음 달 시작
  const startIso = new Date(Date.UTC(year, month - 1, 1, -9)).toISOString()
  const endIso = new Date(Date.UTC(year, month, 1, -9)).toISOString()

  const pageSize = 1000

  // ============================================
  // 1. 데모 트레이너의 전체 근무처 조회
  // ============================================

  const companies: DemoCompany[] = []

  // 보관된 근무처 및 기본 개인 고객 근무처도 포함
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase
      .from('companies')
      .select('id, name, company_type, is_active')
      .eq('trainer_id', trainerId)
      .order('id', { ascending: true })
      .range(offset, offset + pageSize - 1)

    if (error) throw error

    const rows = data ?? []
    companies.push(...rows)

    if (rows.length < pageSize) break
  }

  // ============================================
  // 2. 근무처별 통계 초기값 생성
  // ============================================

  // 수업이 없는 근무처도 0회로 표시
  const statsMap = new Map<string, CompanyMonthlyStats>()

  for (const company of companies) {
    statsMap.set(company.id, {
      company_id: company.id,
      company_name: company.name,
      company_type: company.company_type,
      is_active: company.is_active,
      total_sessions: 0,
      pt_sessions: 0,
      group_sessions: 0,
      completed_sessions: 0,
      scheduled_sessions: 0,
      cancelled_sessions: 0,
    })
  }

  // ============================================
  // 3. 선택한 월의 데모 수업 조회
  // ============================================

  const sessions: DemoSession[] = []

  // 삭제된 수업은 제외하고 취소된 수업은 포함
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase
      .from('sessions')
      .select('id, company_id, session_type, status')
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

  // ============================================
  // 4. 근무처별 수업 종류 및 상태 집계
  // ============================================

  for (const session of sessions) {
    const company = statsMap.get(session.company_id)

    // 조회할 수 없는 근무처 데이터는 집계하지 않음
    if (!company) continue

    // 전체 수업 횟수
    company.total_sessions++

    // 수업 종류
    if (session.session_type === 'pt') {
      company.pt_sessions++
    }

    if (session.session_type === 'group') {
      company.group_sessions++
    }

    // 수업 진행 상태
    if (session.status === 'completed') {
      company.completed_sessions++
    }

    if (session.status === 'scheduled') {
      company.scheduled_sessions++
    }

    if (session.status === 'cancelled') {
      company.cancelled_sessions++
    }
  }

  // ============================================
  // 5. 근무처별 통계 반환
  // ============================================

  // 근무처 이름순 정렬
  return Array.from(statsMap.values()).sort((a, b) =>
    a.company_name.localeCompare(b.company_name, 'ko-KR'),
  )
}

// ============================================
// Supabase 근무처별 월간 통계 조회
// ============================================

// 수업이 등록·수정·삭제되면 ['sessions'] 캐시 무효화로 갱신
const {
  data: companyStats,
  isPending: isStatsLoading,
  isFetching,
  error: statsError,
} = useQuery({
  // 트레이너 및 월별 캐시 구분
  queryKey: computed(
    () =>
      [
        'sessions',
        'dashboard-company-monthly-stats',
        trainerContext.value?.trainerId ?? '',
        trainerContext.value?.isDemo ?? false,
        props.year,
        props.month,
      ] as const,
  ),

  enabled: isContextReady,

  queryFn: async ({ queryKey }): Promise<CompanyMonthlyStats[]> => {
    // 빠르게 월을 전환해도 각 요청의 조회 월 유지
    const [, , trainerId, demoMode, year, month] = queryKey

    if (!trainerId) {
      throw new Error('트레이너 정보가 없습니다.')
    }

    // 데모 방문자: 샘플 데이터를 직접 조회하여 집계
    if (demoMode) {
      return getDemoCompanyMonthlyStats(trainerId, year, month)
    }

    // 일반 사용자: 기존 근무처별 월간 통계 RPC 유지
    const { data, error } = await supabase.rpc('get_dashboard_company_monthly_stats', {
      p_year: year,
      p_month: month,
    })

    if (error) {
      throw error
    }

    return (data ?? []) as CompanyMonthlyStats[]
  },

  staleTime: 1000 * 30,
})

// ============================================
// 근무처별 통계 조회 상태
// ============================================

const isLoading = computed(() => {
  if (isContextLoading.value) return true
  if (contextError.value) return false

  return isStatsLoading.value
})

const hasError = computed(() => !!contextError.value || !!statsError.value)

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

      <p v-if="!isLoading && !hasError" class="text-xs text-slate-500">
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
      v-else-if="hasError"
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
