<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowLeft } from 'lucide-vue-next'
import { useQuery } from '@tanstack/vue-query'

import { supabase } from '@/lib/supabase'
import { formatPhone } from '@/utils/phone'
import AddPtPackageDialog from '@/components/members/AddPtPackageDialog.vue'
import EditMemberDialog from '@/components/members/EditMemberDialog.vue'

// 회원 상세 화면 데이터 타입
interface MemberDetailData {
  id: string
  name: string
  phone: string
  totalSessions: number | null
  remainingSessions: number | null
}

// 현재 페이지의 라우트 정보
const route = useRoute()

// 회원 ID
const memberId = computed(() => String(route.params.id))

// Supabase 회원 UUID 형식 확인
const isValidMemberId = computed(() =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(memberId.value),
)

// PT 이용권 추가 모달 컴포넌트 참조
const packageDialog = ref<InstanceType<typeof AddPtPackageDialog> | null>(null)

// PT 이용권 추가 모달 열기
function openPackageDialog() {
  packageDialog.value?.open()
}

// 회원 정보 수정 모달 컴포넌트 참조
const editDialog = ref<InstanceType<typeof EditMemberDialog> | null>(null)

// 회원 정보 수정 모달 열기
function openEditDialog() {
  editDialog.value?.open()
}

// 로그인한 트레이너 ID
const trainerId = ref<string | null>(null)

// 로그인 정보 조회 상태
const isAuthLoading = ref(true)
const authError = ref('')

// TanStack Query로 회원 상세 정보 조회
const {
  data: dbMember,
  isPending: isMemberLoading,
  error: memberError,
} = useQuery({
  // 트레이너와 회원 ID별로 캐시 구분
  queryKey: computed(() => ['member', trainerId.value, memberId.value]),

  // Supabase에서 해당 회원 정보 조회
  queryFn: async () => {
    const { data, error } = await supabase
      .from('members')
      .select('id, name, phone')
      .eq('id', memberId.value)
      .maybeSingle()

    if (error) {
      throw error
    }

    return data
  },

  // 로그인 상태이고 올바른 UUID일 때만 조회
  enabled: computed(() => !!trainerId.value && isValidMemberId.value),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,
})

// TanStack Query로 회원별 PT 이용권 조회
const {
  data: dbPtPackages,
  isPending: isPackagesLoading,
  error: packagesError,
} = useQuery({
  // 회원별 이용권 캐시 구분
  queryKey: computed(() => ['member-packages', memberId.value, trainerId.value]),

  // Supabase에서 해당 회원의 PT 이용권 조회
  queryFn: async () => {
    const { data, error } = await supabase
      .from('member_packages')
      .select(
        'id, member_id, package_type, usage_type, total_sessions, remaining_sessions, starts_on, ends_on, status, created_at',
      )
      .eq('member_id', memberId.value)
      .eq('package_type', 'pt')
      .order('created_at', { ascending: false })

    if (error) {
      throw error
    }

    return data ?? []
  },

  // 로그인 상태이고 올바른 UUID일 때만 조회
  enabled: computed(() => !!trainerId.value && isValidMemberId.value),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,
})

// 회원 ID로 회원 정보 조회
const member = computed<MemberDetailData | undefined>(() => {
  // Supabase 회원 정보가 없는 경우
  if (!dbMember.value) {
    return undefined
  }

  // 취소되지 않은 PT 횟수제 이용권만 필터링
  const ptPackages = (dbPtPackages.value ?? []).filter(
    (pkg) => pkg.usage_type === 'count' && pkg.status !== 'cancelled',
  )

  // PT 이용권 정보가 없는 경우
  if (ptPackages.length === 0) {
    return {
      id: dbMember.value.id,
      name: dbMember.value.name,
      phone: dbMember.value.phone,
      totalSessions: null,
      remainingSessions: null,
    }
  }

  // 총 PT 횟수 합산
  const totalSessions = ptPackages.reduce((total, pkg) => total + (pkg.total_sessions ?? 0), 0)

  // 이용 중인 PT의 잔여 횟수 합산
  const remainingSessions = ptPackages.reduce(
    (total, pkg) => total + (pkg.status === 'active' ? (pkg.remaining_sessions ?? 0) : 0),
    0,
  )

  return {
    id: dbMember.value.id,
    name: dbMember.value.name,
    phone: dbMember.value.phone,
    totalSessions,
    remainingSessions,
  }
})

// 회원 정보 조회 상태
const isDetailLoading = computed(() => {
  // 올바르지 않은 UUID는 조회하지 않음
  if (!isValidMemberId.value) return false

  // 로그인 정보 확인 중
  if (isAuthLoading.value) return true

  // 로그인한 트레이너 정보가 없는 경우
  if (!trainerId.value) return false

  // 회원 정보 및 PT 이용권 조회 중
  return isMemberLoading.value || isPackagesLoading.value
})

// 회원 상세 조회 오류 메시지
const detailError = computed(() => {
  if (authError.value) return authError.value
  if (memberError.value) return '회원 정보를 불러오지 못했습니다.'
  if (packagesError.value) return 'PT 이용권을 불러오지 못했습니다.'

  return ''
})

// PT 이용권 정보 유무
const hasPtData = computed(() => {
  return (
    typeof member.value?.totalSessions === 'number' &&
    typeof member.value?.remainingSessions === 'number'
  )
})

// 사용한 PT 횟수
const usedSessions = computed(() => {
  if (!member.value || !hasPtData.value) return 0

  return Math.max(0, (member.value.totalSessions ?? 0) - (member.value.remainingSessions ?? 0))
})

// PT 사용 진행률 (%)
const usagePercent = computed(() => {
  const totalSessions = member.value?.totalSessions ?? 0

  if (!hasPtData.value || totalSessions <= 0) return 0

  const percent = (usedSessions.value / totalSessions) * 100

  return Math.min(100, Math.round(percent))
})

// PT 이용권 상태 표시 이름
function getPackageStatusLabel(status: string) {
  const statusLabels: Record<string, string> = {
    active: '이용 중',
    completed: '사용 완료',
    expired: '기간 만료',
    cancelled: '취소',
  }

  return statusLabels[status] ?? '상태 확인 필요'
}

// 날짜 표시 형식
function formatDate(date: string | null) {
  if (!date) return '미설정'

  return date.slice(0, 10).replaceAll('-', '.')
}

// 회원 상세 페이지 진입 시 로그인한 사용자 확인
onMounted(async () => {
  // 올바르지 않은 UUID는 조회하지 않음
  if (!isValidMemberId.value) {
    isAuthLoading.value = false
    return
  }

  try {
    const { data, error } = await supabase.auth.getSession()

    if (error) {
      throw error
    }

    trainerId.value = data.session?.user.id ?? null

    if (!trainerId.value) {
      authError.value = '로그인 정보를 확인하지 못했습니다.'
    }
  } catch (error) {
    console.error('로그인 정보 조회 오류:', error)
    authError.value = '로그인 정보를 확인하지 못했습니다.'
  } finally {
    isAuthLoading.value = false
  }
})
</script>

<template>
  <div>
    <!-- 회원 목록으로 돌아가기 -->
    <RouterLink
      to="/members"
      class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 hover:text-blue-600"
    >
      <ArrowLeft :size="18" aria-hidden="true" />
      회원 목록으로
    </RouterLink>

    <!-- 회원 정보 조회 중 -->
    <div
      v-if="isDetailLoading"
      class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center"
    >
      <p class="text-sm text-slate-500">회원 정보를 불러오는 중...</p>
    </div>

    <!-- 회원 정보 조회 오류 -->
    <div
      v-else-if="detailError"
      role="alert"
      class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center"
    >
      <p class="text-sm text-red-600">{{ detailError }}</p>
    </div>

    <!-- 회원 정보가 있는 경우 -->
    <template v-else-if="member">
      <!-- 페이지 제목 -->
      <h1 class="mt-6 text-2xl font-bold text-slate-900 sm:text-3xl">
        {{ member.name }}
      </h1>

      <!-- 페이지 설명 -->
      <p class="mt-2 text-slate-500">회원 정보와 PT 이용 현황을 확인합니다.</p>

      <!-- 회원 정보 -->
      <div class="mt-8 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
        <!-- 회원 정보 제목 및 수정 버튼 -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-lg font-semibold text-slate-900">기본 정보</h2>

          <!-- 회원 정보 수정 -->
          <button
            type="button"
            class="rounded-lg border border-slate-200 px-4 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-50"
            @click="openEditDialog"
          >
            정보 수정
          </button>
        </div>

        <div class="mt-5 space-y-4">
          <!-- 회원명 -->
          <div class="flex items-center justify-between gap-4">
            <span class="text-sm text-slate-500">회원명</span>
            <span class="text-sm font-medium text-slate-900">
              {{ member.name }}
            </span>
          </div>

          <!-- 연락처 -->
          <div class="flex items-center justify-between gap-4">
            <span class="text-sm text-slate-500">연락처</span>
            <span class="text-sm font-medium text-slate-900">
              {{ formatPhone(member.phone) }}
            </span>
          </div>
        </div>
      </div>

      <!-- PT 이용 현황 -->
      <div class="mt-6 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
        <!-- PT 이용 현황 제목 및 이용권 추가 버튼 -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-lg font-semibold text-slate-900">PT 이용 현황</h2>

          <!-- PT 이용권 추가 -->
          <button
            type="button"
            class="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700"
            @click="openPackageDialog"
          >
            + PT 이용권 추가
          </button>
        </div>

        <div class="mt-5 grid grid-cols-2 gap-4">
          <!-- 총 PT -->
          <div class="rounded-lg bg-slate-50 p-4">
            <p class="text-sm text-slate-500">총 PT</p>
            <p class="mt-2 text-2xl font-bold text-slate-900">
              {{ member.totalSessions === null ? '—' : `${member.totalSessions}회` }}
            </p>
          </div>

          <!-- 잔여 PT -->
          <div class="rounded-lg bg-blue-50 p-4">
            <p class="text-sm text-blue-600">잔여 PT</p>
            <p class="mt-2 text-2xl font-bold text-blue-600">
              {{ member.remainingSessions === null ? '—' : `${member.remainingSessions}회` }}
            </p>
          </div>
        </div>
      </div>

      <!-- PT 사용 진행률 -->
      <div v-if="hasPtData" class="mt-6">
        <div class="mb-3 flex items-center justify-between">
          <h3 class="text-sm font-medium text-slate-700">PT 사용 진행률</h3>
          <span class="text-sm font-semibold text-blue-600"> {{ usagePercent }}% </span>
        </div>

        <!-- 진행률 바 -->
        <div
          role="progressbar"
          aria-label="PT 사용 진행률"
          :aria-valuenow="usagePercent"
          aria-valuemin="0"
          aria-valuemax="100"
          class="h-3 overflow-hidden rounded-full bg-slate-200"
        >
          <div
            class="h-full rounded-full bg-blue-600 transition-all duration-300"
            :style="{ width: `${usagePercent}%` }"
          ></div>
        </div>

        <!-- 사용 및 잔여 PT 안내 -->
        <div class="mt-3 flex items-center justify-between gap-3 text-xs sm:text-sm">
          <div class="flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-blue-600"></span>
            <span class="text-slate-600">사용 {{ usedSessions }}회</span>
          </div>

          <div class="flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-slate-200"></span>
            <span class="text-slate-600">
              잔여
              {{ member.remainingSessions === null ? '—' : `${member.remainingSessions}회` }}
            </span>
          </div>
        </div>
      </div>

      <!-- PT 이용권 내역 -->
      <div class="mt-6 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
        <!-- 이용권 내역 제목 -->
        <h2 class="text-lg font-semibold text-slate-900">PT 이용권 내역</h2>

        <!-- 이용권 조회 중 -->
        <p v-if="isPackagesLoading" class="mt-5 text-sm text-slate-500">
          PT 이용권을 불러오는 중...
        </p>

        <!-- 이용권 조회 오류 -->
        <p v-else-if="packagesError" role="alert" class="mt-5 text-sm text-red-600">
          PT 이용권 목록을 불러오지 못했습니다.
        </p>

        <!-- 등록된 이용권 없음 -->
        <p v-else-if="!dbPtPackages?.length" class="mt-5 text-sm text-slate-500">
          등록된 PT 이용권이 없습니다.
        </p>

        <!-- PT 이용권 목록 -->
        <div v-else class="mt-5 space-y-3">
          <div
            v-for="pkg in dbPtPackages"
            :key="pkg.id"
            class="rounded-lg border border-slate-200 p-4"
          >
            <!-- 이용권명 및 상태 -->
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h3 class="font-semibold text-slate-900">PT {{ pkg.total_sessions }}회권</h3>

              <span
                class="rounded-full px-3 py-1 text-xs font-medium"
                :class="
                  pkg.status === 'active'
                    ? 'bg-green-50 text-green-700'
                    : 'bg-slate-100 text-slate-600'
                "
              >
                {{ getPackageStatusLabel(pkg.status) }}
              </span>
            </div>

            <!-- 이용권 상세 정보 -->
            <div class="mt-4 space-y-3">
              <!-- 구매일 -->
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm text-slate-500">등록일</span>
                <span class="text-sm text-slate-800">
                  {{ formatDate(pkg.created_at) }}
                </span>
              </div>

              <!-- 개시일 -->
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm text-slate-500">개시일</span>
                <span class="text-sm text-slate-800">
                  {{ formatDate(pkg.starts_on) }}
                </span>
              </div>

              <!-- 총 PT -->
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm text-slate-500">총 PT</span>
                <span class="text-sm font-medium text-slate-800"> {{ pkg.total_sessions }}회 </span>
              </div>

              <!-- 잔여 PT -->
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm text-slate-500">잔여 PT</span>
                <span class="text-sm font-semibold text-blue-600">
                  {{ pkg.remaining_sessions }}회
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- PT 이용권 추가 모달 -->
      <AddPtPackageDialog ref="packageDialog" :member-id="member.id" />

      <!-- 회원 정보 수정 모달 -->
      <EditMemberDialog
        ref="editDialog"
        :member-id="member.id"
        :name="member.name"
        :phone="member.phone"
      />
    </template>

    <!-- 회원 정보가 없는 경우 -->
    <div v-else class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center">
      <h1 class="text-xl font-semibold text-slate-900">회원을 찾을 수 없습니다.</h1>
      <p class="mt-2 text-sm text-slate-500">회원 정보가 없거나 잘못된 주소입니다.</p>
    </div>
  </div>
</template>
