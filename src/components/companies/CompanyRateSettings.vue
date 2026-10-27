<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useMutation, useQueryClient } from '@tanstack/vue-query'

import type { Company } from '@/api/companies'
import type { CompanyRateVersion } from '@/api/companyRates'
import { addCompanyRateVersion } from '@/api/companyRates'
import { getTodayString } from '@/utils/date'

// 근무처와 전체 단가 변경 이력 중 해당 근무처 이력 전달받기
const props = defineProps<{
  company: Company
  rates: CompanyRateVersion[]
  isLoading: boolean
  hasError: boolean
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 단가 설정 폼 및 이력 펼침 상태
const showRateForm = ref(false)
const showHistory = ref(false)
const rateError = ref('')
const rateSuccess = ref('')

// 새 단가 적용일 및 정산 단가 입력값
const effectiveFrom = ref(getTodayString())
const ptRateInput = ref('')
const groupRateInput = ref('')

// 적용일이 최신순이고 같은 적용일에는 마지막으로 등록한 단가가 우선
const sortedRates = computed(() =>
  [...props.rates].sort((a, b) => b.effective_from.localeCompare(a.effective_from) || b.id - a.id),
)

// 선택한 날짜에 적용되는 마지막 단가 버전 조회
function getRateAtDate(date: string): CompanyRateVersion | undefined {
  return sortedRates.value.find((rate) => rate.effective_from <= date)
}

// 오늘 적용되는 단가 버전
const currentRate = computed(() => getRateAtDate(getTodayString()))

// 향후 적용 예정 단가 (가장 가까운 적용 시작일)
const nextRate = computed(
  () =>
    [...sortedRates.value]
      .filter((rate) => rate.effective_from > getTodayString())
      .sort((a, b) => a.effective_from.localeCompare(b.effective_from) || b.id - a.id)[0],
)

// 정산 단가 표시: null은 미설정, 0은 실제 0원
function formatRate(rate: number | null | undefined): string {
  return rate === null || rate === undefined ? '미설정' : `${rate.toLocaleString('ko-KR')}원`
}

// 입력란의 빈값은 미설정으로, 숫자는 정수로 처리
function parseRateInput(value: string | number): number | null | undefined {
  // Vue는 type="number" 입력값을 숫자로 변환할 수 있으므로 문자열로 통일
  const trimmed = String(value).trim()

  if (trimmed === '') return null
  if (!/^\d+$/.test(trimmed)) return undefined

  const rate = Number(trimmed)
  return Number.isSafeInteger(rate) ? rate : undefined
}

// 저장 가능 여부 확인
const isSaveDisabled = computed(() => {
  if (isSaving.value || !props.company.is_active || !effectiveFrom.value) return true

  const ptRate = parseRateInput(ptRateInput.value)
  const groupRate = parseRateInput(groupRateInput.value)

  return ptRate === undefined || groupRate === undefined || (ptRate === null && groupRate === null)
})

// 선택한 날짜에 이미 적용되는 단가를 입력값의 초기값으로 표시
function fillRatesAtDate() {
  const rate = getRateAtDate(effectiveFrom.value)
  ptRateInput.value = rate?.pt_rate_per_session == null ? '' : String(rate.pt_rate_per_session)
  groupRateInput.value =
    rate?.group_rate_per_attendee == null ? '' : String(rate.group_rate_per_attendee)
}

// 단가 설정 폼 열기
function openRateForm() {
  if (!props.company.is_active) return
  effectiveFrom.value = getTodayString()
  fillRatesAtDate()
  rateError.value = ''
  rateSuccess.value = ''
  showRateForm.value = true
}

// 적용일 변경 시 해당 날짜에 적용되는 단가로 입력값 갱신
watch(effectiveFrom, () => {
  if (showRateForm.value) fillRatesAtDate()
})

// 단가 설정 폼 닫기
function closeRateForm() {
  if (isSaving.value) return
  showRateForm.value = false
  rateError.value = ''
}

// 변경 이력을 추가하고 공통 캐시 갱신
const { mutateAsync: saveCompanyRate, isPending: isSaving } = useMutation({
  mutationFn: addCompanyRateVersion,
  onSuccess: async () => {
    await queryClient.invalidateQueries({ queryKey: ['company-rate-history'] })
  },
})

// 단가 변경 이력 저장
async function submitRateForm() {
  if (isSaveDisabled.value) return

  const ptRate = parseRateInput(ptRateInput.value)
  const groupRate = parseRateInput(groupRateInput.value)
  if (ptRate === undefined || groupRate === undefined) return

  rateError.value = ''
  rateSuccess.value = ''

  try {
    await saveCompanyRate({
      companyId: props.company.id,
      effectiveFrom: effectiveFrom.value,
      ptRatePerSession: ptRate,
      groupRatePerAttendee: groupRate,
    })

    showRateForm.value = false
    rateSuccess.value = `${effectiveFrom.value} 적용 단가를 이력에 추가했습니다.`
  } catch (error) {
    console.error('근무처 단가 등록 오류:', error)
    rateError.value = error instanceof Error ? error.message : '정산 단가 저장에 실패했습니다.'
  }
}
</script>

<template>
  <!-- 근무처 정산 단가 및 변경 이력 -->
  <section class="mt-4 border-t border-slate-100 pt-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h3 class="text-sm font-semibold text-slate-800">정산 단가</h3>
        <p class="mt-1 text-xs text-slate-500">PT는 수업 1회, 그룹은 출석 회원 1명 기준</p>
      </div>

      <!-- 단가 변경 및 기록 확인 -->
      <div class="flex flex-wrap gap-2">
        <button
          v-if="rates.length"
          type="button"
          :aria-expanded="showHistory"
          class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-medium text-slate-700 hover:bg-slate-50"
          @click="showHistory = !showHistory"
        >
          {{ showHistory ? '이력 닫기' : `변경 이력 (${rates.length})` }}
        </button>
        <button
          v-if="company.is_active"
          type="button"
          :disabled="isSaving || isLoading || hasError"
          class="rounded-lg border border-blue-200 px-3 py-2 text-xs font-semibold text-blue-700 hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="showRateForm ? closeRateForm() : openRateForm()"
        >
          {{ showRateForm ? '닫기' : currentRate ? '단가 변경' : '단가 설정' }}
        </button>
      </div>
    </div>

    <!-- 정산 단가 조회 상태 -->
    <p v-if="isLoading" class="mt-3 text-sm text-slate-500">정산 단가를 불러오는 중...</p>
    <p v-else-if="hasError" role="alert" class="mt-3 text-sm text-red-600">
      정산 단가를 불러오지 못했습니다.
    </p>

    <!-- 오늘 기준 정산 단가 -->
    <template v-else>
      <div class="mt-3 grid grid-cols-2 gap-2">
        <div class="rounded-lg bg-slate-50 p-3">
          <p class="text-xs text-slate-500">PT · 1회</p>
          <p class="mt-1 text-sm font-semibold text-slate-900">
            {{ formatRate(currentRate?.pt_rate_per_session) }}
          </p>
        </div>
        <div class="rounded-lg bg-slate-50 p-3">
          <p class="text-xs text-slate-500">그룹 · 출석 1명</p>
          <p class="mt-1 text-sm font-semibold text-slate-900">
            {{ formatRate(currentRate?.group_rate_per_attendee) }}
          </p>
        </div>
      </div>

      <p v-if="currentRate" class="mt-2 text-xs text-slate-500">
        {{ currentRate.effective_from.replaceAll('-', '.') }}부터 적용 중
      </p>
      <p v-else class="mt-2 text-xs text-slate-400">현재 적용 중인 단가가 없습니다.</p>

      <!-- 미래에 적용할 정산 단가 -->
      <p v-if="nextRate" class="mt-2 text-xs text-blue-700">
        다음 변경 예정: {{ nextRate.effective_from.replaceAll('-', '.') }}부터 PT
        {{ formatRate(nextRate.pt_rate_per_session) }} · 그룹
        {{ formatRate(nextRate.group_rate_per_attendee) }}
      </p>
    </template>

    <p v-if="rateSuccess" role="status" class="mt-3 text-xs text-green-700">
      {{ rateSuccess }}
    </p>

    <!-- 정산 단가 설정 폼 -->
    <form
      v-if="showRateForm && !isLoading && !hasError"
      class="mt-4 space-y-3 rounded-xl border border-blue-100 bg-blue-50/40 p-4"
      @submit.prevent="submitRateForm"
    >
      <div>
        <label
          :for="`rate-effective-${company.id}`"
          class="mb-1 block text-xs font-medium text-slate-700"
        >
          적용 시작일
        </label>
        <input
          :id="`rate-effective-${company.id}`"
          v-model="effectiveFrom"
          type="date"
          required
          :disabled="isSaving"
          class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <label
            :for="`rate-pt-${company.id}`"
            class="mb-1 block text-xs font-medium text-slate-700"
          >
            PT 1회 단가 (원)
          </label>
          <input
            :id="`rate-pt-${company.id}`"
            v-model="ptRateInput"
            type="number"
            min="0"
            step="1"
            inputmode="numeric"
            placeholder="예: 35000"
            :disabled="isSaving"
            class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          />
        </div>

        <div>
          <label
            :for="`rate-group-${company.id}`"
            class="mb-1 block text-xs font-medium text-slate-700"
          >
            그룹 출석 1명 단가 (원)
          </label>
          <input
            :id="`rate-group-${company.id}`"
            v-model="groupRateInput"
            type="number"
            min="0"
            step="1"
            inputmode="numeric"
            placeholder="예: 10000"
            :disabled="isSaving"
            class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          />
        </div>
      </div>

      <p class="text-xs leading-relaxed text-slate-500">
        비워두면 미설정, 0을 입력하면 0원으로 저장됩니다. 변경할 때는 두 단가를 함께 저장하며, 이전
        기록은 수정하거나 삭제하지 않습니다. 같은 날짜에 재설정하면 마지막 기록이 적용됩니다.
      </p>
      <p v-if="rateError" role="alert" class="text-xs text-red-600">{{ rateError }}</p>
      <div class="flex justify-end gap-2">
        <button
          type="button"
          :disabled="isSaving"
          class="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm text-slate-600 hover:bg-slate-50 disabled:opacity-50"
          @click="closeRateForm"
        >
          취소
        </button>
        <button
          type="submit"
          :disabled="isSaveDisabled"
          class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300"
        >
          {{ isSaving ? '저장 중...' : '변경 이력 저장' }}
        </button>
      </div>
    </form>

    <!-- 정산 단가 변경 이력: 보관된 근무처도 조회 가능 -->
    <div v-if="showHistory && !isLoading && !hasError" class="mt-4 border-t border-slate-100 pt-3">
      <h4 class="text-xs font-semibold text-slate-700">단가 변경 이력</h4>
      <ol class="mt-2 space-y-2">
        <li
          v-for="rate in sortedRates"
          :key="rate.id"
          class="rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-600"
        >
          <div class="flex flex-wrap items-center justify-between gap-1">
            <span class="font-medium text-slate-800">
              {{ rate.effective_from.replaceAll('-', '.') }} 적용
            </span>
            <span v-if="rate.id === currentRate?.id" class="text-blue-700">현재 단가</span>
            <span v-else-if="rate.effective_from > getTodayString()" class="text-slate-500">
              적용 예정
            </span>
          </div>
          <p class="mt-1">
            PT {{ formatRate(rate.pt_rate_per_session) }} · 그룹
            {{ formatRate(rate.group_rate_per_attendee) }}
          </p>
          <p class="mt-1 text-slate-400">
            기록: {{ new Date(rate.created_at).toLocaleString('ko-KR') }}
          </p>
        </li>
      </ol>
    </div>
  </section>
</template>
