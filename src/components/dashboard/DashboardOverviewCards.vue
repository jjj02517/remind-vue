<script setup lang="ts">
import { computed } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import { UsersRound, UserRoundCheck, Building2, Ticket, LoaderCircle } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'

// ============================================
// 한국 날짜 조회
// ============================================

function getTodayString(): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date())

  const year = parts.find((part) => part.type === 'year')!.value
  const month = parts.find((part) => part.type === 'month')!.value
  const day = parts.find((part) => part.type === 'day')!.value

  return `${year}-${month}-${day}`
}

// ============================================
// 전체 회원 및 관리 중 회원 수 조회
// ============================================

const {
  data: memberCounts,
  isPending: isMembersLoading,
  error: membersError,
} = useQuery({
  queryKey: ['members', 'dashboard-overview'],

  queryFn: async () => {
    const [totalResponse, managedResponse] = await Promise.all([
      // 보관 회원을 포함한 전체 회원 수
      supabase.from('members').select('id', { count: 'exact', head: true }),

      // 보관 상태가 아닌 회원 수
      supabase
        .from('members')
        .select('id', { count: 'exact', head: true })
        .neq('status', 'archived'),
    ])

    if (totalResponse.error) {
      throw totalResponse.error
    }

    if (managedResponse.error) {
      throw managedResponse.error
    }

    return {
      total: totalResponse.count ?? 0,
      managed: managedResponse.count ?? 0,
    }
  },

  // 회원 목록 화면에서 회원 데이터를 변경하면 다시 조회
  refetchOnMount: 'always',
  staleTime: 1000 * 30,
})

// ============================================
// 활성 근무처 수 조회
// ============================================

const {
  data: activeCompanyCount,
  isPending: isCompaniesLoading,
  error: companiesError,
} = useQuery({
  queryKey: ['companies', 'dashboard-overview'],

  queryFn: async () => {
    const { count, error } = await supabase
      .from('companies')
      .select('id', { count: 'exact', head: true })

      // 사용 중인 근무처만 조회
      .eq('is_active', true)

      // 기본 개인 고객 근무처는 제외
      .eq('company_type', 'workplace')

    if (error) {
      throw error
    }

    return count ?? 0
  },

  // 근무처 등록 및 보관 상태 변경 반영
  refetchOnMount: 'always',
  staleTime: 1000 * 30,
})

// ============================================
// 실제 이용 가능한 활성 이용권 수 조회
// ============================================

const {
  data: activePackageCount,
  isPending: isPackagesLoading,
  error: packagesError,
} = useQuery({
  queryKey: ['member-packages', 'dashboard-overview', getTodayString()],

  queryFn: async () => {
    // 한국 날짜 기준으로 이용권 유효성 확인
    const today = getTodayString()

    const [countResponse, periodResponse] = await Promise.all([
      // 횟수제: 잔여 횟수가 있고 만료되지 않은 이용권
      supabase
        .from('member_packages')
        .select('id, members!inner(id)', { count: 'exact', head: true })
        .eq('status', 'active')
        .eq('usage_type', 'count')
        .gt('remaining_sessions', 0)

        // 만료일이 없거나 아직 지나지 않은 이용권
        .or(`ends_on.is.null,ends_on.gte.${today}`)

        // 보관된 회원의 이용권 제외
        .neq('members.status', 'archived'),

      // 기간제: 오늘이 실제 이용 기간에 포함되는 이용권
      supabase
        .from('member_packages')
        .select('id, members!inner(id)', { count: 'exact', head: true })
        .eq('status', 'active')
        .eq('usage_type', 'period')

        // 이용 시작일이 오늘 또는 이전
        .lte('starts_on', today)

        // 이용 종료일이 오늘 또는 이후
        .gte('ends_on', today)

        // 보관된 회원의 이용권 제외
        .neq('members.status', 'archived'),
    ])

    if (countResponse.error) {
      throw countResponse.error
    }

    if (periodResponse.error) {
      throw periodResponse.error
    }

    // 횟수제와 기간제 이용권 합산
    return (countResponse.count ?? 0) + (periodResponse.count ?? 0)
  },

  // 이용권 등록 및 상태 변경 반영
  refetchOnMount: 'always',
  staleTime: 1000 * 30,
})

// ============================================
// 대시보드 조회 상태
// ============================================

const isLoading = computed(
  () => isMembersLoading.value || isCompaniesLoading.value || isPackagesLoading.value,
)

const hasError = computed(
  () => !!membersError.value || !!companiesError.value || !!packagesError.value,
)

// ============================================
// 대시보드 운영 현황 카드
// ============================================

const overviewCards = computed(() => [
  {
    key: 'total-members',
    label: '전체 회원',
    value: membersError.value ? null : (memberCounts.value?.total ?? null),
    unit: '명',
    description: '보관 회원 포함',
    icon: UsersRound,
    iconClass: 'bg-blue-50 text-blue-600',
  },
  {
    key: 'managed-members',
    label: '관리 중 회원',
    value: membersError.value ? null : (memberCounts.value?.managed ?? null),
    unit: '명',
    description: '보관 회원 제외',
    icon: UserRoundCheck,
    iconClass: 'bg-emerald-50 text-emerald-600',
  },
  {
    key: 'active-companies',
    label: '활성 근무처',
    value: companiesError.value ? null : (activeCompanyCount.value ?? null),
    unit: '곳',
    description: '개인 고객용 기본 근무처 제외',
    icon: Building2,
    iconClass: 'bg-violet-50 text-violet-600',
  },
  {
    key: 'active-packages',
    label: '활성 이용권',
    value: packagesError.value ? null : (activePackageCount.value ?? null),
    unit: '개',
    description: '실제 이용 가능 기준',
    icon: Ticket,
    iconClass: 'bg-amber-50 text-amber-600',
  },
])
</script>

<template>
  <!-- ============================================ -->
  <!-- 대시보드 전체 운영 현황 -->
  <!-- ============================================ -->
  <section class="space-y-4">
    <!-- 제목 -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-lg font-semibold text-slate-900">전체 운영 현황</h2>

        <p class="mt-1 text-sm text-slate-500">현재 등록된 회원, 근무처, 이용권 현황입니다.</p>
      </div>

      <!-- 데이터 조회 중 -->
      <div v-if="isLoading" class="flex items-center gap-2 text-xs text-slate-400">
        <LoaderCircle :size="15" class="animate-spin" />
        불러오는 중...
      </div>

      <span v-else class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-500">
        현재 기준
      </span>
    </div>

    <!-- ============================================ -->
    <!-- 통계 카드 목록 -->
    <!-- ============================================ -->
    <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <div
        v-for="card in overviewCards"
        :key="card.key"
        class="rounded-xl border border-slate-200 bg-white p-4 sm:p-5"
      >
        <!-- 카드 이름 및 아이콘 -->
        <div class="flex items-start justify-between gap-2">
          <p class="text-sm font-medium text-slate-500">
            {{ card.label }}
          </p>

          <div
            class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg"
            :class="card.iconClass"
          >
            <component :is="card.icon" :size="18" aria-hidden="true" />
          </div>
        </div>

        <!-- 통계 숫자 -->
        <div class="mt-4 flex items-baseline gap-1">
          <span class="text-2xl font-bold tabular-nums text-slate-900 sm:text-3xl">
            {{ card.value === null ? '-' : card.value.toLocaleString('ko-KR') }}
          </span>

          <span class="text-sm font-medium text-slate-500">
            {{ card.unit }}
          </span>
        </div>

        <!-- 집계 기준 -->
        <p class="mt-2 text-xs leading-relaxed text-slate-400">
          {{ card.description }}
        </p>
      </div>
    </div>

    <!-- ============================================ -->
    <!-- 조회 오류 안내 -->
    <!-- ============================================ -->
    <p v-if="hasError" role="alert" class="rounded-lg bg-rose-50 px-4 py-3 text-sm text-rose-700">
      일부 운영 현황을 불러오지 못했습니다. 페이지를 새로고침한 뒤 다시 확인해 주세요.
    </p>
  </section>
</template>
