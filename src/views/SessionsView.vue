<script setup lang="ts">
import { computed, ref } from 'vue'
import { CalendarDays, ChevronLeft, ChevronRight, MapPin, Plus } from 'lucide-vue-next'
import { useQuery, useQueryClient } from '@tanstack/vue-query'

import { getCalendarSessions } from '@/api/sessions'
import type { CalendarSession } from '@/api/sessions'

import SessionRegisterDialog from '@/components/sessions/SessionRegisterDialog.vue'
import SessionDetailDialog from '@/components/sessions/SessionDetailDialog.vue'

// ============================================
// 날짜 관련 공통 함수
// ============================================

// 브라우저 로컬 날짜를 YYYY-MM-DD 형식으로 변환
// toISOString()은 UTC 기준이라 한국 시간에서 날짜가 달라질 수 있으므로 사용하지 않음
function toDateKey(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')

  return `${year}-${month}-${day}`
}

// 오늘 날짜와 현재 선택 날짜
const today = ref(new Date())
const selectedDate = ref(toDateKey(today.value))

// 달력에 표시할 연도와 월 (1일 기준)
const visibleMonth = ref(new Date(today.value.getFullYear(), today.value.getMonth(), 1))

// 요일 표시 (일요일 시작)
const weekdays = ['일', '월', '화', '수', '목', '금', '토']

// ============================================
// Supabase 수업 조회
// ============================================

// 선택한 연·월에 등록된 수업을 실제 Supabase에서 조회
const {
  data: dbSessions,
  isPending: isSessionsLoading,
  error: sessionsError,
} = useQuery({
  queryKey: computed(() => [
    'sessions',
    visibleMonth.value.getFullYear(),
    visibleMonth.value.getMonth() + 1,
  ]),
  queryFn: () =>
    getCalendarSessions(visibleMonth.value.getFullYear(), visibleMonth.value.getMonth() + 1),
  staleTime: 1000 * 30,
})

const sessions = computed<CalendarSession[]>(() => dbSessions.value ?? [])

// 등록 또는 출석 상태 변경 후 수업 목록 갱신
const queryClient = useQueryClient()

async function refreshSessions() {
  await queryClient.invalidateQueries({
    queryKey: ['sessions'],
  })
}

// ============================================
// 수업 등록 모달
// ============================================

const registerDialog = ref<InstanceType<typeof SessionRegisterDialog> | null>(null)

function openRegisterDialog() {
  registerDialog.value?.open()
}

// 수업 등록 직후 달력 갱신
async function handleSessionRegistered() {
  await refreshSessions()
}

// ============================================
// 수업 상세 모달
// ============================================

// 현재 상세 화면에서 확인 중인 수업 ID
const selectedSessionId = ref<string | null>(null)

// 수업 카드를 클릭하면 상세 모달 열기
function openSessionDetail(sessionId: string) {
  selectedSessionId.value = sessionId
}

// 수업 상세 모달 닫기
function closeSessionDetail() {
  selectedSessionId.value = null
}

// 출석·노쇼·당일 취소 상태가 변경되면 달력 갱신
async function handleSessionUpdated() {
  await refreshSessions()
}

// ============================================
// 달력 연도 및 월 이동
// ============================================

// 현재 달력 상단의 연월 표시
const monthTitle = computed(() =>
  new Intl.DateTimeFormat('ko-KR', {
    year: 'numeric',
    month: 'long',
  }).format(visibleMonth.value),
)

// 연도 빠른 이동 옵션 (현재 보고 있는 연도를 중심으로 앞뒤 20년)
const yearOptions = computed(() => {
  const currentYear = visibleMonth.value.getFullYear()

  return Array.from({ length: 41 }, (_, index) => currentYear - 20 + index)
})

// 월 빠른 이동 옵션
const monthOptions = Array.from({ length: 12 }, (_, index) => index + 1)

// 연도 또는 월을 직접 선택하면 해당 월 1일을 선택
// 기존 이전/다음 달 이동과 선택 날짜 처리 방식 유지
function jumpToMonth(year: number, monthIndex: number) {
  const newMonth = new Date(year, monthIndex, 1)

  visibleMonth.value = newMonth
  selectedDate.value = toDateKey(newMonth)
}

// 달력에 표시할 연도 셀렉트
const selectedYear = computed({
  get: () => visibleMonth.value.getFullYear(),

  set: (year: number) => jumpToMonth(year, visibleMonth.value.getMonth()),
})

// 달력에 표시할 월 셀렉트 (1 ~ 12)
const selectedMonthNumber = computed({
  get: () => visibleMonth.value.getMonth() + 1,

  set: (month: number) => jumpToMonth(visibleMonth.value.getFullYear(), month - 1),
})

// ============================================
// 월간 달력 날짜 생성
// ============================================

// 월간 달력의 날짜 셀 생성 (앞뒤 달 날짜 포함)
const calendarDays = computed(() => {
  const year = visibleMonth.value.getFullYear()
  const month = visibleMonth.value.getMonth()

  const firstDay = new Date(year, month, 1)
  const lastDay = new Date(year, month + 1, 0)

  // 달력 첫 칸은 해당 월 1일이 속한 주의 일요일
  const startDay = firstDay.getDay()

  const numberOfCells = Math.ceil((startDay + lastDay.getDate()) / 7) * 7

  return Array.from({ length: numberOfCells }, (_, index) => {
    // 날짜 계산은 Date 생성자를 사용하여 월말과 윤년 처리
    const date = new Date(year, month, index - startDay + 1)

    const dateKey = toDateKey(date)

    return {
      dateKey,
      day: date.getDate(),
      weekday: date.getDay(),
      isCurrentMonth: date.getMonth() === month && date.getFullYear() === year,
      isToday: dateKey === toDateKey(today.value),
      isSelected: dateKey === selectedDate.value,
    }
  })
})

// ============================================
// 날짜별 수업 데이터
// ============================================

// 날짜별 수업 표시용 조회 맵
const sessionsByDate = computed(() => {
  const result = new Map<string, CalendarSession[]>()

  for (const session of sessions.value) {
    const existing = result.get(session.date) ?? []

    existing.push(session)
    result.set(session.date, existing)
  }

  return result
})

// 선택한 날짜의 수업을 시작 시간순으로 표시
const selectedSessions = computed(() =>
  [...(sessionsByDate.value.get(selectedDate.value) ?? [])].sort((a, b) =>
    a.startTime.localeCompare(b.startTime),
  ),
)

// 선택한 날짜의 제목 표시
const selectedDateLabel = computed(() => {
  const [year, month, day] = selectedDate.value.split('-').map(Number)

  return new Intl.DateTimeFormat('ko-KR', {
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  }).format(new Date(year!, month! - 1, day!))
})

// ============================================
// 달력 날짜 이동
// ============================================

// 이전 달 / 다음 달 이동
function moveMonth(offset: number) {
  const year = visibleMonth.value.getFullYear()
  const month = visibleMonth.value.getMonth()

  const newMonth = new Date(year, month + offset, 1)

  visibleMonth.value = newMonth

  // 다른 달로 이동하면 해당 달의 1일을 선택
  selectedDate.value = toDateKey(newMonth)
}

// 오늘로 이동
function goToToday() {
  const now = new Date()

  today.value = now

  visibleMonth.value = new Date(now.getFullYear(), now.getMonth(), 1)

  selectedDate.value = toDateKey(now)
}

// 날짜 선택: 앞뒤 달 날짜를 클릭하면 해당 월로 이동
function selectDate(dateKey: string) {
  selectedDate.value = dateKey

  const [year, month] = dateKey.split('-').map(Number)

  if (year !== visibleMonth.value.getFullYear() || month !== visibleMonth.value.getMonth() + 1) {
    visibleMonth.value = new Date(year!, month! - 1, 1)
  }
}

// ============================================
// 수업 정보 표시 함수
// ============================================

// 수업 종류 표시
function getSessionTypeLabel(type: CalendarSession['type']) {
  return type === 'pt' ? 'PT' : '그룹'
}

// 수업 진행 상태 표시 이름
function getSessionStatusLabel(status: CalendarSession['status']) {
  const labels: Record<CalendarSession['status'], string> = {
    scheduled: '예정',
    completed: '완료',
    cancelled: '취소',
  }

  return labels[status]
}

// 수업 진행 상태 배지 스타일
function getSessionStatusClass(status: CalendarSession['status']) {
  const styles: Record<CalendarSession['status'], string> = {
    scheduled: 'bg-sky-50 text-sky-700',
    completed: 'bg-green-50 text-green-700',
    cancelled: 'bg-slate-100 text-slate-500',
  }

  return styles[status]
}
</script>

<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold text-slate-900">수업 관리</h1>

      <p class="mt-2 text-sm text-slate-500">
        달력에서 날짜를 선택해 PT·그룹 수업 일정을 확인하세요.
      </p>
    </div>

    <!-- ============================================ -->
    <!-- PC: 달력과 일일 일정 나란히 / 모바일: 세로 배치 -->
    <!-- ============================================ -->
    <div class="grid items-start gap-5 lg:grid-cols-[minmax(0,1.15fr)_minmax(340px,0.85fr)]">
      <!-- ============================================ -->
      <!-- 월간 달력 -->
      <!-- ============================================ -->
      <section
        aria-label="월간 수업 달력"
        class="rounded-xl border border-slate-200 bg-white p-4 sm:p-6"
      >
        <!-- 달력 상단 연월 및 이동 버튼 -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex flex-wrap items-center gap-2">
            <CalendarDays :size="20" class="text-blue-600" aria-hidden="true" />

            <h2 class="sr-only">{{ monthTitle }} 수업 달력</h2>

            <!-- 연도 빠른 이동 -->
            <label for="session-calendar-year" class="sr-only"> 연도 선택 </label>

            <select
              id="session-calendar-year"
              v-model.number="selectedYear"
              class="rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-sm font-semibold text-slate-900 outline-none focus:border-blue-500 focus-visible:ring-2 focus-visible:ring-blue-100"
            >
              <option v-for="year in yearOptions" :key="year" :value="year">{{ year }}년</option>
            </select>

            <!-- 월 빠른 이동 -->
            <label for="session-calendar-month" class="sr-only"> 월 선택 </label>

            <select
              id="session-calendar-month"
              v-model.number="selectedMonthNumber"
              class="rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-sm font-semibold text-slate-900 outline-none focus:border-blue-500 focus-visible:ring-2 focus-visible:ring-blue-100"
            >
              <option v-for="month in monthOptions" :key="month" :value="month">
                {{ month }}월
              </option>
            </select>
          </div>

          <div class="flex items-center gap-2">
            <button
              type="button"
              class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-medium text-slate-700 transition hover:bg-slate-50 focus-visible:outline-2 focus-visible:outline-blue-600"
              @click="goToToday"
            >
              오늘
            </button>

            <button
              type="button"
              aria-label="이전 달"
              class="rounded-lg p-2 text-slate-600 transition hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-blue-600"
              @click="moveMonth(-1)"
            >
              <ChevronLeft :size="20" aria-hidden="true" />
            </button>

            <button
              type="button"
              aria-label="다음 달"
              class="rounded-lg p-2 text-slate-600 transition hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-blue-600"
              @click="moveMonth(1)"
            >
              <ChevronRight :size="20" aria-hidden="true" />
            </button>
          </div>
        </div>

        <!-- 요일 표시 -->
        <div
          class="mt-5 grid grid-cols-7 border-b border-slate-100 pb-2 text-center text-xs font-medium"
        >
          <span
            v-for="(weekday, index) in weekdays"
            :key="weekday"
            :class="
              index === 0 ? 'text-rose-500' : index === 6 ? 'text-blue-500' : 'text-slate-500'
            "
          >
            {{ weekday }}
          </span>
        </div>

        <!-- 날짜 선택 달력 -->
        <div class="mt-2 grid grid-cols-7 gap-1 sm:gap-1.5">
          <button
            v-for="day in calendarDays"
            :key="day.dateKey"
            type="button"
            :aria-label="`${day.dateKey} 날짜 선택`"
            :aria-pressed="day.isSelected"
            :aria-current="day.isToday ? 'date' : undefined"
            class="relative flex min-h-13 flex-col items-center justify-start rounded-lg px-1 py-2 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-blue-600 sm:min-h-16"
            :class="[
              day.isSelected
                ? 'bg-blue-600 font-semibold text-white hover:bg-blue-700'
                : day.isCurrentMonth
                  ? 'hover:bg-blue-50'
                  : 'text-slate-300 hover:bg-slate-50',

              !day.isSelected && day.isCurrentMonth && day.weekday === 0 ? 'text-rose-500' : '',

              !day.isSelected && day.isCurrentMonth && day.weekday === 6 ? 'text-blue-500' : '',

              !day.isSelected && day.isToday ? 'ring-1 ring-blue-500' : '',
            ]"
            @click="selectDate(day.dateKey)"
          >
            <span>{{ day.day }}</span>

            <!-- 해당 날짜에 수업이 있으면 종류별 점 표시 -->
            <span
              v-if="sessionsByDate.get(day.dateKey)?.length"
              class="mt-1 flex items-center gap-1"
            >
              <!-- PT: 파란색 -->
              <span
                v-if="sessionsByDate.get(day.dateKey)?.some((session) => session.type === 'pt')"
                class="h-1.5 w-1.5 rounded-full"
                :class="day.isSelected ? 'bg-sky-200' : 'bg-blue-500'"
              />

              <!-- 그룹 수업: 보라색 -->
              <span
                v-if="sessionsByDate.get(day.dateKey)?.some((session) => session.type === 'group')"
                class="h-1.5 w-1.5 rounded-full"
                :class="day.isSelected ? 'bg-fuchsia-200' : 'bg-violet-500'"
              />
            </span>
          </button>
        </div>

        <!-- 수업 종류 범례 -->
        <div
          class="mt-5 flex flex-wrap gap-4 border-t border-slate-100 pt-4 text-xs text-slate-500"
        >
          <span class="inline-flex items-center gap-1.5">
            <span class="h-2 w-2 rounded-full bg-blue-500" />
            PT 수업
          </span>

          <span class="inline-flex items-center gap-1.5">
            <span class="h-2 w-2 rounded-full bg-violet-500" />
            그룹 수업
          </span>
        </div>
      </section>

      <!-- ============================================ -->
      <!-- 날짜별 수업 목록 -->
      <!-- ============================================ -->
      <section
        aria-label="선택한 날짜의 수업 일정"
        class="rounded-xl border border-slate-200 bg-white p-4 sm:p-6"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-lg font-semibold text-slate-900">
              {{ selectedDateLabel }}
            </h2>

            <p class="mt-1 text-sm text-slate-500">총 {{ selectedSessions.length }}건의 수업</p>
          </div>

          <!-- 선택한 날짜에 새 수업 등록 -->
          <button
            type="button"
            class="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-blue-600 px-3 py-2 text-xs font-semibold text-white transition hover:bg-blue-700"
            @click="openRegisterDialog"
          >
            <Plus :size="15" aria-hidden="true" />
            수업 추가
          </button>
        </div>

        <!-- 수업 조회 중 또는 오류 -->
        <p v-if="isSessionsLoading" class="mt-6 text-sm text-slate-500">
          수업 일정을 불러오는 중...
        </p>

        <p v-else-if="sessionsError" role="alert" class="mt-6 text-sm text-red-600">
          수업 일정을 불러오지 못했습니다.
        </p>

        <!-- 선택한 날짜에 수업이 없는 경우 -->
        <div
          v-else-if="selectedSessions.length === 0"
          class="mt-6 rounded-lg border border-dashed border-slate-200 px-4 py-12 text-center"
        >
          <CalendarDays :size="28" class="mx-auto text-slate-300" aria-hidden="true" />

          <p class="mt-3 text-sm font-medium text-slate-700">이날 등록된 수업이 없습니다.</p>

          <p class="mt-2 text-xs text-slate-500">수업 추가 버튼으로 첫 일정을 등록해 보세요.</p>
        </div>

        <!-- 선택한 날짜에 수업이 있는 경우: 시간순 목록 -->
        <div v-else class="mt-5 space-y-3">
          <div v-for="session in selectedSessions" :key="session.id" class="flex gap-3">
            <!-- 수업 시작 및 종료 시간 -->
            <div class="w-14 shrink-0 pt-3 text-sm font-semibold tabular-nums text-slate-700">
              {{ session.startTime }}

              <p class="mt-1 text-xs font-normal text-slate-400">
                {{ session.endTime }}
              </p>
            </div>

            <!-- ============================================ -->
            <!-- 수업 카드: 클릭하면 상세 모달 열기 -->
            <!-- ============================================ -->
            <button
              type="button"
              class="min-w-0 flex-1 rounded-lg border border-l-4 border-slate-200 p-3.5 text-left transition hover:bg-slate-50 hover:shadow-sm focus-visible:outline-2 focus-visible:outline-blue-600"
              :class="session.type === 'pt' ? 'border-l-blue-500' : 'border-l-violet-500'"
              :aria-label="`${session.startTime} ${getSessionTypeLabel(session.type)} ${session.title} 수업 상세 보기`"
              @click="openSessionDetail(session.id)"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <div class="flex min-w-0 items-center gap-2">
                  <!-- 수업 종류 -->
                  <span
                    class="rounded-md px-2 py-1 text-xs font-semibold"
                    :class="
                      session.type === 'pt'
                        ? 'bg-blue-50 text-blue-700'
                        : 'bg-violet-50 text-violet-700'
                    "
                  >
                    {{ getSessionTypeLabel(session.type) }}
                  </span>

                  <!-- 수업명 -->
                  <p class="truncate text-sm font-semibold text-slate-900">
                    {{ session.title }}
                  </p>
                </div>

                <!-- 수업 진행 상태 -->
                <span
                  class="rounded-full px-2 py-1 text-xs font-medium"
                  :class="getSessionStatusClass(session.status)"
                >
                  {{ getSessionStatusLabel(session.status) }}
                </span>
              </div>

              <!-- 근무처 -->
              <p class="mt-2 flex items-center gap-1 text-xs text-slate-500">
                <MapPin :size="13" aria-hidden="true" />

                {{ session.companyName }}
              </p>
            </button>
          </div>
        </div>
      </section>
    </div>

    <!-- ============================================ -->
    <!-- 수업 등록 모달 -->
    <!-- ============================================ -->
    <SessionRegisterDialog
      ref="registerDialog"
      :initial-date="selectedDate"
      @registered="handleSessionRegistered"
    />

    <!-- ============================================ -->
    <!-- 수업 상세 및 출석 관리 모달 -->
    <!-- ============================================ -->
    <SessionDetailDialog
      v-if="selectedSessionId"
      :session-id="selectedSessionId"
      @close="closeSessionDetail"
      @updated="handleSessionUpdated"
    />
  </div>
</template>
