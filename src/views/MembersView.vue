<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useQuery } from '@tanstack/vue-query'

import MemberSearch from '@/components/members/MemberSearch.vue'
import MemberList from '@/components/members/MemberList.vue'
import MemberRegisterDialog from '@/components/members/dialogs/MemberRegisterDialog.vue'

import { normalizePhone } from '@/utils/phone'
import { getMembers } from '@/api/members'
import { getCompanies } from '@/api/companies'
import { supabase } from '@/lib/supabase'

// 회원 상태 필터 타입
type MemberStatusFilter = 'all' | 'active' | 'inactive' | 'archived'

// 로그인한 트레이너 ID
const trainerId = ref<string | null>(null)

// 사용자 정보 조회 상태 및 오류
const isAuthLoading = ref(true)
const authError = ref('')

// TanStack Query로 Supabase 회원 목록 조회
const {
  data: dbMembers,
  isPending: isLoading,
  error: queryError,
} = useQuery({
  // 트레이너별로 회원 목록 캐시 구분
  queryKey: computed(() => ['members', trainerId.value]),

  // Supabase 회원 목록 조회
  queryFn: getMembers,

  // 로그인한 트레이너 ID가 있을 때만 조회
  enabled: computed(() => !!trainerId.value),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,

  // 디버깅을 위해 오류 발생 시 자동 재시도 끄기
  retry: false,

  // 디버깅을 위해 브라우저 포커스 시 자동 재조회 끄기
  refetchOnWindowFocus: false,
})

// 회원과 근무처 연결 데이터 타입
interface MemberCompanyLink {
  member_id: string
  company_id: string
}

// TanStack Query로 회원과 근무처 연결 관계 조회
const {
  data: memberCompanyLinks,
  isPending: isLinksLoading,
  error: linksError,
} = useQuery({
  // 기존 ['members'] 캐시 무효화 시 연결 관계도 함께 갱신
  queryKey: computed(() => ['members', trainerId.value, 'company-links']),

  queryFn: async (): Promise<MemberCompanyLink[]> => {
    const { data, error } = await supabase
      .from('company_members')
      .select('member_id, company_id')
      .eq('trainer_id', trainerId.value!)

    if (error) throw error

    return data ?? []
  },

  // 로그인한 트레이너의 연결 정보만 조회
  enabled: computed(() => !!trainerId.value),
  staleTime: 1000 * 60 * 5,
  retry: false,
})

// TanStack Query로 근무처 목록 조회
const {
  data: dbCompanies,
  isPending: isCompaniesLoading,
  error: companiesError,
} = useQuery({
  // 다른 계정의 캐시와 혼합되지 않도록 트레이너별로 구분
  queryKey: computed(() => ['companies', trainerId.value]),
  queryFn: getCompanies,
  enabled: computed(() => !!trainerId.value),
  staleTime: 1000 * 60 * 5,
  retry: false,
})

// 회원 목록 조회 오류 메시지
const fetchError = computed(() => {
  if (authError.value) return authError.value
  if (queryError.value) return '회원 목록을 불러오지 못했습니다.'
  if (linksError.value) return '회원의 소속 근무처를 불러오지 못했습니다.'
  if (companiesError.value) return '근무처 목록을 불러오지 못했습니다.'

  return ''
})

// 회원 및 근무처 조회 중 상태
const isPageLoading = computed(
  () =>
    isAuthLoading.value ||
    (!!trainerId.value && (isLoading.value || isLinksLoading.value || isCompaniesLoading.value)),
)

// 회원 검색어
const searchKeyword = ref('')

// 회원 상태 필터
const statusFilter = ref<MemberStatusFilter>('all')

// 근무처 필터 ('all' 또는 근무처 UUID)
const companyFilter = ref('all')

// 필터에서 선택 가능한 활성 근무처 목록
const activeCompanies = computed(() =>
  (dbCompanies.value ?? []).filter((company) => company.is_active),
)

// 회원별 연결된 근무처 ID 목록 생성
const companyIdsByMemberId = computed(() => {
  const result = new Map<string, Set<string>>()

  for (const link of memberCompanyLinks.value ?? []) {
    const companyIds = result.get(link.member_id) ?? new Set<string>()
    companyIds.add(link.company_id)
    result.set(link.member_id, companyIds)
  }

  return result
})

// 회원 목록 배지용 근무처 데이터 타입
interface MemberCompanyBadge {
  id: string
  name: string
  isActive: boolean
  isPersonal: boolean
}

// 회원마다 연결된 근무처 이름, 종류 및 보관 여부 표시 데이터 생성
const companiesByMemberId = computed<Record<string, MemberCompanyBadge[]>>(() => {
  const result: Record<string, MemberCompanyBadge[]> = {}
  const companiesById = new Map((dbCompanies.value ?? []).map((company) => [company.id, company]))

  for (const link of memberCompanyLinks.value ?? []) {
    const company = companiesById.get(link.company_id)
    if (!company) continue

    const badges = (result[link.member_id] ??= [])

    // 중복 연결이 존재해도 같은 근무처는 한 번만 표시
    if (badges.some((badge) => badge.id === company.id)) continue

    badges.push({
      id: company.id,
      name: company.name,
      isActive: company.is_active,
      isPersonal: company.company_type === 'personal',
    })
  }

  // 기본 '개인 고객'을 먼저 표시하고 나머지는 근무처 이름순 정렬
  for (const badges of Object.values(result)) {
    badges.sort(
      (a, b) => Number(b.isPersonal) - Number(a.isPersonal) || a.name.localeCompare(b.name, 'ko'),
    )
  }

  return result
})

// 회원 상태 필터 옵션
const statusFilterOptions: {
  value: MemberStatusFilter
  label: string
}[] = [
  { value: 'all', label: '전체' },
  { value: 'active', label: '활동 중' },
  { value: 'inactive', label: '비활성' },
  { value: 'archived', label: '보관 회원' },
]

// 회원 상태 필터 변경
function changeStatusFilter(status: MemberStatusFilter) {
  statusFilter.value = status
}

// 현재 선택한 상태 필터의 전체 회원 수
const statusFilteredMemberCount = computed(() => {
  return (dbMembers.value ?? []).filter((member) => {
    // 전체에서는 보관 회원 제외
    if (statusFilter.value === 'all') {
      return member.status !== 'archived'
    }

    // 나머지는 선택한 상태와 일치하는 회원만 포함
    return member.status === statusFilter.value
  }).length
})

// 검색어, 회원 상태 및 근무처에 따라 필터링된 회원 목록
const filteredMembers = computed(() => {
  const keyword = searchKeyword.value.trim().toLowerCase()
  const phoneKeyword = normalizePhone(keyword)

  return (dbMembers.value ?? []).filter((member) => {
    // 전체에서는 보관 회원을 제외하고, 보관 회원 탭에서는 보관 회원만 표시
    if (statusFilter.value === 'all') {
      if (member.status === 'archived') return false
    } else if (member.status !== statusFilter.value) {
      return false
    }

    // 선택한 근무처에 연결된 회원만 표시
    if (
      companyFilter.value !== 'all' &&
      !companyIdsByMemberId.value.get(member.id)?.has(companyFilter.value)
    ) {
      return false
    }

    // 검색어가 없는 경우 상태 및 근무처 필터만 적용
    if (!keyword) return true

    // 회원명 검색
    const matchesName = member.name.toLowerCase().includes(keyword)

    // 연락처 검색
    const matchesPhone = phoneKeyword !== '' && normalizePhone(member.phone).includes(phoneKeyword)

    return matchesName || matchesPhone
  })
})

// 회원 등록 모달 컴포넌트 참조
const registerDialog = ref<InstanceType<typeof MemberRegisterDialog> | null>(null)

// 회원 등록 모달 열기
function openRegisterDialog() {
  registerDialog.value?.open()
}

// 회원 관리 페이지 진입 시 로그인한 사용자 확인
onMounted(async () => {
  try {
    const { data, error } = await supabase.auth.getSession()

    if (error) {
      throw error
    }

    trainerId.value = data.session?.user.id ?? null

    // 로그인 정보가 없는 경우
    if (!trainerId.value) {
      authError.value = '로그인 정보를 확인하지 못했습니다.'
    }
  } catch (error) {
    console.error('사용자 정보 조회 오류:', error)

    authError.value = '사용자 정보를 확인하지 못했습니다.'
  } finally {
    isAuthLoading.value = false
  }
})
</script>

<template>
  <div>
    <div class="flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">회원 관리</h1>
        <p class="mt-2 text-sm text-slate-500">회원 정보와 이용권을 관리합니다.</p>
      </div>

      <button
        type="button"
        class="w-full rounded-lg bg-blue-600 px-5 py-3 text-sm font-semibold text-white transition hover:bg-blue-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600 sm:w-auto"
        @click="openRegisterDialog"
      >
        회원 등록
      </button>
    </div>

    <!-- 회원 검색 -->
    <MemberSearch v-model="searchKeyword" />

    <!-- 회원 상태 필터 -->
    <div class="mt-4">
      <div
        role="group"
        aria-label="회원 상태 필터"
        class="grid w-full grid-cols-2 gap-1 rounded-xl bg-slate-100 p-1 sm:inline-flex sm:w-auto"
      >
        <button
          v-for="option in statusFilterOptions"
          :key="option.value"
          type="button"
          :aria-pressed="statusFilter === option.value"
          class="rounded-lg px-4 py-2.5 text-sm font-medium transition-colors sm:min-w-24"
          :class="
            statusFilter === option.value
              ? 'bg-white text-blue-600 shadow-sm'
              : 'text-slate-500 hover:text-slate-800'
          "
          @click="changeStatusFilter(option.value)"
        >
          {{ option.label }}
        </button>
      </div>
    </div>

    <!-- 근무처 필터 -->
    <div class="mt-4 max-w-sm">
      <label for="member-company-filter" class="mb-2 block text-sm font-medium text-slate-700">
        근무처
      </label>

      <select
        id="member-company-filter"
        v-model="companyFilter"
        :disabled="isPageLoading || !!fetchError"
        class="w-full rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
      >
        <option value="all">전체 근무처</option>
        <option v-for="company in activeCompanies" :key="company.id" :value="company.id">
          {{ company.name }}
        </option>
      </select>

      <p class="mt-1 text-xs text-slate-500">
        여러 근무처에 소속된 회원도 목록에는 한 번만 표시됩니다.
      </p>
    </div>

    <!-- Supabase 회원 조회 상태 확인 (임시) -->
    <div class="mt-4 rounded-lg border border-slate-200 bg-white p-4 text-sm">
      <!-- 회원 목록 조회 오류 -->
      <p v-if="fetchError" role="alert" class="text-red-600">
        {{ fetchError }}
      </p>

      <!-- 회원 및 근무처 목록 조회 중 -->
      <p v-else-if="isPageLoading" class="text-slate-500">Supabase 회원 목록 불러오는 중...</p>

      <!-- 검색 및 필터 적용 결과 -->
      <p v-else class="text-slate-600">
        표시 중인 회원: {{ filteredMembers.length }}명
        <span class="text-slate-400">
          /
          {{
            statusFilter === 'all'
              ? '관리 중 전체'
              : statusFilterOptions.find((option) => option.value === statusFilter)?.label
          }}
          {{ statusFilteredMemberCount }}명
        </span>
      </p>
    </div>

    <!-- 회원 목록 -->
    <MemberList
      v-if="!isPageLoading && !fetchError"
      :members="filteredMembers"
      :companies-by-member-id="companiesByMemberId"
    />

    <!-- 회원 등록 모달 -->
    <MemberRegisterDialog ref="registerDialog" />
  </div>
</template>
