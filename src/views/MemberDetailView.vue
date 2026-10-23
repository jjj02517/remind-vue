<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowLeft } from 'lucide-vue-next'
import { useQuery } from '@tanstack/vue-query'

import { supabase } from '@/lib/supabase'
import { formatPhone } from '@/utils/phone'
import { getMemberStatus } from '@/utils/memberStatus'
import type { MemberStatus } from '@/utils/memberStatus'

import MemberPackageCard from '@/components/members/MemberPackageCard.vue'
import AddPackageDialog from '@/components/members/dialogs/AddPackageDialog.vue'
import EditMemberDialog from '@/components/members/dialogs/EditMemberDialog.vue'

// 회원 상세 화면 데이터 타입
interface MemberDetailData {
  id: string
  name: string
  phone: string
  status: MemberStatus
}

// 현재 페이지의 라우트 정보
const route = useRoute()

// 회원 ID
const memberId = computed(() => String(route.params.id))

// Supabase 회원 UUID 형식 확인
const isValidMemberId = computed(() =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(memberId.value),
)

// 공통 이용권 추가 모달 컴포넌트 참조
const packageDialog = ref<InstanceType<typeof AddPackageDialog> | null>(null)

// 공통 이용권 추가 모달 열기
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
      .select('id, name, phone, status')
      .eq('id', memberId.value)
      .maybeSingle()

    if (error) throw error

    return data
  },

  // 로그인 상태이고 올바른 UUID일 때만 조회
  enabled: computed(() => !!trainerId.value && isValidMemberId.value),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,
})

// TanStack Query로 회원별 전체 이용권 조회
const {
  data: dbPackages,
  isPending: isPackagesLoading,
  error: packagesError,
} = useQuery({
  // 회원별 이용권 캐시 구분
  queryKey: computed(() => ['member-packages', memberId.value, trainerId.value]),

  // Supabase에서 해당 회원의 모든 이용권과 일시정지 내역 조회
  queryFn: async () => {
    const { data, error } = await supabase
      .from('member_packages')
      .select(
        `
        id,
        member_id,
        package_type,
        usage_type,
        total_sessions,
        remaining_sessions,
        starts_on,
        ends_on,
        status,
        created_at,
        package_pauses (
          id,
          package_id,
          starts_on,
          ends_on,
          resumed_on,
          cancelled_at,
          reason,
          created_at
        )
      `,
      )
      .eq('member_id', memberId.value)
      .order('created_at', { ascending: false })

    if (error) throw error

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
  if (!dbMember.value) return undefined

  // 모든 이용권의 상태, 이용 기간, 일시정지 내역으로 활동 상태 계산
  const status = getMemberStatus(dbMember.value.status, dbPackages.value ?? [])

  return {
    id: dbMember.value.id,
    name: dbMember.value.name,
    phone: dbMember.value.phone,
    status,
  }
})

// 브라우저 현지 날짜를 YYYY-MM-DD로 반환
function getTodayString(): string {
  const now = new Date()
  const year = now.getFullYear()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const day = String(now.getDate()).padStart(2, '0')

  return `${year}-${month}-${day}`
}

// 현재 또는 이용 예정 이용권 여부 판단
// 완료·만료·취소된 이용권은 지난 내역으로 분리
function isCurrentPackage(
  pkg: {
    status: string
    usage_type: string
    remaining_sessions: number | null
    starts_on: string | null
    ends_on: string | null
  },
  today: string,
): boolean {
  if (pkg.status !== 'active') return false

  // 기간이 끝난 이용권은 DB 상태가 active여도 지난 이용권으로 분류
  if (pkg.ends_on && pkg.ends_on < today) return false

  // 횟수제는 잔여 횟수가 있어야 현재 이용권으로 분류
  if (pkg.usage_type === 'count') {
    return (pkg.remaining_sessions ?? 0) > 0
  }

  // 기간제는 이용 시작 전이라도 만료 전이면 현재·예정에 포함
  if (pkg.usage_type === 'period') {
    return !!pkg.starts_on && !!pkg.ends_on
  }

  return false
}

// 현재 이용권과 이용 예정 이용권
// 일시정지 중인 이용권도 이 목록에 남김
const currentPackages = computed(() => {
  const today = getTodayString()

  return (dbPackages.value ?? []).filter((pkg) => isCurrentPackage(pkg, today))
})

// 사용 완료·기간 만료·취소된 지난 이용권
const pastPackages = computed(() => {
  const today = getTodayString()

  return (dbPackages.value ?? []).filter((pkg) => !isCurrentPackage(pkg, today))
})

// 지난 이용권 펼침 상태
const showPastPackages = ref(false)

// 회원 정보 조회 상태
const isDetailLoading = computed(() => {
  // 올바르지 않은 UUID는 조회하지 않음
  if (!isValidMemberId.value) return false

  // 로그인 정보 확인 중
  if (isAuthLoading.value) return true

  // 로그인한 트레이너 정보가 없는 경우
  if (!trainerId.value) return false

  // 회원 정보 및 이용권 조회 중
  return isMemberLoading.value || isPackagesLoading.value
})

// 회원 상세 조회 오류 메시지
const detailError = computed(() => {
  if (authError.value) return authError.value
  if (memberError.value) return '회원 정보를 불러오지 못했습니다.'
  if (packagesError.value) return '이용권을 불러오지 못했습니다.'
  return ''
})

// 회원 상태 표시 이름
function getMemberStatusLabel(status: MemberStatus) {
  const statusLabels: Record<MemberStatus, string> = {
    active: '활동 중',
    inactive: '비활성',
    archived: '보관',
  }

  return statusLabels[status]
}

// 회원 상태별 배지 스타일
function getMemberStatusClass(status: MemberStatus) {
  const statusClasses: Record<MemberStatus, string> = {
    active: 'bg-green-50 text-green-700',
    inactive: 'bg-amber-50 text-amber-700',
    archived: 'bg-slate-100 text-slate-600',
  }

  return statusClasses[status]
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

    if (error) throw error

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
      <!-- 회원 기본 정보 -->
      <section class="mt-6 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <!-- 회원명 및 상태 -->
            <div class="flex flex-wrap items-center gap-3">
              <h1 class="text-2xl font-bold text-slate-900 sm:text-3xl">
                {{ member.name }}
              </h1>
              <span
                class="rounded-full px-3 py-1 text-xs font-medium"
                :class="getMemberStatusClass(member.status)"
              >
                {{ getMemberStatusLabel(member.status) }}
              </span>
            </div>

            <!-- 연락처 -->
            <p class="mt-2 text-sm text-slate-500">
              {{ formatPhone(member.phone) }}
            </p>
          </div>

          <!-- 회원 정보 수정 -->
          <button
            type="button"
            class="rounded-lg border border-slate-200 px-4 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-50"
            @click="openEditDialog"
          >
            정보 수정
          </button>
        </div>
      </section>

      <!-- 회원별 이용권 목록 -->
      <section class="mt-6">
        <!-- 이용권 내역 제목 및 이용권 추가 버튼 -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="text-lg font-semibold text-slate-900">보유 이용권</h2>
            <p class="mt-1 text-sm text-slate-500">
              PT, 그룹 수업, 월 회원권을 이용권별로 관리합니다.
            </p>
          </div>

          <!-- 공통 이용권 추가 버튼 -->
          <button
            type="button"
            class="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
            @click="openPackageDialog"
          >
            + 이용권 추가
          </button>
        </div>

        <!-- 등록된 이용권 없음 -->
        <div
          v-if="!dbPackages?.length"
          class="mt-5 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center"
        >
          <p class="text-sm text-slate-500">등록된 이용권이 없습니다.</p>
        </div>

        <template v-else>
          <!-- 현재 및 이용 예정 이용권 -->
          <div class="mt-6">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="text-base font-semibold text-slate-900">현재·예정 이용권</h3>
              <span class="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-medium text-blue-700">
                {{ currentPackages.length }}개
              </span>
            </div>

            <!-- 현재 및 이용 예정 이용권이 없는 경우 -->
            <div
              v-if="currentPackages.length === 0"
              class="mt-4 rounded-xl border border-slate-200 bg-white px-6 py-10 text-center"
            >
              <p class="text-sm text-slate-500">현재 이용 중이거나 예정된 이용권이 없습니다.</p>
            </div>

            <!-- 현재 및 이용 예정 이용권 카드 -->
            <div v-else class="mt-4 grid grid-cols-1 items-start gap-4 xl:grid-cols-2">
              <MemberPackageCard v-for="pkg in currentPackages" :key="pkg.id" :pkg="pkg" />
            </div>
          </div>

          <!-- 지난 이용권 목록: 필요할 때만 펼쳐보기 -->
          <div v-if="pastPackages.length > 0" class="mt-8 border-t border-slate-200 pt-6">
            <button
              type="button"
              class="flex w-full items-center justify-between gap-3 rounded-lg px-2 py-3 text-left transition hover:bg-slate-50 focus-visible:outline-2 focus-visible:outline-blue-600"
              :aria-expanded="showPastPackages"
              @click="showPastPackages = !showPastPackages"
            >
              <span class="flex flex-wrap items-center gap-2">
                <span class="text-base font-semibold text-slate-800">지난 이용권</span>
                <span
                  class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-600"
                >
                  {{ pastPackages.length }}개
                </span>
              </span>
              <span class="text-sm font-medium text-slate-500">
                {{ showPastPackages ? '접기 ▲' : '펼치기 ▼' }}
              </span>
            </button>

            <!-- 지난 이용권 카드 목록 -->
            <div
              v-if="showPastPackages"
              class="mt-4 grid grid-cols-1 items-start gap-4 xl:grid-cols-2"
            >
              <MemberPackageCard v-for="pkg in pastPackages" :key="pkg.id" :pkg="pkg" />
            </div>
          </div>
        </template>
      </section>

      <!-- 공통 이용권 추가 모달 -->
      <AddPackageDialog ref="packageDialog" :member-id="member.id" />

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
