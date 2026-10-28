<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'
import { supabase } from '@/lib/supabase'
import { addMembershipPackage } from '@/api/memberPackages'
import { getCompanies } from '@/api/companies'
import { blockDemoWrite } from '@/utils/demoGuard'

// 부모 컴포넌트에서 회원 ID 전달받기
const props = defineProps<{
  memberId: string
}>()
// TanStack Query 캐시 관리
const queryClient = useQueryClient()
// 월 회원권 추가 모달
const membershipPackageDialog = ref<HTMLDialogElement | null>(null)
// 모달 열림 상태
const isDialogOpen = ref(false)
// 월 회원권 이용 시작일과 종료일
const startsOn = ref('')
const endsOn = ref('')
// 월 회원권 추가 오류 메시지
const registerError = ref('')
// 선택한 근무처 ID
const selectedCompanyId = ref('')
// 회원에게 연결된 활성 근무처 목록 조회
const {
  data: availableCompanies,
  isPending: isCompaniesLoading,
  isFetching: isCompaniesFetching,
  error: companiesError,
  refetch: refetchCompanies,
} = useQuery({
  // 회원별로 근무처 조회 캐시 구분
  queryKey: computed(() => ['membership-package-companies', props.memberId]),
  queryFn: async () => {
    // 회원과 연결된 근무처 ID 조회
    const { data: links, error } = await supabase
      .from('company_members')
      .select('company_id')
      .eq('member_id', props.memberId)

    if (error) throw error

    const linkedCompanyIds = new Set((links ?? []).map((link) => link.company_id))
    if (!linkedCompanyIds.size) return []

    // 연결되어 있고 활성 상태인 근무처만 선택 가능
    const companies = await getCompanies()
    return companies.filter((company) => company.is_active && linkedCompanyIds.has(company.id))
  },
  // 모달이 열려 있을 때만 조회
  enabled: computed(() => isDialogOpen.value && !!props.memberId),
  staleTime: 0,
  retry: false,
})

// 근무처가 하나면 자동 선택하고, 더는 사용할 수 없는 근무처는 선택 해제
watch(availableCompanies, (companies) => {
  if (!isDialogOpen.value) return

  if (companies?.length === 1) {
    selectedCompanyId.value = companies[0]!.id
    return
  }

  if (!companies?.some((company) => company.id === selectedCompanyId.value)) {
    selectedCompanyId.value = ''
  }
})

// 조회된 활성 근무처 중 실제로 선택된 근무처인지 확인
const hasSelectedCompany = computed(() =>
  (availableCompanies.value ?? []).some((company) => company.id === selectedCompanyId.value),
)

// 근무처 목록 재조회
function retryCompanies() {
  void refetchCompanies()
}
// 시작일을 기준으로 30일째 되는 종료일 계산
// 시작일을 첫째 날로 포함하므로 29일을 더함
function addDays(date: string, days: number): string {
  if (!date) return ''
  // 시간대에 따른 날짜 차이를 방지하기 위해 UTC 사용
  const result = new Date(`${date}T00:00:00Z`)
  if (Number.isNaN(result.getTime())) return ''
  result.setUTCDate(result.getUTCDate() + days)
  return result.toISOString().slice(0, 10)
}
// 월 회원권 최소 종료일
const minimumEndsOn = computed(() => {
  return addDays(startsOn.value, 29)
})
// 월 회원권 이용 기간 유효성 검사
const isPeriodValid = computed(() => {
  // 시작일과 종료일은 필수
  if (!startsOn.value || !endsOn.value || !minimumEndsOn.value) {
    return false
  }
  // 월 회원권은 시작일과 종료일을 포함하여 최소 30일
  return endsOn.value >= minimumEndsOn.value
})
// 이용 기간 오류 메시지
const periodError = computed(() => {
  if (!startsOn.value || !endsOn.value) {
    return ''
  }
  // 종료일이 시작일보다 빠른 경우
  if (endsOn.value < startsOn.value) {
    return '종료일은 시작일보다 빠를 수 없습니다.'
  }
  // 30일 미만인 경우
  if (minimumEndsOn.value && endsOn.value < minimumEndsOn.value) {
    return `월 회원권은 최소 30일 이상이어야 합니다. 종료일을 ${formatDate(minimumEndsOn.value)} 이후로 선택해 주세요.`
  }
  return ''
})
// 월 회원권 중복 기간 검사 활성화 조건
const canCheckOverlap = computed(() => {
  return isDialogOpen.value && !!props.memberId && hasSelectedCompany.value && isPeriodValid.value
})
// 기존 월 회원권과 이용 기간 중복 검사
const {
  data: overlappingPackage,
  isPending: isOverlapPending,
  isFetching: isOverlapFetching,
  isError: isOverlapError,
} = useQuery({
  // 회원과 선택한 날짜별로 검사 결과 캐시 구분
  queryKey: computed(() => [
    'membership-package-overlap',
    props.memberId,
    selectedCompanyId.value,
    startsOn.value,
    endsOn.value,
  ]),
  // 기존 월 회원권 중 겹치는 이용권 조회
  queryFn: async () => {
    const { data, error } = await supabase
      .from('member_packages')
      .select('id, starts_on, ends_on')
      .eq('member_id', props.memberId)
      // 같은 근무처의 이용 기간만 중복 검사
      .eq('company_id', selectedCompanyId.value)
      .eq('package_type', 'membership')
      .eq('usage_type', 'period')
      // 취소된 이용권은 중복 검사에서 제외
      .neq('status', 'cancelled')
      // 시작일과 종료일을 포함하여 기간 비교
      .lte('starts_on', endsOn.value)
      .gte('ends_on', startsOn.value)
      // 가장 먼저 시작하는 중복 이용권 조회
      .order('starts_on', { ascending: true })
      .limit(1)
      .maybeSingle()
    if (error) {
      throw error
    }
    // 중복 이용권이 없으면 null
    return data
  },
  // 모달이 열려 있고 유효한 날짜가 선택되었을 때만 조회
  enabled: canCheckOverlap,
  // 날짜를 다시 선택하면 최신 정보 확인
  staleTime: 0,
  // 오류 발생 시 자동 재시도하지 않음
  retry: false,
})
// 중복 검사 진행 상태
const isCheckingOverlap = computed(() => {
  if (!canCheckOverlap.value) return false
  return isOverlapPending.value || isOverlapFetching.value
})
// 기존 월 회원권과 날짜가 겹치는지 확인
const hasOverlappingPackage = computed(() => {
  return !!overlappingPackage.value
})
// 날짜 표시 형식
function formatDate(date: string | null): string {
  if (!date) return '미설정'
  return date.replaceAll('-', '.')
}
// 월 회원권 추가 Mutation
const { mutateAsync: registerMembershipPackage, isPending: isRegistering } = useMutation({
  // 기존 회원에게 월 회원권 추가
  mutationFn: async (params: { startsOn: string; endsOn: string; companyId: string }) => {
    return addMembershipPackage({
      memberId: props.memberId,
      startsOn: params.startsOn,
      endsOn: params.endsOn,
      companyId: params.companyId,
    })
  },
  // 등록 성공 시 회원 목록 및 상세 이용권 정보 갱신
  onSuccess: async () => {
    await Promise.all([
      // 회원 목록 갱신
      queryClient.invalidateQueries({
        queryKey: ['members'],
      }),
      // 회원 상세 이용권 갱신
      queryClient.invalidateQueries({
        queryKey: ['member-packages', props.memberId],
      }),
      // 기존 이용권 중복 검사 캐시 갱신
      queryClient.invalidateQueries({
        queryKey: ['membership-package-overlap', props.memberId],
      }),
    ])
  },
})
// 이용권 추가 버튼 비활성화 조건
const isSubmitDisabled = computed(() => {
  // 등록 진행 중
  if (isRegistering.value) return true
  // 근무처 조회 또는 선택 조건을 만족하지 않는 경우
  if (isCompaniesLoading.value || isCompaniesFetching.value || companiesError.value) return true
  if (!hasSelectedCompany.value) return true
  // 회원 ID 및 기간 유효성 검사
  if (!props.memberId || !isPeriodValid.value) {
    return true
  }
  // 중복 검사 진행 중
  if (isCheckingOverlap.value) return true
  // 중복 검사 오류
  if (isOverlapError.value) return true
  // 중복 이용권 존재
  if (hasOverlappingPackage.value) return true
  return false
})
// 시작일 변경 시 최소 30일 종료일 자동 설정
function handleStartDateChange() {
  endsOn.value = minimumEndsOn.value
  // 기존 등록 오류 초기화
  registerError.value = ''
}
// 종료일 변경 시 기존 등록 오류 초기화
function handlePeriodChange() {
  registerError.value = ''
}
// 월 회원권 추가 모달 열기
function openMembershipPackageDialog() {
  // 입력값 초기화
  startsOn.value = ''
  endsOn.value = ''
  registerError.value = ''
  selectedCompanyId.value = ''
  isDialogOpen.value = true
  membershipPackageDialog.value?.showModal()

  // 모달을 다시 열 때마다 근무처 연결 및 보관 상태를 최신으로 확인
  void refetchCompanies()
}
// 월 회원권 추가 모달 닫기
function closeMembershipPackageDialog() {
  if (isRegistering.value) return
  membershipPackageDialog.value?.close()
}
// 모달이 닫혔을 때 상태 정리
function handleDialogClose() {
  isDialogOpen.value = false
}
// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isRegistering.value) {
    event.preventDefault()
  }
}
// 월 회원권 등록
async function submitMembershipPackage() {
  if (isSubmitDisabled.value) return

  registerError.value = ''
  try {
    if (await blockDemoWrite()) return

    // Supabase RPC로 월 회원권 추가
    // DB에서 최소 30일 및 날짜 중복을 최종 검증
    await registerMembershipPackage({
      startsOn: startsOn.value,
      endsOn: endsOn.value,
      companyId: selectedCompanyId.value,
    })
    // 등록 성공 시 모달 닫기
    membershipPackageDialog.value?.close()
  } catch (error) {
    console.error('월 회원권 추가 오류:', error)
    registerError.value = error instanceof Error ? error.message : '월 회원권 추가에 실패했습니다.'
  }
}
// 부모 컴포넌트에서 모달 열기 함수 사용
defineExpose({
  open: openMembershipPackageDialog,
})
</script>
<template>
  <!-- 월 회원권 추가 모달 -->
  <dialog
    ref="membershipPackageDialog"
    aria-labelledby="membership-package-dialog-title"
    aria-describedby="membership-package-dialog-description"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @cancel="handleCancel"
    @close="handleDialogClose"
  >
    <!-- 모달 제목 -->
    <h2 id="membership-package-dialog-title" class="text-xl font-bold text-slate-900">
      월 회원권 추가
    </h2>
    <!-- 모달 설명 -->
    <p id="membership-package-dialog-description" class="mt-2 text-sm text-slate-500">
      기존 회원에게 최소 30일 이상의 월 회원권을 추가합니다.
    </p>
    <!-- 월 회원권 등록 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitMembershipPackage">
      <!-- 근무처 선택 -->
      <div>
        <label
          for="membership-package-company"
          class="mb-2 block text-sm font-medium text-slate-700"
        >
          근무처
        </label>

        <!-- 근무처 목록 조회 중 -->
        <p v-if="isCompaniesLoading || isCompaniesFetching" class="text-sm text-slate-500">
          연결된 근무처를 불러오는 중...
        </p>

        <!-- 근무처 조회 실패 -->
        <div v-else-if="companiesError" class="space-y-2">
          <p role="alert" class="text-sm text-red-600">근무처 목록을 불러오지 못했습니다.</p>
          <button
            type="button"
            :disabled="isRegistering"
            class="rounded-lg border border-slate-200 px-3 py-2 text-sm text-slate-700 hover:bg-slate-50"
            @click="retryCompanies"
          >
            다시 시도
          </button>
        </div>

        <!-- 연결된 활성 근무처가 없는 경우 -->
        <p v-else-if="!availableCompanies?.length" role="status" class="text-sm text-amber-700">
          연결된 활성 근무처가 없습니다. 회원 상세에서 먼저 근무처를 연결해 주세요.
        </p>

        <!-- 회원에게 연결된 활성 근무처 중 선택 -->
        <select
          v-else
          id="membership-package-company"
          v-model="selectedCompanyId"
          required
          :disabled="isRegistering"
          class="w-full rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        >
          <option value="" disabled>근무처를 선택해 주세요.</option>
          <option v-for="company in availableCompanies" :key="company.id" :value="company.id">
            {{ company.name }}
          </option>
        </select>

        <p class="mt-2 text-xs text-slate-500">회원에게 연결된 활성 근무처만 선택할 수 있습니다.</p>
      </div>
      <!-- 이용 시작일 -->
      <div>
        <label
          for="membership-package-starts-on"
          class="mb-2 block text-sm font-medium text-slate-700"
        >
          이용 시작일
        </label>
        <input
          id="membership-package-starts-on"
          v-model="startsOn"
          type="date"
          required
          :disabled="isRegistering"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          @change="handleStartDateChange"
        />
      </div>
      <!-- 이용 종료일 -->
      <div>
        <label
          for="membership-package-ends-on"
          class="mb-2 block text-sm font-medium text-slate-700"
        >
          이용 종료일
        </label>
        <input
          id="membership-package-ends-on"
          v-model="endsOn"
          type="date"
          required
          :min="minimumEndsOn || undefined"
          :disabled="isRegistering || !startsOn"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50 disabled:bg-slate-50"
          @change="handlePeriodChange"
        />
        <!-- 최소 이용 기간 안내 -->
        <p v-if="minimumEndsOn" class="mt-2 text-xs text-slate-500">
          최소 종료일: {{ formatDate(minimumEndsOn) }}
          (시작일 포함 30일)
        </p>
      </div>
      <!-- 이용 기간 유효성 검사 -->
      <p v-if="periodError" role="alert" class="text-sm text-red-600">
        {{ periodError }}
      </p>
      <!-- 기존 월 회원권과 날짜 중복 검사 -->
      <div v-if="canCheckOverlap" aria-live="polite">
        <!-- 중복 검사 중 -->
        <p v-if="isCheckingOverlap" class="text-sm text-slate-500">
          선택한 근무처의 월 회원권과 날짜 중복 확인 중...
        </p>
        <!-- 중복 검사 오류 -->
        <p v-else-if="isOverlapError" role="alert" class="text-sm text-red-600">
          선택한 근무처의 월 회원권을 확인하지 못했습니다. 날짜를 다시 선택하거나 잠시 후 재시도해
          주세요.
        </p>
        <!-- 같은 근무처의 월 회원권과 기간 중복 -->
        <div
          v-else-if="hasOverlappingPackage"
          role="alert"
          class="rounded-lg border border-red-200 bg-red-50 p-4"
        >
          <p class="text-sm font-medium text-red-700">
            선택한 근무처의 월 회원권과 이용 기간이 겹칩니다.
          </p>
          <p class="mt-2 text-xs text-red-600">
            기존 이용 기간:
            {{ formatDate(overlappingPackage?.starts_on ?? null) }}
            ~
            {{ formatDate(overlappingPackage?.ends_on ?? null) }}
          </p>
          <p class="mt-2 text-xs text-red-600">중복되지 않는 날짜를 선택해 주세요.</p>
        </div>
        <!-- 중복 없는 이용 기간 -->
        <p v-else class="text-sm text-green-700">선택한 근무처에 등록 가능한 이용 기간입니다.</p>
      </div>
      <!-- 월 회원권 안내 -->
      <div class="rounded-lg bg-slate-50 p-4">
        <p class="text-sm text-slate-700">
          월 회원권은 시작일과 종료일을 포함하여 최소 30일 이상 등록해야 합니다.
        </p>
        <p class="mt-2 text-xs text-slate-500">기존 PT 및 그룹 수업 이용권은 변경되지 않습니다.</p>
      </div>
      <!-- 월 회원권 등록 오류 -->
      <p v-if="registerError" role="alert" class="text-sm text-red-600">
        {{ registerError }}
      </p>
      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <!-- 취소 -->
        <button
          type="button"
          :disabled="isRegistering"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closeMembershipPackageDialog"
        >
          취소
        </button>
        <!-- 월 회원권 추가 -->
        <button
          type="submit"
          :disabled="isSubmitDisabled"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-500"
        >
          {{ isRegistering ? '등록 중...' : '이용권 추가' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
