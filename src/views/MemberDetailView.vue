<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Archive, ArchiveRestore, ArrowLeft, Download, LoaderCircle } from 'lucide-vue-next'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'

import { supabase } from '@/lib/supabase'
import { getCompanies } from '@/api/companies'
import type { Company } from '@/api/companies'
import { getTrainerContext } from '@/api/trainerContext'
import { getMemberExport } from '@/api/memberExports'
import { downloadMemberExcel } from '@/utils/memberExportExcel'
import { getTodayString } from '@/utils/date'
import { formatPhone } from '@/utils/phone'
import { getMemberStatus } from '@/utils/memberStatus'
import type { MemberStatus } from '@/utils/memberStatus'

import MemberPackageCard from '@/components/members/MemberPackageCard.vue'
import AddPackageDialog from '@/components/members/dialogs/AddPackageDialog.vue'
import EditMemberDialog from '@/components/members/dialogs/EditMemberDialog.vue'
import MemberSessionHistory from '@/components/members/MemberSessionHistory.vue'

// 회원 상세 화면 데이터 타입
interface MemberDetailData {
  id: string
  name: string
  phone: string
  status: MemberStatus
}

// 현재 페이지의 라우트 정보
const route = useRoute()

// 회원 ID
const memberId = computed(() => String(route.params.id))

// Supabase 회원 UUID 형식 확인
const isValidMemberId = computed(() =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(memberId.value),
)

// 공통 이용권 추가 모달 컴포넌트 참조
const packageDialog = ref<InstanceType<typeof AddPackageDialog> | null>(null)

// 공통 이용권 추가 모달 열기
function openPackageDialog() {
  packageDialog.value?.open()
}

// 회원 정보 수정 모달 컴포넌트 참조
const editDialog = ref<InstanceType<typeof EditMemberDialog> | null>(null)

// 회원 정보 수정 모달 열기
function openEditDialog() {
  editDialog.value?.open()
}

// 로그인한 트레이너 ID
const trainerId = ref<string | null>(null)

// 데모 방문자 여부
const isDemo = ref(false)

// 로그인 정보 조회 상태
const isAuthLoading = ref(true)
const authError = ref('')

// TanStack Query로 회원 상세 정보 조회
const {
  data: dbMember,
  isPending: isMemberLoading,
  error: memberError,
} = useQuery({
  // 트레이너와 회원 ID별로 캐시 구분
  queryKey: computed(() => ['member', trainerId.value, memberId.value]),

  // Supabase에서 해당 회원 정보 조회
  queryFn: async () => {
    const { data, error } = await supabase
      .from('members')
      .select('id, name, phone, status')
      .eq('id', memberId.value)
      .maybeSingle()

    if (error) throw error
    return data
  },

  // 로그인 상태이고 올바른 UUID일 때만 조회
  enabled: computed(() => !!trainerId.value && isValidMemberId.value),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,
})

// TanStack Query로 회원별 전체 이용권 조회
const {
  data: dbPackages,
  isPending: isPackagesLoading,
  error: packagesError,
} = useQuery({
  // 회원별 이용권 캐시 구분
  queryKey: computed(() => ['member-packages', memberId.value, trainerId.value]),

  // Supabase에서 해당 회원의 모든 이용권과 일시정지 내역 조회
  queryFn: async () => {
    const { data, error } = await supabase
      .from('member_packages')
      .select(
        `
        id,
        member_id,
        company_id,
        package_type,
        usage_type,
        total_sessions,
        remaining_sessions,
        starts_on,
        ends_on,
        status,
        created_at,
        package_pauses (
          id,
          package_id,
          starts_on,
          ends_on,
          resumed_on,
          cancelled_at,
          reason,
          created_at
        )
      `,
      )
      .eq('member_id', memberId.value)
      .order('created_at', { ascending: false })

    if (error) throw error
    return data ?? []
  },

  // 로그인 상태이고 올바른 UUID일 때만 조회
  enabled: computed(() => !!trainerId.value && isValidMemberId.value),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,
})

// TanStack Query로 회원의 소속 근무처 조회
const {
  data: memberCompanies,
  isPending: isCompaniesLoading,
  error: companiesError,
} = useQuery({
  // 회원 ID별로 소속 근무처 캐시 구분
  queryKey: computed(() => ['member-companies', trainerId.value, memberId.value]),

  // 회원과 연결된 근무처를 조회 (보관된 근무처도 이력으로 표시)
  queryFn: async (): Promise<Company[]> => {
    const { data: links, error } = await supabase
      .from('company_members')
      .select('company_id')
      .eq('trainer_id', trainerId.value!)
      .eq('member_id', memberId.value)

    if (error) throw error

    const companyIds = (links ?? []).map((link) => link.company_id)
    if (!companyIds.length) return []

    // 근무처 이름과 보관 여부 조회
    const companies = await getCompanies()
    return companies.filter((company) => companyIds.includes(company.id))
  },

  // 로그인 상태이고 올바른 UUID일 때만 조회
  enabled: computed(() => !!trainerId.value && isValidMemberId.value),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,
})

// 근무처 연결 작업 후 회원 소속 목록 캐시 갱신
const queryClient = useQueryClient()

// 회원 보관 및 보관 해제 상태
const isUpdatingArchive = ref(false)
const archiveError = ref('')

// DB에 저장된 실제 보관 상태를 기준으로 버튼 표시
const isArchived = computed(() => dbMember.value?.status === 'archived')

// 회원을 보관하거나 다시 관리 목록으로 복원
async function toggleMemberArchive() {
  if (!member.value || !trainerId.value || isUpdatingArchive.value) return

  isUpdatingArchive.value = true
  archiveError.value = ''

  try {
    // 데모 모드는 변경 내용을 저장하지 않음
    if (isDemo.value) {
      window.alert('데모 모드에서는 데이터를 저장할 수 없습니다.')
      return
    }

    const shouldArchive = !isArchived.value

    const message = shouldArchive
      ? `${member.value.name} 회원을 보관할까요? 회원 정보와 이용권·수업 기록은 삭제되지 않습니다.`
      : `${member.value.name} 회원을 다시 관리 목록에 표시할까요?`

    if (!window.confirm(message)) return

    // 보관 해제 시 DB는 inactive로 두고, 화면에서는 이용권을 기준으로 활동 상태를 계산
    const nextStatus: MemberStatus = shouldArchive ? 'archived' : 'inactive'

    const { data, error } = await supabase
      .from('members')
      .update({ status: nextStatus })
      .eq('id', memberId.value)
      .eq('trainer_id', trainerId.value)
      .eq('status', dbMember.value!.status)
      .select('id')
      .maybeSingle()

    if (error) throw error

    if (!data) {
      throw new Error('회원 상태가 변경되지 않았습니다. 새로고침 후 다시 시도해 주세요.')
    }

    // 상세 화면·회원 목록·대시보드의 회원 수 갱신
    await Promise.all([
      queryClient.invalidateQueries({
        queryKey: ['member', trainerId.value, memberId.value],
      }),
      queryClient.invalidateQueries({
        queryKey: ['members'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['dashboard-overview'],
      }),
    ])
  } catch (error) {
    console.error('회원 보관 상태 변경 오류:', error)
    archiveError.value =
      error instanceof Error ? error.message : '회원 보관 상태를 변경하지 못했습니다.'
  } finally {
    isUpdatingArchive.value = false
  }
}

// 근무처 추가 연결 폼 상태
const isCompanyLinkFormOpen = ref(false)
const selectedCompanyId = ref('')
const companyLinkError = ref('')

// 추가 연결에 사용할 전체 근무처 목록 조회
const {
  data: allCompanies,
  isPending: isAllCompaniesLoading,
  error: allCompaniesError,
} = useQuery({
  queryKey: ['companies'],
  queryFn: getCompanies,
  enabled: computed(() => !!trainerId.value && isValidMemberId.value),
  staleTime: 1000 * 60 * 5,
})

// 이미 연결되어 있거나 보관된 근무처는 선택 목록에서 제외
const availableCompanies = computed(() => {
  const linkedCompanyIds = new Set((memberCompanies.value ?? []).map((company) => company.id))

  return (allCompanies.value ?? []).filter(
    (company) => company.is_active && !linkedCompanyIds.has(company.id),
  )
})

// 이용권의 근무처 ID로 이름을 찾기 위한 조회 결과
const companyNameById = computed(
  () => new Map((allCompanies.value ?? []).map((company) => [company.id, company.name])),
)

// 이용권 근무처 필터 (전체 근무처 또는 특정 근무처)
const packageCompanyFilter = ref('all')

// 이 회원과 연결되어 있거나 이용권 이력이 있는 근무처만 필터에 표시
// 보관된 근무처도 지난 이용권 조회를 위해 포함
const packageFilterCompanies = computed(() => {
  const companyIds = new Set<string>()

  for (const company of memberCompanies.value ?? []) {
    companyIds.add(company.id)
  }

  for (const pkg of dbPackages.value ?? []) {
    if (pkg.company_id) companyIds.add(pkg.company_id)
  }

  return (allCompanies.value ?? []).filter((company) => companyIds.has(company.id))
})

// 근무처 선택 결과: 전체 이용권은 유지하고 화면에 표시할 이용권만 필터링
const filteredPackages = computed(() => {
  if (packageCompanyFilter.value === 'all') return dbPackages.value ?? []

  return (dbPackages.value ?? []).filter((pkg) => pkg.company_id === packageCompanyFilter.value)
})

// 이용권별 근무처 이름 표시
function getPackageCompanyName(companyId: string | null): string | null {
  // 이전 데이터에 근무처가 지정되지 않은 경우
  if (!companyId) return '근무처 미지정'

  // 근무처 목록 조회 중에는 이름을 표시하지 않음
  if (isAllCompaniesLoading.value) return null

  // 조회 실패 또는 근무처가 목록에 없는 경우 다른 이름으로 추정하지 않음
  return companyNameById.value.get(companyId) ?? '근무처 확인 필요'
}

// 기존 회원을 선택한 근무처에 연결
const { mutateAsync: linkMemberToCompany, isPending: isLinkingCompany } = useMutation({
  mutationFn: async (companyId: string) => {
    const { error } = await supabase.rpc('link_member_to_company', {
      p_member_id: memberId.value,
      p_company_id: companyId,
    })

    if (error) throw error
  },

  onSuccess: async () => {
    // 소속 근무처 목록을 갱신해 새 근무처를 바로 표시
    await queryClient.invalidateQueries({
      queryKey: ['member-companies', trainerId.value, memberId.value],
    })

    // 추후 회원 목록의 근무처 필터에서도 최신 연결을 반영
    await queryClient.invalidateQueries({ queryKey: ['members'] })
  },
})

// 근무처 연결 폼 열기 또는 닫기
function toggleCompanyLinkForm() {
  if (isLinkingCompany.value) return

  companyLinkError.value = ''
  isCompanyLinkFormOpen.value = !isCompanyLinkFormOpen.value

  if (isCompanyLinkFormOpen.value) {
    // 사용 가능한 첫 번째 근무처를 기본 선택
    selectedCompanyId.value = availableCompanies.value[0]?.id ?? ''
  }
}

// 선택한 근무처에 회원 연결
async function submitCompanyLink() {
  const companyId = selectedCompanyId.value

  // 조회된 활성 근무처 중 아직 연결되지 않은 근무처만 등록
  if (!availableCompanies.value.some((company) => company.id === companyId)) return
  if (isLinkingCompany.value) return

  companyLinkError.value = ''

  try {
    await linkMemberToCompany(companyId)
    selectedCompanyId.value = ''
    isCompanyLinkFormOpen.value = false
  } catch (error) {
    console.error('근무처 추가 연결 오류:', error)

    // 다른 화면 등에서 동시에 같은 연결을 생성한 경우
    if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
      companyLinkError.value = '이미 연결된 근무처입니다. 새로고침 후 확인해 주세요.'
    } else {
      companyLinkError.value =
        error instanceof Error ? error.message : '근무처 연결에 실패했습니다.'
    }
  }
}

// 회원 ID로 회원 정보 조회
const member = computed<MemberDetailData | undefined>(() => {
  // Supabase 회원 정보가 없는 경우
  if (!dbMember.value) return undefined

  // 모든 이용권의 상태, 이용 기간, 일시정지 내역으로 활동 상태 계산
  const status = getMemberStatus(dbMember.value.status, dbPackages.value ?? [])

  return {
    id: dbMember.value.id,
    name: dbMember.value.name,
    phone: dbMember.value.phone,
    status,
  }
})

// 현재 또는 이용 예정 이용권 여부 판단
// 완료·만료·취소된 이용권은 지난 내역으로 분리
function isCurrentPackage(
  pkg: {
    status: string
    usage_type: string
    remaining_sessions: number | null
    starts_on: string | null
    ends_on: string | null
  },
  today: string,
): boolean {
  if (pkg.status !== 'active') return false

  // 기간이 끝난 이용권은 DB 상태가 active여도 지난 이용권으로 분류
  if (pkg.ends_on && pkg.ends_on < today) return false

  // 횟수제는 잔여 횟수가 있어야 현재 이용권으로 분류
  if (pkg.usage_type === 'count') {
    return (pkg.remaining_sessions ?? 0) > 0
  }

  // 기간제는 이용 시작 전이라도 만료 전이면 현재·예정에 포함
  if (pkg.usage_type === 'period') {
    return !!pkg.starts_on && !!pkg.ends_on
  }

  return false
}

// 현재 이용권과 이용 예정 이용권
// 일시정지 중인 이용권도 이 목록에 남김
const currentPackages = computed(() => {
  const today = getTodayString()
  return filteredPackages.value.filter((pkg) => isCurrentPackage(pkg, today))
})

// 사용 완료·기간 만료·취소된 지난 이용권
const pastPackages = computed(() => {
  const today = getTodayString()
  return filteredPackages.value.filter((pkg) => !isCurrentPackage(pkg, today))
})

// 지난 이용권 펼침 상태
const showPastPackages = ref(false)

// 회원 정보 조회 상태
const isDetailLoading = computed(() => {
  // 올바르지 않은 UUID는 조회하지 않음
  if (!isValidMemberId.value) return false

  // 로그인 정보 확인 중
  if (isAuthLoading.value) return true

  // 로그인한 트레이너 정보가 없는 경우
  if (!trainerId.value) return false

  // 회원 정보 및 이용권 조회 중
  return isMemberLoading.value || isPackagesLoading.value
})

// 회원 상세 조회 오류 메시지
const detailError = computed(() => {
  if (authError.value) return authError.value
  if (memberError.value) return '회원 정보를 불러오지 못했습니다.'
  if (packagesError.value) return '이용권을 불러오지 못했습니다.'
  return ''
})

// 회원 전체 내역 엑셀 다운로드 상태
const isExporting = ref(false)
const exportError = ref('')

// 다른 회원으로 이동하면 이전 회원의 다운로드 안내 초기화
watch(memberId, () => {
  exportError.value = ''
  archiveError.value = ''
})

// 화면 필터와 관계없이 회원의 전체 내역을 새로 조회해 다운로드
async function downloadMemberHistory() {
  if (
    isExporting.value ||
    isDetailLoading.value ||
    detailError.value ||
    !trainerId.value ||
    !isValidMemberId.value ||
    !member.value
  ) {
    return
  }

  // 클릭한 시점의 회원 ID를 고정해 사용
  const selectedMemberId = memberId.value
  isExporting.value = true
  exportError.value = ''

  try {
    const data = await getMemberExport({ memberId: selectedMemberId })
    await downloadMemberExcel(data)
  } catch (error) {
    console.error('회원 내역 엑셀 다운로드 오류:', error)

    if (memberId.value === selectedMemberId) {
      exportError.value =
        error instanceof Error
          ? error.message
          : '회원 내역을 다운로드하지 못했습니다. 잠시 후 다시 시도해 주세요.'
    }
  } finally {
    isExporting.value = false
  }
}

// 회원 상태 표시 이름
function getMemberStatusLabel(status: MemberStatus) {
  const statusLabels: Record<MemberStatus, string> = {
    active: '활동 중',
    inactive: '비활성',
    archived: '보관',
  }

  return statusLabels[status]
}

// 회원 상태별 배지 스타일
function getMemberStatusClass(status: MemberStatus) {
  const statusClasses: Record<MemberStatus, string> = {
    active: 'bg-green-50 text-green-700',
    inactive: 'bg-amber-50 text-amber-700',
    archived: 'bg-slate-100 text-slate-600',
  }

  return statusClasses[status]
}

// 회원 상세 페이지 진입 시 로그인한 사용자 확인
onMounted(async () => {
  // 올바르지 않은 UUID는 조회하지 않음
  if (!isValidMemberId.value) {
    isAuthLoading.value = false
    return
  }

  try {
    // 데모 방문자는 샘플 데이터 소유 트레이너 ID로 조회
    const context = await getTrainerContext()
    trainerId.value = context.trainerId
    isDemo.value = context.isDemo

    if (!trainerId.value) {
      authError.value = '로그인 정보를 확인하지 못했습니다.'
    }
  } catch (error) {
    console.error('로그인 정보 조회 오류:', error)
    authError.value = '로그인 정보를 확인하지 못했습니다.'
  } finally {
    isAuthLoading.value = false
  }
})
</script>

<template>
  <div>
    <!-- 회원 목록으로 돌아가기 -->
    <RouterLink
      to="/members"
      class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 hover:text-blue-600"
    >
      <ArrowLeft :size="18" aria-hidden="true" />
      회원 목록으로
    </RouterLink>

    <!-- 회원 정보 조회 중 -->
    <div
      v-if="isDetailLoading"
      class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center"
    >
      <p class="text-sm text-slate-500">회원 정보를 불러오는 중...</p>
    </div>

    <!-- 회원 정보 조회 오류 -->
    <div
      v-else-if="detailError"
      role="alert"
      class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center"
    >
      <p class="text-sm text-red-600">{{ detailError }}</p>
    </div>

    <!-- 회원 정보가 있는 경우 -->
    <template v-else-if="member">
      <!-- 회원 기본 정보 -->
      <section class="mt-6 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <!-- 회원명 및 상태 -->
            <div class="flex flex-wrap items-center gap-3">
              <h1 class="text-2xl font-bold text-slate-900 sm:text-3xl">
                {{ member.name }}
              </h1>
              <span
                class="rounded-full px-3 py-1 text-xs font-medium"
                :class="getMemberStatusClass(member.status)"
              >
                {{ getMemberStatusLabel(member.status) }}
              </span>
            </div>

            <!-- 연락처 -->
            <p class="mt-2 text-sm text-slate-500">
              {{ formatPhone(member.phone) }}
            </p>
          </div>

          <div class="flex w-full flex-wrap items-center gap-2 sm:w-auto">
            <!-- 회원 전체 내역 엑셀 다운로드 -->
            <button
              type="button"
              :disabled="isExporting"
              :aria-busy="isExporting"
              class="inline-flex items-center justify-center gap-2 rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-2 text-sm font-semibold text-emerald-700 transition hover:bg-emerald-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-600 disabled:cursor-not-allowed disabled:opacity-50"
              @click="downloadMemberHistory"
            >
              <LoaderCircle v-if="isExporting" :size="16" class="animate-spin" aria-hidden="true" />
              <Download v-else :size="16" aria-hidden="true" />
              {{ isExporting ? '엑셀 생성 중...' : '회원 내역 다운로드' }}
            </button>

            <!-- 회원 정보 수정 -->
            <button
              type="button"
              class="rounded-lg border border-slate-200 px-4 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-50"
              @click="openEditDialog"
            >
              정보 수정
            </button>

            <!-- 회원 보관 및 보관 해제 -->
            <button
              type="button"
              :disabled="isUpdatingArchive"
              :aria-busy="isUpdatingArchive"
              class="inline-flex items-center justify-center gap-2 rounded-lg border px-4 py-2 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-50"
              :class="
                isArchived
                  ? 'border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100'
                  : 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50'
              "
              @click="toggleMemberArchive"
            >
              <LoaderCircle
                v-if="isUpdatingArchive"
                :size="16"
                class="animate-spin"
                aria-hidden="true"
              />
              <ArchiveRestore v-else-if="isArchived" :size="16" aria-hidden="true" />
              <Archive v-else :size="16" aria-hidden="true" />
              {{ isUpdatingArchive ? '처리 중...' : isArchived ? '보관 해제' : '회원 보관' }}
            </button>
          </div>
        </div>

        <!-- 회원 보관·해제 오류 안내 -->
        <p v-if="archiveError" role="alert" class="mt-3 text-sm text-red-600">
          {{ archiveError }}
        </p>

        <!-- 회원 엑셀 다운로드 범위 및 결과 안내 -->
        <p class="mt-3 text-xs text-slate-500">
          전체 근무처 · 전체 기간의 내역을 엑셀로 내려받습니다.
        </p>
        <p v-if="exportError" role="alert" class="mt-2 text-sm text-red-600">
          {{ exportError }}
        </p>

        <!-- 회원 소속 근무처 -->
        <div class="mt-5 border-t border-slate-100 pt-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-sm font-semibold text-slate-800">소속 근무처</h2>

            <!-- 연결 가능한 근무처가 있을 때만 추가 버튼 표시 -->
            <button
              v-if="!isCompaniesLoading && !companiesError && availableCompanies.length"
              type="button"
              :disabled="isLinkingCompany"
              :aria-expanded="isCompanyLinkFormOpen"
              class="rounded-lg border border-blue-200 px-3 py-2 text-xs font-semibold text-blue-700 transition hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50"
              @click="toggleCompanyLinkForm"
            >
              {{ isCompanyLinkFormOpen ? '닫기' : '+ 근무처 연결' }}
            </button>
          </div>

          <!-- 근무처 조회 중 -->
          <p v-if="isCompaniesLoading" class="mt-3 text-sm text-slate-500">
            근무처를 불러오는 중...
          </p>

          <!-- 근무처 조회 오류 -->
          <p v-else-if="companiesError" role="alert" class="mt-3 text-sm text-red-600">
            소속 근무처를 불러오지 못했습니다.
          </p>

          <!-- 연결된 근무처 없음 -->
          <p v-else-if="!memberCompanies?.length" class="mt-3 text-sm text-slate-400">
            연결된 근무처가 없습니다.
          </p>

          <!-- 소속 근무처 배지 목록 -->
          <div v-else class="mt-3 flex flex-wrap gap-2">
            <span
              v-for="company in memberCompanies"
              :key="company.id"
              class="inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-xs font-medium"
              :class="
                company.is_active
                  ? company.company_type === 'personal'
                    ? 'bg-blue-50 text-blue-700'
                    : 'bg-slate-100 text-slate-700'
                  : 'bg-slate-100 text-slate-400'
              "
            >
              {{ company.name }}
              <span v-if="!company.is_active">(보관됨)</span>
            </span>
          </div>

          <!-- 근무처 추가 연결 폼 -->
          <form
            v-if="isCompanyLinkFormOpen && !isCompaniesLoading && !companiesError"
            class="mt-4 rounded-xl border border-blue-100 bg-blue-50/50 p-4"
            @submit.prevent="submitCompanyLink"
          >
            <label for="link-member-company" class="mb-2 block text-sm font-medium text-slate-700">
              추가로 연결할 근무처
            </label>

            <!-- 아직 연결되지 않은 활성 근무처 선택 -->
            <select
              id="link-member-company"
              v-model="selectedCompanyId"
              required
              :disabled="isLinkingCompany || isAllCompaniesLoading || !!allCompaniesError"
              class="w-full rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
            >
              <option v-for="company in availableCompanies" :key="company.id" :value="company.id">
                {{ company.name }}
              </option>
            </select>

            <p class="mt-2 text-xs text-slate-500">
              회원 정보는 중복 생성하지 않고 근무처 소속만 추가합니다.
            </p>

            <!-- 근무처 추가 연결 오류 -->
            <p v-if="companyLinkError" role="alert" class="mt-3 text-sm text-red-600">
              {{ companyLinkError }}
            </p>

            <div class="mt-4 flex justify-end gap-2">
              <button
                type="button"
                :disabled="isLinkingCompany"
                class="rounded-lg border border-slate-200 bg-white px-4 py-2 text-sm text-slate-700 hover:bg-slate-50 disabled:opacity-50"
                @click="toggleCompanyLinkForm"
              >
                취소
              </button>
              <button
                type="submit"
                :disabled="
                  isLinkingCompany ||
                  !availableCompanies.some((company) => company.id === selectedCompanyId)
                "
                class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300"
              >
                {{ isLinkingCompany ? '연결 중...' : '근무처 연결' }}
              </button>
            </div>
          </form>

          <!-- 추가 가능한 근무처 없음 또는 목록 조회 오류 -->
          <p
            v-else-if="!isAllCompaniesLoading && allCompaniesError"
            role="alert"
            class="mt-3 text-xs text-red-600"
          >
            추가 가능한 근무처 목록을 불러오지 못했습니다.
          </p>
          <p
            v-else-if="
              !isAllCompaniesLoading &&
              !isCompaniesLoading &&
              !companiesError &&
              !availableCompanies.length
            "
            class="mt-3 text-xs text-slate-500"
          >
            추가로 연결할 수 있는 활성 근무처가 없습니다.
          </p>
        </div>
      </section>

      <!-- 회원별 이용권 목록 -->
      <section class="mt-6">
        <!-- 이용권 내역 제목 및 이용권 추가 버튼 -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="text-lg font-semibold text-slate-900">보유 이용권</h2>
            <p class="mt-1 text-sm text-slate-500">
              PT, 그룹 수업, 월 회원권을 이용권별로 관리합니다.
            </p>
          </div>

          <!-- 공통 이용권 추가 버튼 -->
          <button
            type="button"
            class="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
            @click="openPackageDialog"
          >
            + 이용권 추가
          </button>
        </div>

        <!-- 근무처별 이용권 필터 -->
        <div class="mt-5 flex flex-wrap items-end justify-between gap-3">
          <div class="w-full sm:w-72">
            <label
              for="package-company-filter"
              class="mb-2 block text-sm font-medium text-slate-700"
            >
              근무처별 이용권 보기
            </label>
            <select
              id="package-company-filter"
              v-model="packageCompanyFilter"
              :disabled="isAllCompaniesLoading || !!allCompaniesError || isCompaniesLoading"
              class="w-full rounded-lg border border-slate-200 bg-white px-4 py-2.5 text-sm text-slate-700 outline-none focus:border-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <option value="all">전체 근무처</option>
              <option
                v-for="company in packageFilterCompanies"
                :key="company.id"
                :value="company.id"
              >
                {{ company.name }}{{ company.is_active ? '' : ' (보관됨)' }}
              </option>
            </select>
            <p
              v-if="allCompaniesError || companiesError"
              role="alert"
              class="mt-2 text-xs text-red-600"
            >
              근무처 필터 목록을 불러오지 못했습니다.
            </p>
          </div>

          <p v-if="packageCompanyFilter !== 'all'" class="text-sm text-slate-500">
            선택한 근무처의 이용권: {{ filteredPackages.length }}개
          </p>
        </div>

        <!-- 선택한 근무처에 등록된 이용권 없음 -->
        <div
          v-if="!filteredPackages.length"
          class="mt-5 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center"
        >
          <p class="text-sm text-slate-500">
            {{
              packageCompanyFilter === 'all'
                ? '등록된 이용권이 없습니다.'
                : '선택한 근무처에 등록된 이용권이 없습니다.'
            }}
          </p>
        </div>

        <template v-else>
          <!-- 현재 및 이용 예정 이용권 -->
          <div class="mt-6">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="text-base font-semibold text-slate-900">현재·예정 이용권</h3>
              <span class="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-medium text-blue-700">
                {{ currentPackages.length }}개
              </span>
            </div>

            <!-- 현재 및 이용 예정 이용권이 없는 경우 -->
            <div
              v-if="currentPackages.length === 0"
              class="mt-4 rounded-xl border border-slate-200 bg-white px-6 py-10 text-center"
            >
              <p class="text-sm text-slate-500">현재 이용 중이거나 예정된 이용권이 없습니다.</p>
            </div>

            <!-- 현재 및 이용 예정 이용권 카드 -->
            <div v-else class="mt-4 grid grid-cols-1 items-start gap-4 xl:grid-cols-2">
              <MemberPackageCard
                v-for="pkg in currentPackages"
                :key="pkg.id"
                :pkg="pkg"
                :company-name="getPackageCompanyName(pkg.company_id)"
              />
            </div>
          </div>

          <!-- 지난 이용권 목록: 필요할 때만 펼쳐보기 -->
          <div v-if="pastPackages.length > 0" class="mt-8 border-t border-slate-200 pt-6">
            <button
              type="button"
              class="flex w-full items-center justify-between gap-3 rounded-lg px-2 py-3 text-left transition hover:bg-slate-50 focus-visible:outline-2 focus-visible:outline-blue-600"
              :aria-expanded="showPastPackages"
              @click="showPastPackages = !showPastPackages"
            >
              <span class="flex flex-wrap items-center gap-2">
                <span class="text-base font-semibold text-slate-800">지난 이용권</span>
                <span
                  class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-600"
                >
                  {{ pastPackages.length }}개
                </span>
              </span>
              <span class="text-sm font-medium text-slate-500">
                {{ showPastPackages ? '접기 ▲' : '펼치기 ▼' }}
              </span>
            </button>

            <!-- 지난 이용권 카드 목록 -->
            <div
              v-if="showPastPackages"
              class="mt-4 grid grid-cols-1 items-start gap-4 xl:grid-cols-2"
            >
              <MemberPackageCard
                v-for="pkg in pastPackages"
                :key="pkg.id"
                :pkg="pkg"
                :company-name="getPackageCompanyName(pkg.company_id)"
              />
            </div>
          </div>
        </template>
      </section>

      <!-- 회원별 수업 이력 -->
      <MemberSessionHistory :member-id="member.id" />

      <!-- 공통 이용권 추가 모달 -->
      <AddPackageDialog ref="packageDialog" :member-id="member.id" />

      <!-- 회원 정보 수정 모달 -->
      <EditMemberDialog
        ref="editDialog"
        :member-id="member.id"
        :name="member.name"
        :phone="member.phone"
      />
    </template>

    <!-- 회원 정보가 없는 경우 -->
    <div v-else class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center">
      <h1 class="text-xl font-semibold text-slate-900">회원을 찾을 수 없습니다.</h1>
      <p class="mt-2 text-sm text-slate-500">회원 정보가 없거나 잘못된 주소입니다.</p>
    </div>
  </div>
</template>
