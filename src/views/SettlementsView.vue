<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import {
  AlertCircle,
  Building2,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Download,
  LoaderCircle,
  RefreshCw,
  Wallet,
} from 'lucide-vue-next'
import { supabase } from '@/lib/supabase'
import { getMonthlySettlements, type MonthlySettlement } from '@/api/settlements'
import { getTodayString } from '@/utils/date'
import { downloadSettlementExcel } from '@/utils/downloadSettlementExcel'
import CompanySettlementDetailDialog from '@/components/settlements/CompanySettlementDetailDialog.vue'

// 오늘 날짜를 기준으로 조회 연월 초기화
const today = getTodayString()
const selectedYear = ref(Number(today.slice(0, 4)))
const selectedMonth = ref(Number(today.slice(5, 7)))

// 근무처 필터
const selectedCompanyId = ref('all')

// 엑셀 다운로드 진행 상태 및 오류
const isExporting = ref(false)
const exportError = ref('')

// 현재 조회 중인 연도·월·근무처의 정산 내역을 엑셀로 다운로드
async function handleDownloadExcel() {
  if (isExporting.value || !authUserId.value || !isValidYearMonth.value) return

  exportError.value = ''
  isExporting.value = true

  try {
    // 클릭 당시 조회 조건을 사용해 선택 값이 바뀌어도 요청 범위 유지
    const year = selectedYear.value
    const month = selectedMonth.value
    const companyId = selectedCompanyId.value === 'all' ? null : selectedCompanyId.value

    await downloadSettlementExcel({ year, month, companyId })
  } catch (error) {
    console.error('정산 엑셀 다운로드 오류:', error)
    exportError.value =
      error instanceof Error ? error.message : '정산 엑셀을 다운로드하지 못했습니다.'
  } finally {
    isExporting.value = false
  }
}

// 수업별 정산 상세 팝업
const detailDialogRef = ref<InstanceType<typeof CompanySettlementDetailDialog> | null>(null)
const detailCompany = ref<{ id: string; name: string } | null>(null)

// 근무처 이름을 클릭하면 해당 월의 정산 상세 내역 표시
async function openSettlementDetail(row: MonthlySettlement) {
  detailCompany.value = {
    id: row.company_id,
    name: row.company_name,
  }

  // 선택한 근무처 정보가 팝업에 전달된 이후 열기
  await nextTick()
  detailDialogRef.value?.open()
}

// 로그인한 사용자 정보
const authUserId = ref<string | null>(null)
const isAuthLoading = ref(true)
const authError = ref('')

// 조회 연월 유효성 검사
const isValidYearMonth = computed(
  () =>
    Number.isInteger(selectedYear.value) &&
    selectedYear.value >= 1900 &&
    selectedYear.value <= 9999 &&
    Number.isInteger(selectedMonth.value) &&
    selectedMonth.value >= 1 &&
    selectedMonth.value <= 12,
)

// 월별 정산 데이터 조회
const {
  data: settlements,
  isPending,
  isFetching,
  error: queryError,
  refetch,
} = useQuery({
  // 로그인한 사용자와 조회 연월별로 캐시 구분
  queryKey: computed(() => [
    'settlements',
    authUserId.value,
    selectedYear.value,
    selectedMonth.value,
  ]),
  queryFn: () =>
    getMonthlySettlements({
      year: selectedYear.value,
      month: selectedMonth.value,
    }),
  // 사용자 확인 및 유효한 조회 연월일 때만 조회
  enabled: computed(() => !!authUserId.value && isValidYearMonth.value),
  staleTime: 1000 * 60,
  retry: false,
})

// 이전 달 또는 다음 달로 이동
function changeMonth(offset: number) {
  const date = new Date(Date.UTC(selectedYear.value, selectedMonth.value - 1 + offset, 1))
  const nextYear = date.getUTCFullYear()
  if (nextYear < 1900 || nextYear > 9999) return
  selectedYear.value = nextYear
  selectedMonth.value = date.getUTCMonth() + 1
}

// 조회 연월 변경 시 전체 근무처로 초기화
watch([selectedYear, selectedMonth], () => {
  selectedCompanyId.value = 'all'
})

// 조회 조건이 변경되면 이전 다운로드 오류 메시지 초기화
watch([selectedYear, selectedMonth, selectedCompanyId], () => {
  exportError.value = ''
})

// 조회 결과에 포함된 근무처 목록
const companyOptions = computed(() => {
  const companyMap = new Map<string, string>()
  for (const settlement of settlements.value ?? []) {
    companyMap.set(settlement.company_id, settlement.company_name)
  }
  return Array.from(companyMap, ([id, name]) => ({
    id,
    name,
  })).sort((a, b) => a.name.localeCompare(b.name, 'ko'))
})

// 선택한 근무처의 정산 내역만 표시
const filteredSettlements = computed<MonthlySettlement[]>(() => {
  const rows = settlements.value ?? []
  const filtered =
    selectedCompanyId.value === 'all'
      ? rows
      : rows.filter((row) => row.company_id === selectedCompanyId.value)

  // 단가 이력이 없는 수업은 화면에서 KRW로 표시하되, 미설정 건수는 보존
  // 같은 근무처의 KRW/UNSET 결과가 두 행으로 나뉘지 않도록 합산
  const combined = new Map<string, MonthlySettlement>()

  for (const row of filtered) {
    const currencyCode = row.currency_code === 'UNSET' ? 'KRW' : row.currency_code
    const key = `${row.company_id}:${currencyCode}`
    const previous = combined.get(key)

    if (previous) {
      previous.confirmed_units += row.confirmed_units
      previous.confirmed_amount += row.confirmed_amount
      previous.scheduled_units += row.scheduled_units
      previous.scheduled_amount += row.scheduled_amount
      previous.unpriced_confirmed_units += row.unpriced_confirmed_units
      previous.unpriced_scheduled_units += row.unpriced_scheduled_units
    } else {
      combined.set(key, { ...row, currency_code: currencyCode })
    }
  }

  return Array.from(combined.values())
})

// 통화별 정산 요약 타입
interface SettlementSummary {
  currencyCode: string
  confirmedUnits: number
  confirmedAmount: number
  scheduledUnits: number
  scheduledAmount: number
  unpricedConfirmedUnits: number
  unpricedScheduledUnits: number
}

// 서로 다른 통화는 합산하지 않음
const currencySummaries = computed<SettlementSummary[]>(() => {
  const summaryMap = new Map<string, SettlementSummary>()
  for (const row of filteredSettlements.value) {
    let summary = summaryMap.get(row.currency_code)
    if (!summary) {
      summary = {
        currencyCode: row.currency_code,
        confirmedUnits: 0,
        confirmedAmount: 0,
        scheduledUnits: 0,
        scheduledAmount: 0,
        unpricedConfirmedUnits: 0,
        unpricedScheduledUnits: 0,
      }
      summaryMap.set(row.currency_code, summary)
    }
    summary.confirmedUnits += row.confirmed_units
    summary.confirmedAmount += row.confirmed_amount
    summary.scheduledUnits += row.scheduled_units
    summary.scheduledAmount += row.scheduled_amount
    summary.unpricedConfirmedUnits += row.unpriced_confirmed_units
    summary.unpricedScheduledUnits += row.unpriced_scheduled_units
  }
  return Array.from(summaryMap.values()).sort((a, b) =>
    a.currencyCode.localeCompare(b.currencyCode),
  )
})

// 단가 미설정 정산 건수
const totalUnpricedUnits = computed(() =>
  filteredSettlements.value.reduce(
    (total, row) => total + row.unpriced_confirmed_units + row.unpriced_scheduled_units,
    0,
  ),
)

// 통화별 금액 표시
function formatMoney(amount: number, currencyCode: string) {
  const formatted = new Intl.NumberFormat('ko-KR', {
    maximumFractionDigits: 0,
  }).format(amount)
  if (currencyCode === 'KRW') {
    return `${formatted}원`
  }
  return `${formatted} ${currencyCode}`
}

// 회원별 출석 기록 단위로 계산하므로 건수로 표시
function formatUnits(units: number) {
  return `${units.toLocaleString('ko-KR')}건`
}

// 로그인한 사용자 확인
onMounted(async () => {
  try {
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser()
    if (error) throw error
    if (!user) {
      throw new Error('로그인이 필요합니다.')
    }
    // 계정 간 정산 캐시가 섞이지 않도록 사용자 ID 사용
    authUserId.value = user.id
  } catch (error) {
    console.error('정산 관리 로그인 확인 오류:', error)
    authError.value = error instanceof Error ? error.message : '로그인 정보를 확인할 수 없습니다.'
  } finally {
    isAuthLoading.value = false
  }
})
</script>

<template>
  <div class="space-y-6">
    <!-- 페이지 제목 -->
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">정산 관리</h1>
        <p class="mt-2 text-sm leading-relaxed text-slate-500">
          근무처별 수업 단가와 정산 기준을 적용한 월별 수입 현황입니다.
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <!-- 선택한 조회 조건으로 정산 엑셀 다운로드 -->
        <button
          type="button"
          :disabled="
            !authUserId ||
            !isValidYearMonth ||
            isPending ||
            isFetching ||
            !!queryError ||
            isExporting
          "
          class="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
          @click="handleDownloadExcel"
        >
          <LoaderCircle v-if="isExporting" :size="16" class="animate-spin" aria-hidden="true" />
          <Download v-else :size="16" aria-hidden="true" />
          {{ isExporting ? '엑셀 생성 중...' : '엑셀 다운로드' }}
        </button>

        <!-- 정산 데이터 새로고침 -->
        <button
          type="button"
          :disabled="!authUserId || !isValidYearMonth || isFetching"
          class="inline-flex items-center gap-2 rounded-lg border border-slate-200 bg-white px-4 py-2.5 text-sm font-medium text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="() => refetch()"
        >
          <RefreshCw :size="16" :class="{ 'animate-spin': isFetching }" aria-hidden="true" />
          새로고침
        </button>
      </div>
    </header>
    <!-- 조회 조건 -->
    <section class="rounded-xl border border-slate-200 bg-white p-4 sm:p-5">
      <div class="mb-4 flex items-center gap-2">
        <CalendarDays :size="18" class="text-blue-600" aria-hidden="true" />
        <h2 class="text-sm font-semibold text-slate-900">조회 조건</h2>
      </div>
      <div class="flex flex-wrap items-end gap-3">
        <!-- 이전 달 -->
        <button
          type="button"
          aria-label="이전 달"
          class="flex h-11 w-11 items-center justify-center rounded-lg border border-slate-200 text-slate-600 transition hover:bg-slate-50"
          @click="changeMonth(-1)"
        >
          <ChevronLeft :size="20" aria-hidden="true" />
        </button>
        <!-- 조회 연도 -->
        <div class="min-w-0 flex-1 sm:flex-none">
          <label for="settlement-year" class="mb-2 block text-xs font-medium text-slate-600">
            연도
          </label>
          <input
            id="settlement-year"
            v-model.number="selectedYear"
            type="number"
            min="1900"
            max="9999"
            step="1"
            class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-700 outline-none focus:border-blue-500 sm:w-28"
          />
        </div>
        <!-- 조회 월 -->
        <div class="min-w-0 flex-1 sm:flex-none">
          <label for="settlement-month" class="mb-2 block text-xs font-medium text-slate-600">
            월
          </label>
          <select
            id="settlement-month"
            v-model.number="selectedMonth"
            class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-700 outline-none focus:border-blue-500 sm:w-24"
          >
            <option v-for="month in 12" :key="month" :value="month">{{ month }}월</option>
          </select>
        </div>
        <!-- 다음 달 -->
        <button
          type="button"
          aria-label="다음 달"
          class="flex h-11 w-11 items-center justify-center rounded-lg border border-slate-200 text-slate-600 transition hover:bg-slate-50"
          @click="changeMonth(1)"
        >
          <ChevronRight :size="20" aria-hidden="true" />
        </button>
        <!-- 근무처별 필터 -->
        <div class="w-full sm:w-auto sm:min-w-52 sm:flex-1">
          <label for="settlement-company" class="mb-2 block text-xs font-medium text-slate-600">
            근무처
          </label>
          <select
            id="settlement-company"
            v-model="selectedCompanyId"
            class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-700 outline-none focus:border-blue-500"
          >
            <option value="all">전체 근무처</option>
            <option v-for="company in companyOptions" :key="company.id" :value="company.id">
              {{ company.name }}
            </option>
          </select>
        </div>
      </div>
      <p class="mt-3 text-xs text-slate-500">
        수업 날짜는 한국 시간(Asia/Seoul)을 기준으로 집계합니다. 엑셀 다운로드에도 현재 선택한
        기간과 근무처가 적용됩니다.
      </p>
    </section>

    <!-- 정산 엑셀 다운로드 오류 -->
    <div
      v-if="exportError"
      role="alert"
      class="flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 p-4"
    >
      <AlertCircle :size="20" class="shrink-0 text-red-500" aria-hidden="true" />
      <p class="text-sm text-red-700">{{ exportError }}</p>
    </div>
    <!-- 로그인 정보 확인 중 -->
    <div
      v-if="isAuthLoading"
      class="flex items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-6 py-12 text-sm text-slate-500"
    >
      <LoaderCircle :size="20" class="animate-spin" aria-hidden="true" />
      로그인 정보를 확인하는 중...
    </div>
    <!-- 로그인 오류 -->
    <div
      v-else-if="authError"
      role="alert"
      class="rounded-xl border border-red-200 bg-white p-6 text-sm text-red-600"
    >
      {{ authError }}
    </div>
    <!-- 조회 연월 오류 -->
    <div
      v-else-if="!isValidYearMonth"
      role="alert"
      class="rounded-xl border border-amber-200 bg-white p-6 text-sm text-amber-700"
    >
      올바른 조회 연도와 월을 선택해 주세요.
    </div>
    <!-- 정산 데이터 조회 중 -->
    <div
      v-else-if="isPending"
      class="flex items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-6 py-12 text-sm text-slate-500"
    >
      <LoaderCircle :size="20" class="animate-spin" aria-hidden="true" />
      월별 정산 데이터를 불러오는 중...
    </div>
    <!-- 정산 데이터 조회 오류 -->
    <div v-else-if="queryError" role="alert" class="rounded-xl border border-red-200 bg-white p-6">
      <div class="flex items-start gap-3">
        <AlertCircle :size="20" class="shrink-0 text-red-500" aria-hidden="true" />
        <div>
          <p class="text-sm font-semibold text-red-700">정산 정보를 불러오지 못했습니다.</p>
          <p class="mt-2 break-words text-xs text-red-600">
            {{ queryError.message }}
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
    <!-- 조회 성공 -->
    <template v-else>
      <!-- 정산 대상 데이터 없음 -->
      <div
        v-if="filteredSettlements.length === 0"
        class="rounded-xl border border-slate-200 bg-white px-6 py-14 text-center"
      >
        <Wallet :size="32" class="mx-auto text-slate-300" aria-hidden="true" />
        <h2 class="mt-4 text-base font-semibold text-slate-800">정산 내역이 없습니다.</h2>
        <p class="mt-2 text-sm text-slate-500">선택한 기간과 근무처에 정산 대상 수업이 없습니다.</p>
      </div>
      <template v-else>
        <!-- 단가 미설정 안내 -->
        <div
          v-if="totalUnpricedUnits > 0"
          role="status"
          class="flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4"
        >
          <AlertCircle :size="20" class="shrink-0 text-amber-600" aria-hidden="true" />
          <div>
            <p class="text-sm font-semibold text-amber-900">
              단가 미설정 {{ formatUnits(totalUnpricedUnits) }}
            </p>
            <p class="mt-1 text-xs leading-relaxed text-amber-800">
              일부 수업의 단가를 확인할 수 없어 금액 계산에서 제외했습니다. 근무처 관리에서 해당
              날짜의 단가 이력을 확인해 주세요.
            </p>
          </div>
        </div>
        <!-- 통화별 정산 요약 -->
        <section v-for="summary in currencySummaries" :key="summary.currencyCode" class="space-y-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="flex items-center gap-2 text-lg font-semibold text-slate-900">
              <Wallet :size="20" class="text-blue-600" aria-hidden="true" />
              월별 정산 요약
            </h2>
            <span
              v-if="summary.currencyCode !== 'KRW'"
              class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-600"
            >
              {{ summary.currencyCode }}
            </span>
          </div>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <!-- 확정 정산액 -->
            <div class="rounded-xl border border-slate-200 bg-white p-5">
              <p class="text-sm font-medium text-slate-500">확정 정산액</p>
              <p class="mt-3 break-words text-2xl font-bold text-slate-900">
                {{ formatMoney(summary.confirmedAmount, summary.currencyCode) }}
              </p>
              <p class="mt-2 text-xs text-slate-500">
                정산 대상 {{ formatUnits(summary.confirmedUnits) }}
              </p>
            </div>
            <!-- 예정 정산액 -->
            <div class="rounded-xl border border-slate-200 bg-white p-5">
              <p class="text-sm font-medium text-slate-500">예정 정산액</p>
              <p class="mt-3 break-words text-2xl font-bold text-blue-700">
                {{ formatMoney(summary.scheduledAmount, summary.currencyCode) }}
              </p>
              <p class="mt-2 text-xs text-slate-500">
                예약 예정 {{ formatUnits(summary.scheduledUnits) }}
              </p>
            </div>
            <!-- 확정 및 예정 합계 -->
            <div class="rounded-xl border border-blue-200 bg-blue-50 p-5">
              <p class="text-sm font-medium text-blue-700">확정 + 예정 합계</p>
              <p class="mt-3 break-words text-2xl font-bold text-blue-900">
                {{
                  formatMoney(
                    summary.confirmedAmount + summary.scheduledAmount,
                    summary.currencyCode,
                  )
                }}
              </p>
              <p class="mt-2 text-xs text-blue-700">단가가 설정된 내역 기준</p>
            </div>
          </div>
          <p
            v-if="summary.unpricedConfirmedUnits > 0 || summary.unpricedScheduledUnits > 0"
            class="text-xs text-amber-700"
          >
            단가 미설정: 확정 {{ formatUnits(summary.unpricedConfirmedUnits) }} · 예정
            {{ formatUnits(summary.unpricedScheduledUnits) }}
          </p>
        </section>
        <!-- 근무처별 정산 현황 -->
        <section class="rounded-xl border border-slate-200 bg-white">
          <div class="border-b border-slate-100 px-5 py-4">
            <div class="flex items-center gap-2">
              <Building2 :size="20" class="text-blue-600" aria-hidden="true" />
              <h2 class="text-base font-semibold text-slate-900">근무처별 정산 현황</h2>
            </div>
            <p class="mt-2 text-xs text-slate-500">
              그룹 수업은 회원별 출석 기록 단위로 집계합니다. 근무처 이름을 클릭하면 수업별 정산
              상세 내역을 볼 수 있습니다.
            </p>
          </div>
          <!-- 모바일에서는 가로 스크롤 -->
          <div class="overflow-x-auto">
            <table class="min-w-[760px] w-full text-sm">
              <thead class="bg-slate-50 text-xs text-slate-500">
                <tr>
                  <th scope="col" class="px-5 py-3 text-left font-semibold">근무처</th>
                  <th scope="col" class="px-4 py-3 text-right font-semibold">확정 건수</th>
                  <th scope="col" class="px-4 py-3 text-right font-semibold">확정 정산액</th>
                  <th scope="col" class="px-4 py-3 text-right font-semibold">예정 건수</th>
                  <th scope="col" class="px-4 py-3 text-right font-semibold">예정 정산액</th>
                  <th scope="col" class="px-5 py-3 text-right font-semibold">단가 미설정</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100">
                <tr
                  v-for="row in filteredSettlements"
                  :key="`${row.company_id}-${row.currency_code}`"
                  class="hover:bg-slate-50"
                >
                  <td class="px-5 py-4">
                    <button
                      type="button"
                      class="rounded text-left font-semibold text-blue-700 underline-offset-4 transition hover:text-blue-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
                      :aria-label="`${row.company_name} ${selectedYear}년 ${selectedMonth}월 정산 상세 보기`"
                      @click="openSettlementDetail(row)"
                    >
                      {{ row.company_name }}
                    </button>
                    <p v-if="row.currency_code !== 'KRW'" class="mt-1 text-xs text-slate-400">
                      {{ row.currency_code }}
                    </p>
                  </td>
                  <td class="px-4 py-4 text-right tabular-nums text-slate-700">
                    {{ formatUnits(row.confirmed_units) }}
                  </td>
                  <td class="px-4 py-4 text-right font-semibold tabular-nums text-slate-900">
                    {{ formatMoney(row.confirmed_amount, row.currency_code) }}
                  </td>
                  <td class="px-4 py-4 text-right tabular-nums text-slate-700">
                    {{ formatUnits(row.scheduled_units) }}
                  </td>
                  <td class="px-4 py-4 text-right font-medium tabular-nums text-blue-700">
                    {{ formatMoney(row.scheduled_amount, row.currency_code) }}
                  </td>
                  <td class="px-5 py-4 text-right tabular-nums">
                    <span
                      :class="
                        row.unpriced_confirmed_units + row.unpriced_scheduled_units > 0
                          ? 'font-semibold text-amber-700'
                          : 'text-slate-400'
                      "
                    >
                      {{ formatUnits(row.unpriced_confirmed_units + row.unpriced_scheduled_units) }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
        <!-- 정산 집계 기준 안내 -->
        <section class="rounded-xl border border-slate-200 bg-white p-5">
          <h2 class="text-sm font-semibold text-slate-900">정산 계산 안내</h2>
          <p class="mt-3 text-xs leading-6 text-slate-600">
            확정 정산액은 실제 출석과 근무처별 정책에서 인정한 노쇼·당일 취소를 기준으로 계산합니다.
            예정 정산액은 예약 상태의 수업을 기준으로 계산합니다. 수업 날짜에 적용되는 단가와 정산
            정책을 사용하며, 일반 취소와 삭제된 수업은 제외합니다.
          </p>
          <p class="mt-2 text-xs leading-6 text-slate-500">
            이 화면은 트레이너의 수업 및 예상 수입을 기록용으로 확인하는 화면입니다. 확정 정산액은
            정산 대상 금액이며, 실제 지급 완료를 의미하지 않습니다.
          </p>
        </section>
      </template>
    </template>

    <!-- 근무처별 수업 정산 상세 내역 팝업 -->
    <CompanySettlementDetailDialog
      v-if="detailCompany"
      ref="detailDialogRef"
      :company-id="detailCompany.id"
      :company-name="detailCompany.name"
      :year="selectedYear"
      :month="selectedMonth"
    />
  </div>
</template>
