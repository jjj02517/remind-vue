<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { useQuery, useQueryClient } from '@tanstack/vue-query'
import {
  CalendarDays,
  MapPin,
  ArrowRight,
  LoaderCircle,
  CircleAlert,
  ChevronRight,
} from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'
import { getTrainerContext } from '@/api/trainerContext'
import type { SessionStatus, SessionType } from '@/api/sessions'
import SessionDetailDialog from '@/components/sessions/SessionDetailDialog.vue'

// ============================================
// 오늘의 수업 데이터 타입
// ============================================

interface TodaySession {
  id: string
  startTime: string
  endTime: string
  type: SessionType
  status: SessionStatus
  title: string
  companyName: string
}

// ============================================
// 트레이너 데이터 조회 컨텍스트
// ============================================

// 일반 사용자: 본인 데이터
// 데모 방문자: 데모 트레이너의 샘플 데이터
const trainerContext = ref<{
  trainerId: string
  isDemo: boolean
} | null>(null)

const isContextLoading = ref(true)
const contextError = ref('')

// 현재 사용자에 맞는 데이터 조회 기준 확인
onMounted(async () => {
  try {
    trainerContext.value = await getTrainerContext()
  } catch (error) {
    console.error('오늘의 수업 트레이너 컨텍스트 조회 오류:', error)
    contextError.value = '트레이너 정보를 확인하지 못했습니다.'
  } finally {
    isContextLoading.value = false
  }
})

const isContextReady = computed(() => !!trainerContext.value?.trainerId)
const isDemo = computed(() => trainerContext.value?.isDemo ?? false)

// ============================================
// 한국 시간 기준 오늘 날짜
// ============================================

function getKoreaDateKey(date: Date): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date)

  const value = (type: string) => parts.find((part) => part.type === type)?.value ?? ''

  return `${value('year')}-${value('month')}-${value('day')}`
}

const today = new Date()
const todayKey = getKoreaDateKey(today)

const todayLabel = new Intl.DateTimeFormat('ko-KR', {
  timeZone: 'Asia/Seoul',
  month: 'long',
  day: 'numeric',
  weekday: 'long',
}).format(today)

// 한국 시간 기준 오늘 00:00 ~ 내일 00:00
function getTodayBounds() {
  const [year, month, day] = todayKey.split('-').map(Number)

  const nextDate = new Date(Date.UTC(year!, month! - 1, day! + 1)).toISOString().slice(0, 10)

  return {
    start: new Date(`${todayKey}T00:00:00+09:00`).toISOString(),
    end: new Date(`${nextDate}T00:00:00+09:00`).toISOString(),
  }
}

const timeFormatter = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Seoul',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})

// ============================================
// Supabase 오늘의 수업 조회
// ============================================

const queryClient = useQueryClient()

const {
  data: todaySessions,
  isPending: isSessionsLoading,
  error: sessionsError,
} = useQuery({
  // 수업 관리에서 ['sessions'] 캐시를 갱신하면 함께 갱신
  // 일반 사용자와 데모 방문자의 캐시를 분리
  queryKey: computed(
    () => ['sessions', 'dashboard-today', todayKey, trainerContext.value?.trainerId ?? ''] as const,
  ),

  // 트레이너 정보를 확인한 후 조회
  enabled: isContextReady,

  queryFn: async ({ queryKey }): Promise<TodaySession[]> => {
    const [, , , trainerId] = queryKey

    if (!trainerId) {
      throw new Error('트레이너 정보가 없습니다.')
    }

    const bounds = getTodayBounds()

    // ============================================
    // 1. 오늘 등록된 수업 조회
    // ============================================

    const { data: sessions, error: sessionError } = await supabase
      .from('sessions')
      .select('id, company_id, session_type, status, starts_at, ends_at')
      .eq('trainer_id', trainerId)
      .is('deleted_at', null)
      .gte('starts_at', bounds.start)
      .lt('starts_at', bounds.end)
      .order('starts_at', { ascending: true })

    if (sessionError) throw sessionError

    if (!sessions?.length) return []

    const sessionIds = sessions.map((session) => session.id)

    const companyIds = [...new Set(sessions.map((session) => session.company_id))]

    // ============================================
    // 2. 근무처 및 수업 참여 회원 조회
    // ============================================

    const [companyResult, attendanceResult] = await Promise.all([
      supabase
        .from('companies')
        .select('id, name')
        .eq('trainer_id', trainerId)
        .in('id', companyIds),

      supabase
        .from('session_attendances')
        .select('session_id, member_id')
        .eq('trainer_id', trainerId)
        .in('session_id', sessionIds),
    ])

    if (companyResult.error) throw companyResult.error
    if (attendanceResult.error) throw attendanceResult.error

    const companyNames = new Map(
      (companyResult.data ?? []).map((company) => [company.id, company.name]),
    )

    const attendances = attendanceResult.data ?? []

    const memberIds = [...new Set(attendances.map((row) => row.member_id))]

    const memberResult = memberIds.length
      ? await supabase
          .from('members')
          .select('id, name')
          .eq('trainer_id', trainerId)
          .in('id', memberIds)
      : { data: [], error: null }

    if (memberResult.error) throw memberResult.error

    const memberNames = new Map((memberResult.data ?? []).map((member) => [member.id, member.name]))

    const membersBySession = new Map<string, string[]>()

    for (const attendance of attendances) {
      const names = membersBySession.get(attendance.session_id) ?? []

      names.push(memberNames.get(attendance.member_id) ?? '회원 확인 필요')

      membersBySession.set(attendance.session_id, names)
    }

    // ============================================
    // 3. 오늘의 수업 목록 구성
    // ============================================

    return sessions.map((session) => {
      const names = membersBySession.get(session.id) ?? []

      return {
        id: session.id,
        startTime: timeFormatter.format(new Date(session.starts_at)),
        endTime: timeFormatter.format(new Date(session.ends_at)),
        type: session.session_type as SessionType,
        status: session.status as SessionStatus,
        title:
          session.session_type === 'pt'
            ? (names[0] ?? '회원 확인 필요')
            : `그룹 수업 · ${names.length}명`,
        companyName: companyNames.get(session.company_id) ?? '근무처 확인 필요',
      }
    })
  },

  staleTime: 1000 * 30,
  refetchOnMount: 'always',
  refetchOnWindowFocus: 'always',
})

// ============================================
// 오늘의 수업 조회 상태
// ============================================

const isLoading = computed(() => {
  if (isContextLoading.value) return true
  if (contextError.value) return false

  return isSessionsLoading.value
})

const hasError = computed(() => !!contextError.value || !!sessionsError.value)

// ============================================
// 수업 상태 표시
// ============================================

const statusLabels: Record<SessionStatus, string> = {
  scheduled: '예정',
  completed: '처리 완료',
  cancelled: '취소',
}

function getStatusClass(status: SessionStatus): string {
  switch (status) {
    case 'completed':
      return 'bg-emerald-50 text-emerald-700'
    case 'cancelled':
      return 'bg-slate-100 text-slate-500'
    default:
      return 'bg-blue-50 text-blue-700'
  }
}

const sessionCount = computed(() => todaySessions.value?.length ?? 0)

// ============================================
// 수업 상세 팝업 관리
// ============================================

// 현재 선택한 수업 ID
// null이면 수업 상세 팝업을 표시하지 않음
const selectedSessionId = ref<string | null>(null)

// 오늘의 수업을 클릭하면 기존 상세 팝업 열기
function openSessionDetail(sessionId: string) {
  // 데모에서는 수업 상세 팝업의 조회 및 수정 기능을
  // 별도로 연결하기 전까지 기존 팝업을 열지 않음
  if (isDemo.value) {
    window.alert('데모 수업 상세 기능은 현재 준비 중입니다.')
    return
  }

  selectedSessionId.value = sessionId
}

// 상세 팝업 닫기
function closeSessionDetail() {
  selectedSessionId.value = null
}

// ============================================
// 수업 정보 변경 후 대시보드 갱신
// ============================================

// 기존 수업 상세 팝업에서 출석·운동 기록·일정을 저장하면 호출
// ['sessions'] 아래의 오늘 일정, 월간 수업 통계,
// 근무처별 월간 수업 통계를 함께 갱신
async function handleSessionUpdated() {
  await queryClient.invalidateQueries({
    queryKey: ['sessions'],
  })
}
</script>

<template>
  <section class="rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <div class="flex items-center gap-2">
          <CalendarDays :size="20" class="text-blue-600" aria-hidden="true" />

          <h2 class="text-lg font-semibold text-slate-900">오늘의 수업</h2>
        </div>

        <p class="mt-1 text-sm text-slate-500">{{ todayLabel }} 일정입니다.</p>
      </div>

      <span
        v-if="!isLoading && !hasError"
        class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-600"
      >
        총 {{ sessionCount }}건
      </span>
    </div>

    <div
      v-if="isLoading"
      class="flex items-center justify-center gap-2 py-10 text-sm text-slate-500"
    >
      <LoaderCircle :size="18" class="animate-spin" aria-hidden="true" />
      오늘의 수업을 불러오는 중...
    </div>

    <p
      v-else-if="hasError"
      role="alert"
      class="mt-5 rounded-lg bg-rose-50 p-4 text-sm text-rose-700"
    >
      <CircleAlert :size="18" aria-hidden="true" />
      오늘의 수업을 불러오지 못했습니다.
    </p>

    <div
      v-else-if="!todaySessions?.length"
      class="mt-5 rounded-lg bg-slate-50 px-4 py-10 text-center"
    >
      <CalendarDays :size="28" class="mx-auto text-slate-300" aria-hidden="true" />
      <p class="mt-3 text-sm font-medium text-slate-700">오늘 등록된 수업이 없습니다.</p>
    </div>

    <div v-else class="mt-5 space-y-3">
      <div v-for="session in todaySessions" :key="session.id" class="flex gap-3">
        <div class="w-14 shrink-0 pt-3">
          <p class="text-sm font-semibold tabular-nums text-slate-700">
            {{ session.startTime }}
          </p>

          <p class="mt-1 text-xs tabular-nums text-slate-400">
            {{ session.endTime }}
          </p>
        </div>

        <button
          type="button"
          class="min-w-0 flex-1 rounded-lg border border-slate-200 bg-white p-3.5 text-left transition-colors hover:border-blue-300 hover:bg-blue-50/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
          :aria-label="`${session.startTime} ${session.title} 수업 상세 열기`"
          @click="openSessionDetail(session.id)"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span
              class="rounded-md px-2 py-1 text-xs font-semibold"
              :class="
                session.type === 'pt' ? 'bg-blue-50 text-blue-700' : 'bg-violet-50 text-violet-700'
              "
            >
              {{ session.type === 'pt' ? 'PT' : '그룹' }}
            </span>

            <p class="min-w-0 flex-1 text-sm font-semibold text-slate-900">
              {{ session.title }}
            </p>

            <span
              class="rounded-full px-2.5 py-1 text-xs font-medium"
              :class="getStatusClass(session.status)"
            >
              {{ statusLabels[session.status] }}
            </span>

            <ChevronRight :size="16" class="shrink-0 text-slate-400" aria-hidden="true" />
          </div>

          <p class="mt-3 flex items-center gap-1 text-xs text-slate-500">
            <MapPin :size="13" aria-hidden="true" />
            {{ session.companyName }}
          </p>
        </button>
      </div>
    </div>

    <RouterLink
      to="/sessions"
      class="mt-5 flex items-center justify-center gap-2 border-t border-slate-100 pt-4 text-sm font-medium text-blue-600 hover:text-blue-700"
    >
      전체 일정 보기
      <ArrowRight :size="16" aria-hidden="true" />
    </RouterLink>

    <SessionDetailDialog
      v-if="selectedSessionId"
      :session-id="selectedSessionId"
      @close="closeSessionDetail"
      @updated="handleSessionUpdated"
    />
  </section>
</template>
