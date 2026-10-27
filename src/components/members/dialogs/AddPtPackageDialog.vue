<script setup lang="ts">
import { computed, ref } from 'vue'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'
import { getCompanies } from '@/api/companies'
import { supabase } from '@/lib/supabase'

// 부모 컴포넌트에서 회원 ID 전달받기
const props = defineProps<{
  memberId: string
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// PT 이용권 추가 오류 메시지
const addPackageError = ref('')

// PT 이용권 추가 모달
const packageDialog = ref<HTMLDialogElement | null>(null)

// 추가할 PT 횟수
const totalSessions = ref(10)

// 이용권을 등록할 근무처 ID
const selectedCompanyId = ref('')

// 회원에게 연결된 근무처 ID 목록 조회
const {
  data: memberCompanyLinks,
  isPending: isMemberCompaniesLoading,
  isFetching: isMemberCompaniesFetching,
  isError: isMemberCompaniesError,
  refetch: refetchMemberCompanies,
} = useQuery({
  queryKey: computed(() => ['pt-package-member-companies', props.memberId]),
  queryFn: async () => {
    const { data, error } = await supabase
      .from('company_members')
      .select('company_id')
      .eq('member_id', props.memberId)

    if (error) throw error

    return data ?? []
  },
  enabled: computed(() => !!props.memberId),
})

// 근무처 이름 및 활성 상태 조회
const {
  data: allCompanies,
  isPending: isCompaniesLoading,
  isFetching: isCompaniesFetching,
  isError: isCompaniesError,
  refetch: refetchCompanies,
} = useQuery({
  queryKey: ['companies'],
  queryFn: getCompanies,
})

// 회원에게 연결되어 있고 현재 활성 상태인 근무처만 선택 가능
const availableCompanies = computed(() => {
  const linkedIds = new Set((memberCompanyLinks.value ?? []).map((link) => link.company_id))

  return (allCompanies.value ?? []).filter(
    (company) => company.is_active && linkedIds.has(company.id),
  )
})

// 근무처 조회 진행 상태
const isCompaniesBusy = computed(
  () =>
    isMemberCompaniesLoading.value ||
    isMemberCompaniesFetching.value ||
    isCompaniesLoading.value ||
    isCompaniesFetching.value,
)

// 선택한 근무처가 현재 등록 가능한 근무처인지 확인
const isValidCompanySelected = computed(() =>
  availableCompanies.value.some((company) => company.id === selectedCompanyId.value),
)

// PT 이용권 추가 요청 데이터 타입
interface AddPtPackageParams {
  totalSessions: number
  companyId: string
}

// PT 이용권 추가 Mutation
const { mutateAsync: addPtPackage, isPending: isAddingPackage } = useMutation({
  // 기존 회원의 PT 이용권 추가
  mutationFn: async (params: AddPtPackageParams) => {
    // Supabase에 선택한 근무처의 PT 이용권 추가
    const { error } = await supabase.rpc('add_pt_package', {
      p_member_id: props.memberId,
      p_total_sessions: params.totalSessions,
      p_company_id: params.companyId,
    })

    if (error) {
      throw error
    }
  },

  // PT 이용권 추가 성공 시 데이터 갱신
  onSuccess: async () => {
    // 회원 목록 및 이용권 내역 캐시 무효화
    await Promise.all([
      queryClient.invalidateQueries({
        queryKey: ['members'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['member-packages', props.memberId],
      }),
    ])

    // 아직 Pinia를 사용하는 회원 상세 페이지 데이터 갱신
    // await Promise.all([memberStore.fetchMembers(), memberStore.fetchMemberPackages(props.memberId)])
  },
})

// 이용권 등록 버튼 비활성화 조건
const isSubmitDisabled = computed(
  () =>
    isAddingPackage.value ||
    isCompaniesBusy.value ||
    isMemberCompaniesError.value ||
    isCompaniesError.value ||
    !isValidCompanySelected.value ||
    !Number.isInteger(totalSessions.value) ||
    totalSessions.value < 1,
)

// PT 이용권 추가 모달 열기
function openPackageDialog() {
  totalSessions.value = 10
  selectedCompanyId.value = ''
  addPackageError.value = ''
  packageDialog.value?.showModal()

  // 다른 화면에서 근무처 연결·보관 상태가 변경됐을 수 있으므로 최신 정보 조회
  void Promise.all([refetchMemberCompanies(), refetchCompanies()])
}

// PT 이용권 추가 모달 닫기
function closePackageDialog() {
  if (isAddingPackage.value) return

  packageDialog.value?.close()
}

// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isAddingPackage.value) {
    event.preventDefault()
  }
}

// PT 이용권 추가
async function submitPackage() {
  if (isAddingPackage.value || isCompaniesBusy.value) return

  // PT 횟수 유효성 검사
  if (!Number.isInteger(totalSessions.value) || totalSessions.value < 1) {
    addPackageError.value = 'PT 횟수는 1 이상의 정수여야 합니다.'
    return
  }

  // 조회된 활성 근무처 중 회원에게 연결된 근무처만 허용
  if (!isValidCompanySelected.value) {
    addPackageError.value = '회원에게 연결된 활성 근무처를 선택해 주세요.'
    return
  }

  addPackageError.value = ''

  try {
    // Supabase에 선택한 근무처의 PT 이용권 추가
    await addPtPackage({
      totalSessions: totalSessions.value,
      companyId: selectedCompanyId.value,
    })

    // 추가 성공 시 모달 닫기
    packageDialog.value?.close()
  } catch (error) {
    console.error('PT 이용권 추가 오류:', error)
    addPackageError.value =
      error instanceof Error ? error.message : 'PT 이용권 추가에 실패했습니다.'
  }
}

// 부모에서 모달 열기 함수를 사용할 수 있도록 공개
defineExpose({
  open: openPackageDialog,
})
</script>

<template>
  <!-- PT 이용권 추가 모달 -->
  <dialog
    ref="packageDialog"
    aria-labelledby="package-dialog-title"
    aria-describedby="package-dialog-description"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @cancel="handleCancel"
  >
    <!-- 모달 제목 -->
    <h2 id="package-dialog-title" class="text-xl font-bold text-slate-900">PT 이용권 추가</h2>

    <!-- 모달 설명 -->
    <p id="package-dialog-description" class="mt-2 text-sm text-slate-500">
      회원에게 추가할 PT 횟수와 근무처를 선택해 주세요.
    </p>

    <!-- PT 이용권 입력 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitPackage">
      <!-- 이용권을 등록할 근무처 -->
      <div>
        <label for="pt-package-company" class="mb-2 block text-sm font-medium text-slate-700">
          근무처
        </label>

        <!-- 회원에게 연결된 활성 근무처만 선택 -->
        <select
          id="pt-package-company"
          v-model="selectedCompanyId"
          required
          :disabled="
            isAddingPackage || isCompaniesBusy || isMemberCompaniesError || isCompaniesError
          "
          class="w-full rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        >
          <option value="" disabled>근무처를 선택해 주세요</option>
          <option v-for="company in availableCompanies" :key="company.id" :value="company.id">
            {{ company.name }}
          </option>
        </select>

        <!-- 근무처 조회 중 -->
        <p v-if="isCompaniesBusy" class="mt-2 text-xs text-slate-500">근무처를 불러오는 중...</p>

        <!-- 근무처 조회 오류 -->
        <p
          v-else-if="isMemberCompaniesError || isCompaniesError"
          role="alert"
          class="mt-2 text-xs text-red-600"
        >
          근무처 목록을 불러오지 못했습니다. 모달을 다시 열어 주세요.
        </p>

        <!-- 연결된 활성 근무처 없음 -->
        <p v-else-if="availableCompanies.length === 0" class="mt-2 text-xs text-amber-700">
          연결된 활성 근무처가 없습니다. 회원 상세 페이지에서 먼저 근무처를 연결해 주세요.
        </p>

        <p v-else class="mt-2 text-xs text-slate-500">회원에게 연결된 활성 근무처만 표시됩니다.</p>
      </div>

      <!-- 추가 PT 횟수 -->
      <div>
        <label for="package-sessions" class="mb-2 block text-sm font-medium text-slate-700">
          추가 PT 횟수
        </label>

        <input
          id="package-sessions"
          v-model.number="totalSessions"
          type="number"
          min="1"
          step="1"
          required
          :disabled="isAddingPackage"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- PT 이용권 추가 오류 메시지 -->
      <p v-if="addPackageError" role="alert" class="text-sm text-red-600">
        {{ addPackageError }}
      </p>

      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <button
          type="button"
          :disabled="isAddingPackage"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closePackageDialog"
        >
          취소
        </button>

        <button
          type="submit"
          :disabled="isSubmitDisabled"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {{ isAddingPackage ? '추가 중...' : '이용권 추가' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
