<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'

import { getCompanies } from '@/api/companies'
import { supabase } from '@/lib/supabase'

// 부모 컴포넌트에서 회원 ID 전달받기
const props = defineProps<{
  memberId: string
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 그룹 횟수제 이용권 추가 모달
const groupPackageDialog = ref<HTMLDialogElement | null>(null)

// 모달 열림 상태 (열린 동안에만 근무처 조회)
const isDialogOpen = ref(false)

// 그룹 수업 횟수 입력
const totalSessions = ref<number>(10)

// 이용권 추가 오류 메시지
const registerError = ref('')

// 선택한 근무처 ID
const selectedCompanyId = ref('')

// 해당 회원에게 연결된 활성 근무처 목록 조회
const {
  data: availableCompanies,
  isPending: isCompaniesLoading,
  isFetching: isCompaniesFetching,
  error: companiesError,
  refetch: refetchCompanies,
} = useQuery({
  // 회원별로 근무처 조회 캐시 구분
  queryKey: computed(() => ['group-package-companies', props.memberId]),

  // 회원과 연결된 근무처 중 활성 근무처만 반환
  queryFn: async () => {
    const { data: links, error } = await supabase
      .from('company_members')
      .select('company_id')
      .eq('member_id', props.memberId)

    if (error) throw error

    const linkedCompanyIds = new Set((links ?? []).map((link) => link.company_id))
    if (!linkedCompanyIds.size) return []

    // 기존 근무처 조회 API를 재사용하여 근무처 이름과 보관 여부 확인
    const companies = await getCompanies()
    return companies.filter((company) => company.is_active && linkedCompanyIds.has(company.id))
  },

  // 모달이 열린 경우에만 조회
  enabled: computed(() => isDialogOpen.value && !!props.memberId),
  staleTime: 0,
})

// 근무처가 하나면 자동 선택, 여러 개면 직접 선택
watch(availableCompanies, (companies) => {
  if (!isDialogOpen.value) return

  if (companies?.length === 1) {
    selectedCompanyId.value = companies[0]!.id
    return
  }

  // 이전 선택 근무처가 보관되거나 연결 해제된 경우 선택 초기화
  if (!companies?.some((company) => company.id === selectedCompanyId.value)) {
    selectedCompanyId.value = ''
  }
})

// 근무처 목록 재조회
function retryCompanies() {
  void refetchCompanies()
}

// 그룹 횟수제 이용권 추가 Mutation
const { mutateAsync: registerGroupPackage, isPending: isRegistering } = useMutation({
  // 기존 회원에게 선택한 근무처의 그룹 횟수제 이용권 추가
  mutationFn: async (params: { sessions: number; companyId: string }) => {
    // 근무처가 포함된 신규 Supabase RPC 호출
    const { data, error } = await supabase.rpc('add_group_package', {
      p_member_id: props.memberId,
      p_total_sessions: params.sessions,
      p_company_id: params.companyId,
    })

    if (error) throw error
    return data
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
    ])
  },
})

// 이용권 추가 버튼 비활성화 조건
const isSubmitDisabled = computed(() => {
  if (isRegistering.value) return true
  if (!props.memberId) return true
  if (isCompaniesLoading.value || isCompaniesFetching.value || companiesError.value) return true

  // 회원과 연결된 활성 근무처 중 하나를 선택했는지 확인
  if (!(availableCompanies.value ?? []).some((company) => company.id === selectedCompanyId.value)) {
    return true
  }

  // 횟수는 1 이상의 정수만 허용
  return !Number.isInteger(totalSessions.value) || totalSessions.value < 1
})

// 그룹 이용권 추가 모달 열기
function openGroupPackageDialog() {
  // 입력값 초기화
  totalSessions.value = 10
  registerError.value = ''
  selectedCompanyId.value = ''
  isDialogOpen.value = true

  // 조회가 캐시에 남아 있는 경우에도 단일 근무처 기본 선택
  if (availableCompanies.value?.length === 1) {
    selectedCompanyId.value = availableCompanies.value[0]!.id
  }

  groupPackageDialog.value?.showModal()

  // 모달을 다시 열 때마다 연결 관계와 활성 상태 갱신
  void refetchCompanies()
}

// 그룹 이용권 추가 모달 닫기
function closeGroupPackageDialog() {
  if (isRegistering.value) return

  groupPackageDialog.value?.close()
}

// 모달이 닫힐 때 조회 비활성화
function handleDialogClose() {
  isDialogOpen.value = false
}

// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isRegistering.value) {
    event.preventDefault()
  }
}

// 그룹 횟수제 이용권 등록
async function submitGroupPackage() {
  if (isSubmitDisabled.value) return

  registerError.value = ''

  try {
    // Supabase RPC로 선택한 근무처에 그룹 횟수제 이용권 추가
    await registerGroupPackage({
      sessions: totalSessions.value,
      companyId: selectedCompanyId.value,
    })

    // 등록 성공 시 모달 닫기
    groupPackageDialog.value?.close()
  } catch (error) {
    console.error('그룹 이용권 추가 오류:', error)

    registerError.value =
      error instanceof Error ? error.message : '그룹 이용권 추가에 실패했습니다.'
  }
}

// 부모 컴포넌트에서 모달 열기 함수 사용
defineExpose({
  open: openGroupPackageDialog,
})
</script>

<template>
  <!-- 그룹 횟수제 이용권 추가 모달 -->
  <dialog
    ref="groupPackageDialog"
    aria-labelledby="group-package-dialog-title"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @cancel="handleCancel"
    @close="handleDialogClose"
  >
    <!-- 모달 제목 -->
    <h2 id="group-package-dialog-title" class="text-xl font-bold text-slate-900">
      그룹 이용권 추가
    </h2>

    <!-- 모달 설명 -->
    <p class="mt-2 text-sm text-slate-500">기존 회원에게 그룹 수업 횟수제 이용권을 추가합니다.</p>

    <!-- 그룹 이용권 등록 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitGroupPackage">
      <!-- 근무처 선택 -->
      <div>
        <label for="group-package-company" class="mb-2 block text-sm font-medium text-slate-700">
          근무처
        </label>

        <!-- 근무처 조회 중 -->
        <p v-if="isCompaniesLoading || isCompaniesFetching" class="text-sm text-slate-500">
          연결된 근무처를 불러오는 중...
        </p>

        <!-- 근무처 조회 오류 -->
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
          연결된 활성 근무처가 없습니다. 회원 상세 화면에서 먼저 근무처를 연결해 주세요.
        </p>

        <!-- 회원과 연결된 활성 근무처만 선택 -->
        <select
          v-else
          id="group-package-company"
          v-model="selectedCompanyId"
          required
          :disabled="isRegistering"
          class="w-full rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        >
          <option value="" disabled>근무처를 선택해 주세요</option>
          <option v-for="company in availableCompanies" :key="company.id" :value="company.id">
            {{ company.name }}
          </option>
        </select>

        <p class="mt-2 text-xs text-slate-500">회원에게 연결된 활성 근무처만 선택할 수 있습니다.</p>
      </div>

      <!-- 총 그룹 수업 횟수 -->
      <div>
        <label for="group-total-sessions" class="mb-2 block text-sm font-medium text-slate-700">
          총 그룹 수업 횟수
        </label>

        <input
          id="group-total-sessions"
          v-model.number="totalSessions"
          type="number"
          min="1"
          step="1"
          required
          :disabled="isRegistering"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- 그룹 이용권 안내 -->
      <div class="rounded-lg bg-slate-50 p-4">
        <p class="text-sm text-slate-700">그룹 횟수제 이용권은 수업 참석 시 횟수가 차감됩니다.</p>

        <p class="mt-2 text-xs text-slate-500">기존 PT 및 월 회원권은 변경되지 않습니다.</p>
      </div>

      <!-- 그룹 이용권 등록 오류 -->
      <p v-if="registerError" role="alert" class="text-sm text-red-600">
        {{ registerError }}
      </p>

      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <button
          type="button"
          :disabled="isRegistering"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closeGroupPackageDialog"
        >
          취소
        </button>

        <!-- 그룹 이용권 추가 -->
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
