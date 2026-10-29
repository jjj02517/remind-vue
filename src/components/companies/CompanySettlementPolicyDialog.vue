<script setup lang="ts">
import { computed, ref } from 'vue'
import { useQueryClient } from '@tanstack/vue-query'
import { CalendarDays, LoaderCircle, X } from 'lucide-vue-next'

import {
  DEFAULT_SETTLEMENT_POLICY,
  getCompanySettlementPolicy,
  getCompanySettlementPolicyHistory,
  saveCompanySettlementPolicy,
  type CompanySettlementPolicy,
} from '@/api/companySettlementPolicies'
import { getTodayString } from '@/utils/date'
import { blockDemoWrite } from '@/utils/demoGuard'

// 근무처 정보
const props = defineProps<{
  companyId: string
  companyName: string
}>()

// 정산 기준 저장 완료 이벤트
const emit = defineEmits<{
  updated: []
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 정산 기준 설정 모달
const dialogRef = ref<HTMLDialogElement | null>(null)

// 적용 시작일
const effectiveFrom = ref('')

// 정산 정책 입력값
const includeNoShow = ref(false)
const includeSameDayCancelled = ref(false)

// 현재 선택한 날짜에 적용되는 정책
const appliedPolicy = ref<CompanySettlementPolicy | null>(null)

// 정산 정책 변경 이력
const policyHistory = ref<CompanySettlementPolicy[]>([])

// 조회 및 저장 상태
const isLoading = ref(false)
const isSaving = ref(false)
const errorMessage = ref('')

// 비동기 조회 결과가 뒤늦게 덮어쓰는 문제 방지
let loadVersion = 0

// 기존에 동일한 적용일로 등록된 정책이 있는지 확인
const hasExistingPolicyOnDate = computed(() =>
  policyHistory.value.some((policy) => policy.effective_from === effectiveFrom.value),
)

// 현재 선택된 정산 기준 설명
const selectedPolicyDescription = computed(() => {
  const included = ['실제 출석']

  if (includeNoShow.value) {
    included.push('노쇼')
  }

  if (includeSameDayCancelled.value) {
    included.push('당일 취소')
  }

  return included.join(' · ')
})

// 적용일 기준 정산 정책 조회
async function loadPolicy() {
  const version = ++loadVersion
  const companyId = props.companyId
  const targetDate = effectiveFrom.value

  if (!companyId || !targetDate) return

  isLoading.value = true
  errorMessage.value = ''

  try {
    // 선택 날짜의 적용 정책과 전체 변경 이력 조회
    const [policy, history] = await Promise.all([
      getCompanySettlementPolicy(companyId, targetDate),
      getCompanySettlementPolicyHistory(companyId),
    ])

    // 날짜 변경 또는 모달 종료 후 도착한 결과 무시
    if (version !== loadVersion) return

    appliedPolicy.value = policy
    policyHistory.value = history

    // 해당 날짜에 적용되는 기존 정책을 기본 입력값으로 사용
    includeNoShow.value = policy?.include_no_show ?? DEFAULT_SETTLEMENT_POLICY.includeNoShow

    includeSameDayCancelled.value =
      policy?.include_same_day_cancelled ?? DEFAULT_SETTLEMENT_POLICY.includeSameDayCancelled
  } catch (error) {
    if (version !== loadVersion) return

    console.error('정산 정책 조회 오류:', error)

    errorMessage.value = error instanceof Error ? error.message : '정산 기준을 불러오지 못했습니다.'
  } finally {
    if (version === loadVersion) {
      isLoading.value = false
    }
  }
}

// 정산 기준 설정 팝업 열기
function openDialog() {
  if (dialogRef.value?.open) return

  // 팝업을 열 때마다 오늘 날짜를 기준으로 설정
  effectiveFrom.value = getTodayString()
  includeNoShow.value = false
  includeSameDayCancelled.value = false

  appliedPolicy.value = null
  policyHistory.value = []
  errorMessage.value = ''

  dialogRef.value?.showModal()
  void loadPolicy()
}

// 정산 기준 설정 팝업 닫기
function closeDialog() {
  if (isLoading.value || isSaving.value) return

  dialogRef.value?.close()
}

// ESC 입력 처리
function handleCancel(event: Event) {
  if (isLoading.value || isSaving.value) {
    event.preventDefault()
  }
}

// 모달 종료 시 진행 중인 조회 결과 무효화
function handleClose() {
  loadVersion += 1
  isLoading.value = false
  errorMessage.value = ''
}

// 적용 시작일 변경
function handleDateChange() {
  void loadPolicy()
}

// 정산 기준 저장
async function handleSave() {
  if (isLoading.value || isSaving.value || errorMessage.value || !effectiveFrom.value) {
    return
  }

  // 과거 날짜를 선택한 경우 이전 정산이 변경될 수 있음을 안내
  if (effectiveFrom.value < getTodayString()) {
    const confirmed = window.confirm(
      '과거 날짜의 정산 기준을 등록하거나 변경하면 ' +
        '이전 수업의 예상 정산액이 다시 계산될 수 있습니다.\n\n' +
        '계속하시겠습니까?',
    )

    if (!confirmed) return
  }

  // 데모 계정에서는 서버에 저장하지 않음
  if (await blockDemoWrite()) return

  isSaving.value = true
  errorMessage.value = ''

  let isSuccess = false

  try {
    await saveCompanySettlementPolicy({
      companyId: props.companyId,
      effectiveFrom: effectiveFrom.value,
      includeNoShow: includeNoShow.value,
      includeSameDayCancelled: includeSameDayCancelled.value,
    })

    isSuccess = true
  } catch (error) {
    console.error('정산 정책 저장 오류:', error)

    errorMessage.value = error instanceof Error ? error.message : '정산 기준을 저장하지 못했습니다.'
  } finally {
    isSaving.value = false
  }

  if (!isSuccess) return

  // 저장 성공 이후 관련 캐시 갱신
  try {
    await Promise.all([
      queryClient.invalidateQueries({
        queryKey: ['company-settlement-policies'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['company-settlement-policy'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['company-settlement-policy-history'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['settlements'],
      }),
    ])
  } catch (error) {
    // DB 저장 성공과 캐시 갱신 오류 구분
    console.error('정산 정책 저장 후 캐시 갱신 오류:', error)
  }

  emit('updated')
  closeDialog()
}

// 부모에서 모달 열기 함수 사용
defineExpose({
  open: openDialog,
})
</script>

<template>
  <!-- 근무처별 정산 기준 설정 모달 -->
  <dialog
    ref="dialogRef"
    aria-labelledby="settlement-policy-title"
    class="fixed inset-0 m-auto max-h-[90vh] w-[calc(100%-2rem)] max-w-xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-6"
    @cancel="handleCancel"
    @close="handleClose"
  >
    <!-- 모달 제목 -->
    <div class="flex items-start justify-between gap-4">
      <div>
        <h2 id="settlement-policy-title" class="text-xl font-bold text-slate-900">
          정산 기준 설정
        </h2>

        <p class="mt-2 text-sm text-slate-500">
          {{ props.companyName }}
        </p>
      </div>

      <button
        type="button"
        aria-label="닫기"
        :disabled="isLoading || isSaving"
        class="rounded-lg p-2 text-slate-500 hover:bg-slate-100 disabled:opacity-50"
        @click="closeDialog"
      >
        <X :size="20" aria-hidden="true" />
      </button>
    </div>

    <!-- 정산 기준 설정 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="handleSave">
      <!-- 적용 시작일 -->
      <div>
        <label
          :for="`settlement-effective-date-${props.companyId}`"
          class="mb-2 block text-sm font-semibold text-slate-700"
        >
          적용 시작일
        </label>

        <div class="relative">
          <CalendarDays
            :size="18"
            class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"
            aria-hidden="true"
          />

          <input
            :id="`settlement-effective-date-${props.companyId}`"
            v-model="effectiveFrom"
            type="date"
            required
            :disabled="isLoading || isSaving"
            class="w-full rounded-lg border border-slate-200 bg-white py-3 pl-10 pr-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
            @change="handleDateChange"
          />
        </div>

        <p class="mt-2 text-xs leading-5 text-slate-500">
          선택한 날짜부터 이 정산 기준을 적용합니다. 이전 날짜는 기존 기준을 유지합니다.
        </p>

        <p v-if="hasExistingPolicyOnDate" class="mt-2 text-xs text-amber-700">
          해당 날짜에 등록된 정책이 있습니다. 저장하면 기존 설정을 변경합니다.
        </p>
      </div>

      <!-- 정산 정책 조회 중 -->
      <div
        v-if="isLoading"
        role="status"
        class="flex items-center gap-2 rounded-lg bg-slate-50 p-4 text-sm text-slate-500"
      >
        <LoaderCircle :size="18" class="animate-spin" />
        정산 기준을 불러오는 중...
      </div>

      <template v-else>
        <!-- 정산 대상 출석 상태 -->
        <fieldset class="space-y-3" :disabled="isSaving || !!errorMessage">
          <legend class="mb-3 text-sm font-semibold text-slate-800">정산에 포함할 출석 상태</legend>

          <!-- 실제 출석은 항상 포함 -->
          <div
            class="flex items-center justify-between gap-3 rounded-xl border border-slate-200 p-4"
          >
            <div>
              <p class="text-sm font-medium text-slate-800">실제 출석</p>
              <p class="mt-1 text-xs text-slate-500">실제 수업에 참여한 회원</p>
            </div>

            <span
              class="rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-700"
            >
              항상 포함
            </span>
          </div>

          <!-- 노쇼 정산 여부 -->
          <label
            class="flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-slate-200 p-4"
          >
            <span>
              <span class="block text-sm font-medium text-slate-800"> 노쇼 </span>
              <span class="mt-1 block text-xs text-slate-500">
                회원이 예약한 수업에 참석하지 않은 경우
              </span>
            </span>

            <input
              v-model="includeNoShow"
              type="checkbox"
              class="h-5 w-5 shrink-0 accent-blue-600"
            />
          </label>

          <!-- 당일 취소 정산 여부 -->
          <label
            class="flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-slate-200 p-4"
          >
            <span>
              <span class="block text-sm font-medium text-slate-800"> 당일 취소 </span>
              <span class="mt-1 block text-xs text-slate-500"> 수업 당일 예약이 취소된 경우 </span>
            </span>

            <input
              v-model="includeSameDayCancelled"
              type="checkbox"
              class="h-5 w-5 shrink-0 accent-blue-600"
            />
          </label>
        </fieldset>

        <!-- 적용 정책 요약 -->
        <div class="rounded-xl bg-blue-50 p-4">
          <p class="text-xs font-semibold text-blue-800">선택한 정산 기준</p>

          <p class="mt-2 text-sm leading-relaxed text-blue-900">
            {{ selectedPolicyDescription }}
          </p>

          <p class="mt-2 text-xs text-blue-700">
            일반 취소와 예정 수업은 확정 정산액에 포함하지 않습니다.
          </p>

          <p v-if="appliedPolicy" class="mt-2 text-xs text-blue-700">
            현재 적용 중인 정책 시작일:
            {{ appliedPolicy.effective_from }}
          </p>
        </div>
      </template>

      <!-- 정산 정책 변경 이력 -->
      <div v-if="policyHistory.length" class="border-t border-slate-200 pt-4">
        <h3 class="text-sm font-semibold text-slate-800">정산 정책 변경 이력</h3>

        <div class="mt-3 max-h-44 space-y-2 overflow-y-auto">
          <div
            v-for="policy in policyHistory"
            :key="policy.id"
            class="rounded-lg bg-slate-50 px-3 py-2.5"
          >
            <p class="text-xs font-semibold text-slate-700">{{ policy.effective_from }}부터</p>

            <p class="mt-1 text-xs leading-relaxed text-slate-500">
              실제 출석
              <span v-if="policy.include_no_show"> · 노쇼</span>
              <span v-if="policy.include_same_day_cancelled"> · 당일 취소 </span>
            </p>
          </div>
        </div>
      </div>

      <!-- 오류 안내 -->
      <p v-if="errorMessage" role="alert" class="rounded-lg bg-red-50 p-3 text-sm text-red-600">
        {{ errorMessage }}
      </p>

      <!-- 하단 버튼 -->
      <div class="flex justify-end gap-3 border-t border-slate-100 pt-4">
        <button
          type="button"
          :disabled="isLoading || isSaving"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50"
          @click="closeDialog"
        >
          취소
        </button>

        <button
          type="submit"
          :disabled="isLoading || isSaving || !!errorMessage"
          class="inline-flex items-center justify-center gap-2 rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300"
        >
          <LoaderCircle v-if="isSaving" :size="16" class="animate-spin" aria-hidden="true" />
          {{ isSaving ? '저장 중...' : '정산 기준 저장' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
