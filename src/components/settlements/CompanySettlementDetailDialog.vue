<script setup lang="ts">
import { computed, ref } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import { AlertCircle, CalendarDays, LoaderCircle, RefreshCw, Wallet, X } from 'lucide-vue-next'

import {
  getMonthlySettlementDetails,
  type MonthlySettlementDetail,
  type SettlementCalculationStatus,
} from '@/api/settlementDetails'

// 선택한 근무처 및 조회 연월
const props = defineProps<{
  companyId: string
  companyName: string
  year: number
  month: number
}>()

// 팝업 상태
const dialogRef = ref<HTMLDialogElement | null>(null)
const isOpen = ref(false)

// 정산 상세 내역 조회
const {
  data: details,
  isPending,
  isFetching,
  error,
  refetch,
} = useQuery({
  queryKey: computed(() => ['settlements', 'details', props.companyId, props.year, props.month]),

  queryFn: () =>
    getMonthlySettlementDetails({
      year: props.year,
      month: props.month,
      companyId: props.companyId,
    }),

  // 팝업이 열렸을 때만 데이터 조회
  enabled: computed(
    () =>
      isOpen.value &&
      !!props.companyId &&
      Number.isInteger(props.year) &&
      props.year >= 1900 &&
      props.year <= 9999 &&
      Number.isInteger(props.month) &&
      props.month >= 1 &&
      props.month <= 12,
  ),

  staleTime: 0,
  retry: false,
})

// 팝업 열기
function open() {
  if (!dialogRef.value || dialogRef.value.open) return

  dialogRef.value.showModal()
  isOpen.value = true
}

// 팝업 닫기
function close() {
  dialogRef.value?.close()
}

// ESC 등으로 팝업이 닫힌 경우에도 상태 초기화
function handleClose() {
  isOpen.value = false
}

// 부모 컴포넌트에서 open() 호출 가능
defineExpose({
  open,
  close,
})

// 정산 상세 데이터
const detailRows = computed<MonthlySettlementDetail[]>(() => details.value ?? [])

// 통화 코드 정리
// 현재 통화 설정 UI가 없으므로 UNSET은 원화로 표시
function normalizeCurrency(currencyCode: string) {
  if (!currencyCode || currencyCode === 'UNSET') {
    return 'KRW'
  }

  return currencyCode
}

// 통화별 정산 요약
interface DetailSummary {
  currencyCode: string
  confirmedCount: number
  confirmedAmount: number
  scheduledCount: number
  scheduledAmount: number
  excludedCount: number
  unpricedCount: number
}

const summaries = computed<DetailSummary[]>(() => {
  const summaryMap = new Map<string, DetailSummary>()

  for (const row of detailRows.value) {
    const currencyCode = normalizeCurrency(row.currency_code)

    let summary = summaryMap.get(currencyCode)

    if (!summary) {
      summary = {
        currencyCode,
        confirmedCount: 0,
        confirmedAmount: 0,
        scheduledCount: 0,
        scheduledAmount: 0,
        excludedCount: 0,
        unpricedCount: 0,
      }

      summaryMap.set(currencyCode, summary)
    }

    if (row.calculation_status === 'confirmed') {
      summary.confirmedCount += 1

      if (row.settlement_amount === null) {
        summary.unpricedCount += 1
      } else {
        summary.confirmedAmount += row.settlement_amount
      }
    } else if (row.calculation_status === 'scheduled') {
      summary.scheduledCount += 1

      if (row.settlement_amount === null) {
        summary.unpricedCount += 1
      } else {
        summary.scheduledAmount += row.settlement_amount
      }
    } else {
      summary.excludedCount += 1
    }
  }

  return Array.from(summaryMap.values()).sort((a, b) =>
    a.currencyCode.localeCompare(b.currencyCode),
  )
})

// 전체 단가 미설정 건수
const totalUnpricedCount = computed(() =>
  summaries.value.reduce((total, summary) => total + summary.unpricedCount, 0),
)

// 금액 표시
function formatMoney(amount: number | null, currencyCode: string) {
  if (amount === null) {
    return '단가 미설정'
  }

  const formatted = new Intl.NumberFormat('ko-KR', {
    maximumFractionDigits: 0,
  }).format(amount)

  const currency = normalizeCurrency(currencyCode)

  if (currency === 'KRW') {
    return `${formatted}원`
  }

  return `${formatted} ${currency}`
}

// 수업 날짜 표시 (한국 시간)
function formatSessionDate(value: string) {
  const date = new Date(value)

  if (Number.isNaN(date.getTime())) {
    return '-'
  }

  return new Intl.DateTimeFormat('ko-KR', {
    timeZone: 'Asia/Seoul',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date)
}

// 수업 유형 표시
function getSessionTypeLabel(type: string) {
  switch (type) {
    case 'pt':
      return 'PT'
    case 'group':
      return '그룹'
    default:
      return type
  }
}

// 출석 상태 표시
function getAttendanceLabel(status: string) {
  switch (status) {
    case 'attended':
      return '출석'
    case 'no_show':
      return '노쇼'
    case 'same_day_cancelled':
      return '당일 취소'
    case 'cancelled':
      return '일반 취소'
    case 'scheduled':
      return '예약'
    default:
      return status
  }
}

// 정산 분류 표시
function getCalculationLabel(status: SettlementCalculationStatus) {
  switch (status) {
    case 'confirmed':
      return '확정'
    case 'scheduled':
      return '예정'
    case 'excluded':
      return '제외'
  }
}

// 정산 분류 배지 스타일
function getCalculationClass(status: SettlementCalculationStatus) {
  switch (status) {
    case 'confirmed':
      return 'bg-emerald-50 text-emerald-700'
    case 'scheduled':
      return 'bg-blue-50 text-blue-700'
    case 'excluded':
      return 'bg-slate-100 text-slate-500'
  }
}
</script>

<template>
  <dialog
    ref="dialogRef"
    aria-labelledby="settlement-detail-title"
    class="fixed left-1/2 top-1/2 m-0 w-[calc(100%-24px)] max-w-5xl -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-slate-200 bg-white p-0 shadow-2xl backdrop:bg-slate-950/50"
    @close="handleClose"
  >
    <div class="flex max-h-[90vh] flex-col">
      <!-- 팝업 제목 -->
      <header
        class="flex shrink-0 items-start justify-between gap-4 border-b border-slate-100 px-5 py-4 sm:px-6"
      >
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <Wallet :size="20" class="shrink-0 text-blue-600" aria-hidden="true" />

            <h2 id="settlement-detail-title" class="text-lg font-bold text-slate-900">
              정산 상세 내역
            </h2>
          </div>

          <p class="mt-2 break-words text-sm font-medium text-slate-700">
            {{ companyName }}
          </p>

          <p class="mt-1 flex items-center gap-1 text-xs text-slate-500">
            <CalendarDays :size="14" aria-hidden="true" />
            {{ year }}년 {{ month }}월
          </p>
        </div>

        <button
          type="button"
          aria-label="정산 상세 내역 닫기"
          class="rounded-lg p-2 text-slate-400 transition hover:bg-slate-100 hover:text-slate-700"
          @click="close"
        >
          <X :size="20" aria-hidden="true" />
        </button>
      </header>

      <!-- 스크롤 가능한 본문 -->
      <div class="min-h-0 flex-1 space-y-5 overflow-y-auto px-5 py-5 sm:px-6">
        <!-- 조회 중 -->
        <div
          v-if="isPending"
          class="flex items-center justify-center gap-2 py-16 text-sm text-slate-500"
        >
          <LoaderCircle :size="20" class="animate-spin" aria-hidden="true" />
          정산 상세 내역을 불러오는 중...
        </div>

        <!-- 조회 오류 -->
        <div v-else-if="error" role="alert" class="rounded-xl border border-red-200 bg-red-50 p-5">
          <div class="flex items-start gap-3">
            <AlertCircle :size="20" class="shrink-0 text-red-500" aria-hidden="true" />

            <div>
              <p class="text-sm font-semibold text-red-700">
                정산 상세 내역을 불러오지 못했습니다.
              </p>

              <p class="mt-2 break-words text-xs text-red-600">
                {{ error.message }}
              </p>

              <button
                type="button"
                class="mt-3 text-sm font-medium text-blue-600 underline"
                @click="() => refetch()"
              >
                다시 시도
              </button>
            </div>
          </div>
        </div>

        <!-- 상세 내역 없음 -->
        <div v-else-if="detailRows.length === 0" class="py-16 text-center">
          <Wallet :size="32" class="mx-auto text-slate-300" aria-hidden="true" />

          <p class="mt-4 text-sm font-medium text-slate-700">수업별 정산 내역이 없습니다.</p>

          <p class="mt-2 text-xs text-slate-500">선택한 기간의 수업 기록을 확인해 주세요.</p>
        </div>

        <template v-else>
          <!-- 단가 미설정 안내 -->
          <div
            v-if="totalUnpricedCount > 0"
            role="status"
            class="flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4"
          >
            <AlertCircle :size="20" class="shrink-0 text-amber-600" aria-hidden="true" />

            <div>
              <p class="text-sm font-semibold text-amber-900">
                단가 미설정 {{ totalUnpricedCount }}건
              </p>

              <p class="mt-1 text-xs leading-relaxed text-amber-800">
                해당 수업 날짜에 적용되는 단가가 없어 금액을 계산하지 못했습니다. 근무처 관리에서
                단가 이력을 확인해 주세요.
              </p>
            </div>
          </div>

          <!-- 통화별 확정 및 예정 정산 요약 -->
          <section v-for="summary in summaries" :key="summary.currencyCode" class="space-y-3">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-sm font-semibold text-slate-800">정산 요약</h3>

              <span
                v-if="summary.currencyCode !== 'KRW'"
                class="rounded-full bg-slate-100 px-2.5 py-1 text-xs text-slate-600"
              >
                {{ summary.currencyCode }}
              </span>
            </div>

            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <!-- 확정 정산 금액 -->
              <div class="rounded-xl border border-slate-200 bg-slate-50 p-4">
                <p class="text-xs font-medium text-slate-500">확정 정산액</p>

                <p class="mt-2 break-words text-xl font-bold text-slate-900">
                  {{ formatMoney(summary.confirmedAmount, summary.currencyCode) }}
                </p>

                <p class="mt-1 text-xs text-slate-500">{{ summary.confirmedCount }}건</p>
              </div>

              <!-- 예정 정산 금액 -->
              <div class="rounded-xl border border-blue-200 bg-blue-50 p-4">
                <p class="text-xs font-medium text-blue-700">예정 정산액</p>

                <p class="mt-2 break-words text-xl font-bold text-blue-900">
                  {{ formatMoney(summary.scheduledAmount, summary.currencyCode) }}
                </p>

                <p class="mt-1 text-xs text-blue-700">{{ summary.scheduledCount }}건</p>
              </div>
            </div>

            <p class="text-xs text-slate-500">
              정산 제외 {{ summary.excludedCount }}건
              <template v-if="summary.unpricedCount > 0">
                · 단가 미설정 {{ summary.unpricedCount }}건
              </template>
            </p>
          </section>

          <!-- 수업별 정산 내역 -->
          <section class="space-y-3">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h3 class="text-sm font-semibold text-slate-900">수업별 정산 내역</h3>

              <span class="text-xs text-slate-500"> 전체 {{ detailRows.length }}건 </span>
            </div>

            <p class="text-xs leading-relaxed text-slate-500">
              그룹 수업은 참여 회원별로 한 건씩 표시합니다. 일반 취소 등 정산 제외 기록도 확인할 수
              있습니다.
            </p>

            <!-- 모바일 가로 스크롤 -->
            <div class="overflow-x-auto rounded-xl border border-slate-200">
              <table class="w-full min-w-[850px] text-sm">
                <thead class="bg-slate-50 text-xs text-slate-500">
                  <tr>
                    <th scope="col" class="px-4 py-3 text-left font-semibold">수업 날짜</th>

                    <th scope="col" class="px-4 py-3 text-left font-semibold">회원</th>

                    <th scope="col" class="px-4 py-3 text-left font-semibold">수업</th>

                    <th scope="col" class="px-4 py-3 text-left font-semibold">출석</th>

                    <th scope="col" class="px-4 py-3 text-left font-semibold">정산 분류</th>

                    <th scope="col" class="px-4 py-3 text-right font-semibold">적용 단가</th>

                    <th scope="col" class="px-4 py-3 text-right font-semibold">정산 금액</th>
                  </tr>
                </thead>

                <tbody class="divide-y divide-slate-100">
                  <tr v-for="row in detailRows" :key="row.attendance_id" class="hover:bg-slate-50">
                    <!-- 수업 날짜 -->
                    <td class="whitespace-nowrap px-4 py-3 text-slate-600">
                      {{ formatSessionDate(row.starts_at) }}
                    </td>

                    <!-- 회원 이름 -->
                    <td class="px-4 py-3 font-medium text-slate-800">
                      {{ row.member_name }}
                    </td>

                    <!-- 수업 유형 -->
                    <td class="px-4 py-3 text-slate-600">
                      {{ getSessionTypeLabel(row.session_type) }}
                    </td>

                    <!-- 출석 상태 -->
                    <td class="whitespace-nowrap px-4 py-3 text-slate-600">
                      {{ getAttendanceLabel(row.attendance_status) }}
                    </td>

                    <!-- 정산 분류 -->
                    <td class="px-4 py-3">
                      <span
                        class="inline-flex rounded-full px-2.5 py-1 text-xs font-medium"
                        :class="getCalculationClass(row.calculation_status)"
                      >
                        {{ getCalculationLabel(row.calculation_status) }}
                      </span>
                    </td>

                    <!-- 적용 단가 -->
                    <td class="whitespace-nowrap px-4 py-3 text-right tabular-nums text-slate-600">
                      {{
                        row.unit_rate === null
                          ? '미설정'
                          : formatMoney(row.unit_rate, row.currency_code)
                      }}
                    </td>

                    <!-- 정산 금액 -->
                    <td
                      class="whitespace-nowrap px-4 py-3 text-right font-semibold tabular-nums"
                      :class="
                        row.settlement_amount === null
                          ? 'text-amber-700'
                          : row.calculation_status === 'excluded'
                            ? 'text-slate-400'
                            : 'text-slate-900'
                      "
                    >
                      {{ formatMoney(row.settlement_amount, row.currency_code) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- 계산 기준 안내 -->
          <div class="rounded-lg bg-slate-50 p-4">
            <p class="text-xs leading-6 text-slate-600">
              확정 정산은 출석과 근무처별 정책에서 인정한 노쇼·당일 취소를 포함합니다. 예정 정산은
              예약된 수업의 예상 금액입니다. 정산 제외 기록은 0원으로 표시하며, 적용 단가를 찾을 수
              없는 정산 대상 기록은 '단가 미설정'으로 표시합니다.
            </p>
          </div>
        </template>
      </div>

      <!-- 팝업 하단 -->
      <footer
        class="flex shrink-0 items-center justify-between gap-3 border-t border-slate-100 bg-white px-5 py-4 sm:px-6"
      >
        <p class="text-xs text-slate-400">수업 기록 기준 자동 계산</p>

        <div class="flex items-center gap-2">
          <button
            type="button"
            :disabled="isFetching"
            class="inline-flex items-center gap-2 rounded-lg border border-slate-200 px-3 py-2 text-sm text-slate-600 transition hover:bg-slate-50 disabled:opacity-50"
            @click="() => refetch()"
          >
            <RefreshCw :size="15" :class="{ 'animate-spin': isFetching }" aria-hidden="true" />
            새로고침
          </button>

          <button
            type="button"
            class="rounded-lg bg-slate-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-slate-800"
            @click="close"
          >
            닫기
          </button>
        </div>
      </footer>
    </div>
  </dialog>
</template>
