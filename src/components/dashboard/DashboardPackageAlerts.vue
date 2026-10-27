<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { useQuery } from '@tanstack/vue-query'
import {
  Bell,
  AlertCircle,
  CalendarClock,
  ChevronRight,
  LoaderCircle,
  Ticket,
} from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'

// ============================================
// 알림 기준
// ============================================

const LOW_REMAINING_THRESHOLD = 3
const EXPIRING_DAYS_THRESHOLD = 7
const INITIAL_VISIBLE_COUNT = 5

// ============================================
// 이용권 및 알림 데이터 타입
// ============================================

interface PackageRow {
  id: string
  member_id: string
  package_type: string
  usage_type: string
  remaining_sessions: number | null
  starts_on: string | null
  ends_on: string | null
}

interface PackageAlert {
  id: string
  memberId: string
  memberName: string
  packageName: string
  remainingSessions: number | null
  endsOn: string | null
  daysUntilExpiry: number | null
}

interface DashboardPackageAlerts {
  lowRemaining: PackageAlert[]
  expiringSoon: PackageAlert[]
}

// ============================================
// 한국 시간 기준 날짜 계산
// ============================================

function getKoreaDateKey(): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date())

  const value = (type: string) => parts.find((part) => part.type === type)?.value ?? ''

  return `${value('year')}-${value('month')}-${value('day')}`
}

const todayKey = ref(getKoreaDateKey())

function syncToday() {
  todayKey.value = getKoreaDateKey()
}

onMounted(() => {
  window.addEventListener('focus', syncToday)
})

onUnmounted(() => {
  window.removeEventListener('focus', syncToday)
})

// 날짜 차이는 UTC 날짜 단위로 계산하여 시차 영향을 방지
function getDaysBetween(start: string, end: string): number {
  const startTime = Date.parse(`${start}T00:00:00Z`)
  const endTime = Date.parse(`${end}T00:00:00Z`)

  return Math.round((endTime - startTime) / 86400000)
}

function formatDate(date: string | null): string {
  if (!date) return '미설정'

  const [, month, day] = date.slice(0, 10).split('-')
  return `${Number(month)}.${String(day).padStart(2, '0')}`
}

function getExpiryLabel(days: number | null): string {
  if (days === null) return ''

  return days === 0 ? '오늘 만료' : `D-${days}`
}

// ============================================
// 이용권 종류 표시
// ============================================

function getPackageName(pkg: PackageRow): string {
  if (pkg.package_type === 'pt') return 'PT 이용권'

  if (pkg.package_type === 'membership') return '월 회원권'

  if (pkg.package_type === 'group') {
    return pkg.usage_type === 'count' ? '그룹 이용권' : '그룹 기간권'
  }

  return '기타 이용권'
}

// ============================================
// Supabase 이용권 알림 조회
// ============================================

const {
  data: alerts,
  isPending: isLoading,
  isFetching,
  error: alertsError,
  refetch,
} = useQuery({
  queryKey: computed(() => ['member-packages', 'dashboard-alerts', todayKey.value]),

  queryFn: async (): Promise<DashboardPackageAlerts> => {
    // RLS를 통해 로그인한 트레이너의 이용권만 조회
    const { data: packages, error: packagesError } = await supabase
      .from('member_packages')
      .select('id, member_id, package_type, usage_type, remaining_sessions, starts_on, ends_on')
      .eq('status', 'active')

    if (packagesError) throw packagesError

    const packageRows = (packages ?? []) as PackageRow[]

    if (!packageRows.length) {
      return {
        lowRemaining: [],
        expiringSoon: [],
      }
    }

    // ============================================
    // 관리 중 회원 정보 조회
    // ============================================

    const memberIds = [...new Set(packageRows.map((pkg) => pkg.member_id))]

    const { data: members, error: membersError } = await supabase
      .from('members')
      .select('id, name')
      .in('id', memberIds)
      .neq('status', 'archived')

    if (membersError) throw membersError

    const memberNames = new Map((members ?? []).map((member) => [member.id, member.name]))

    const lowRemaining: PackageAlert[] = []
    const expiringSoon: PackageAlert[] = []

    // ============================================
    // 알림 조건별 데이터 분류
    // ============================================

    for (const pkg of packageRows) {
      const memberName = memberNames.get(pkg.member_id)

      // 보관 회원 또는 조회 대상이 아닌 회원 제외
      if (!memberName) continue

      // 아직 개시하지 않은 이용권 제외
      if (pkg.starts_on && pkg.starts_on > todayKey.value) {
        continue
      }

      const endsOn = pkg.ends_on?.slice(0, 10) ?? null

      const daysUntilExpiry = endsOn ? getDaysBetween(todayKey.value, endsOn) : null

      // 실제 종료일이 지난 이용권은 이번 알림 대상에서 제외
      if (daysUntilExpiry !== null && daysUntilExpiry < 0) {
        continue
      }

      const remainingSessions = pkg.remaining_sessions

      const alert: PackageAlert = {
        id: pkg.id,
        memberId: pkg.member_id,
        memberName,
        packageName: getPackageName(pkg),
        remainingSessions,
        endsOn,
        daysUntilExpiry,
      }

      // PT·그룹 횟수제 이용권 잔여 0~3회
      if (
        pkg.usage_type === 'count' &&
        remainingSessions !== null &&
        remainingSessions >= 0 &&
        remainingSessions <= LOW_REMAINING_THRESHOLD
      ) {
        lowRemaining.push(alert)
      }

      // 종료일이 오늘부터 7일 이내인 이용권
      if (
        daysUntilExpiry !== null &&
        daysUntilExpiry >= 0 &&
        daysUntilExpiry <= EXPIRING_DAYS_THRESHOLD
      ) {
        expiringSoon.push(alert)
      }
    }

    // 잔여 횟수가 적은 순
    lowRemaining.sort(
      (a, b) =>
        (a.remainingSessions ?? 0) - (b.remainingSessions ?? 0) ||
        a.memberName.localeCompare(b.memberName, 'ko'),
    )

    // 만료일이 가까운 순
    expiringSoon.sort(
      (a, b) =>
        (a.daysUntilExpiry ?? 0) - (b.daysUntilExpiry ?? 0) ||
        a.memberName.localeCompare(b.memberName, 'ko'),
    )

    return {
      lowRemaining,
      expiringSoon,
    }
  },

  staleTime: 0,
  refetchOnMount: 'always',
  refetchOnWindowFocus: 'always',
})

// ============================================
// 알림 목록 펼치기 / 접기
// ============================================

const showAllLowRemaining = ref(false)
const showAllExpiring = ref(false)

const lowRemainingAlerts = computed(() => alerts.value?.lowRemaining ?? [])

const expiringAlerts = computed(() => alerts.value?.expiringSoon ?? [])

const visibleLowRemaining = computed(() =>
  showAllLowRemaining.value
    ? lowRemainingAlerts.value
    : lowRemainingAlerts.value.slice(0, INITIAL_VISIBLE_COUNT),
)

const visibleExpiring = computed(() =>
  showAllExpiring.value
    ? expiringAlerts.value
    : expiringAlerts.value.slice(0, INITIAL_VISIBLE_COUNT),
)
</script>

<template>
  <section
    aria-label="이용권 관리 알림"
    class="rounded-xl border border-slate-200 bg-white p-5 sm:p-6"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <div class="flex items-center gap-2">
          <Bell :size="20" class="text-blue-600" aria-hidden="true" />

          <h2 class="text-lg font-semibold text-slate-900">이용권 관리 알림</h2>
        </div>

        <p class="mt-2 text-sm text-slate-500">
          잔여 횟수가 적거나 만료일이 가까운 이용권을 확인하세요.
        </p>
      </div>

      <span
        v-if="isFetching && !isLoading"
        class="inline-flex items-center gap-1.5 text-xs text-slate-400"
      >
        <LoaderCircle :size="14" class="animate-spin" aria-hidden="true" />
        갱신 중
      </span>
    </div>

    <div
      v-if="isLoading"
      class="flex items-center justify-center gap-2 py-10 text-sm text-slate-500"
    >
      <LoaderCircle :size="18" class="animate-spin" aria-hidden="true" />
      이용권 알림을 불러오는 중...
    </div>

    <div
      v-else-if="alertsError"
      role="alert"
      class="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-lg bg-rose-50 p-4"
    >
      <div class="flex items-center gap-2 text-sm text-rose-700">
        <AlertCircle :size="18" aria-hidden="true" />
        이용권 알림을 불러오지 못했습니다.
      </div>

      <button
        type="button"
        class="rounded-lg border border-rose-200 bg-white px-3 py-2 text-xs font-medium text-rose-700 hover:bg-rose-100"
        @click="refetch()"
      >
        다시 시도
      </button>
    </div>

    <div v-else class="mt-5 grid grid-cols-1 gap-4 lg:grid-cols-2">
      <div class="rounded-xl border border-slate-200 p-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <Ticket :size="18" class="text-rose-500" aria-hidden="true" />
            <h3 class="text-sm font-semibold text-slate-900">잔여 횟수 부족</h3>
          </div>

          <span class="rounded-full bg-rose-50 px-2.5 py-1 text-xs font-semibold text-rose-600">
            {{ lowRemainingAlerts.length }}건
          </span>
        </div>

        <p class="mt-2 text-xs text-slate-400">
          PT·그룹 수업 잔여 {{ LOW_REMAINING_THRESHOLD }}회 이하
        </p>

        <div
          v-if="lowRemainingAlerts.length === 0"
          class="mt-5 rounded-lg bg-slate-50 px-3 py-8 text-center text-sm text-slate-500"
        >
          잔여 횟수 부족 알림이 없습니다.
        </div>

        <ul v-else class="mt-4 divide-y divide-slate-100">
          <li v-for="alert in visibleLowRemaining" :key="alert.id">
            <RouterLink
              :to="`/members/${alert.memberId}`"
              class="flex items-center justify-between gap-3 rounded-lg px-2 py-3 transition-colors hover:bg-slate-50"
            >
              <div class="min-w-0">
                <p class="text-sm font-semibold text-slate-800">
                  {{ alert.memberName }}
                </p>

                <p class="mt-1 text-xs text-slate-500">
                  {{ alert.packageName }}
                </p>
              </div>

              <div class="flex shrink-0 items-center gap-2">
                <span class="text-xs font-semibold text-rose-600">
                  잔여 {{ alert.remainingSessions }}회
                </span>

                <ChevronRight :size="16" class="text-slate-400" aria-hidden="true" />
              </div>
            </RouterLink>
          </li>
        </ul>

        <button
          v-if="lowRemainingAlerts.length > INITIAL_VISIBLE_COUNT"
          type="button"
          class="mt-3 w-full rounded-lg border border-slate-200 px-3 py-2 text-xs font-medium text-slate-600 transition hover:bg-slate-50"
          @click="showAllLowRemaining = !showAllLowRemaining"
        >
          {{
            showAllLowRemaining
              ? '접기'
              : `나머지 ${lowRemainingAlerts.length - INITIAL_VISIBLE_COUNT}건 더 보기`
          }}
        </button>
      </div>

      <div class="rounded-xl border border-slate-200 p-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <CalendarClock :size="18" class="text-amber-500" aria-hidden="true" />

            <h3 class="text-sm font-semibold text-slate-900">기간 만료 예정</h3>
          </div>

          <span class="rounded-full bg-amber-50 px-2.5 py-1 text-xs font-semibold text-amber-700">
            {{ expiringAlerts.length }}건
          </span>
        </div>

        <p class="mt-2 text-xs text-slate-400">
          오늘부터 {{ EXPIRING_DAYS_THRESHOLD }}일 이내 만료
        </p>

        <div
          v-if="expiringAlerts.length === 0"
          class="mt-5 rounded-lg bg-slate-50 px-3 py-8 text-center text-sm text-slate-500"
        >
          기간 만료 예정 알림이 없습니다.
        </div>

        <ul v-else class="mt-4 divide-y divide-slate-100">
          <li v-for="alert in visibleExpiring" :key="alert.id">
            <RouterLink
              :to="`/members/${alert.memberId}`"
              class="flex items-center justify-between gap-3 rounded-lg px-2 py-3 transition-colors hover:bg-slate-50"
            >
              <div class="min-w-0">
                <p class="text-sm font-semibold text-slate-800">
                  {{ alert.memberName }}
                </p>

                <p class="mt-1 text-xs text-slate-500">
                  {{ alert.packageName }}
                </p>
              </div>

              <div class="flex shrink-0 items-center gap-2">
                <div class="text-right">
                  <p class="text-xs font-semibold text-amber-700">
                    {{ getExpiryLabel(alert.daysUntilExpiry) }}
                  </p>

                  <p class="mt-1 text-xs text-slate-400">{{ formatDate(alert.endsOn) }} 만료</p>
                </div>

                <ChevronRight :size="16" class="text-slate-400" aria-hidden="true" />
              </div>
            </RouterLink>
          </li>
        </ul>

        <button
          v-if="expiringAlerts.length > INITIAL_VISIBLE_COUNT"
          type="button"
          class="mt-3 w-full rounded-lg border border-slate-200 px-3 py-2 text-xs font-medium text-slate-600 transition hover:bg-slate-50"
          @click="showAllExpiring = !showAllExpiring"
        >
          {{
            showAllExpiring
              ? '접기'
              : `나머지 ${expiringAlerts.length - INITIAL_VISIBLE_COUNT}건 더 보기`
          }}
        </button>
      </div>
    </div>

    <p class="mt-4 text-xs leading-relaxed text-slate-400">
      보관 회원과 종료된 이용권은 제외합니다. 알림은 이용권 단위로 계산하며, 회원을 클릭하면 상세
      정보를 확인할 수 있습니다.
    </p>
  </section>
</template>
