<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowLeft } from 'lucide-vue-next'

import { useMemberStore } from '@/stores/members'
import { formatPhone } from '@/utils/phone'
import AddPtPackageDialog from '@/components/members/AddPtPackageDialog.vue'

// 회원 상세 화면 데이터 타입
interface MemberDetailData {
  id: string | number
  name: string
  phone: string
  totalSessions: number | null
  remainingSessions: number | null
}

// 현재 페이지의 라우트 정보
const route = useRoute()

// 회원 데이터 Store
const memberStore = useMemberStore()

// PT 이용권 추가 모달 컴포넌트 참조
const packageDialog = ref<InstanceType<typeof AddPtPackageDialog> | null>(null)

// PT 이용권 추가 모달 열기
function openPackageDialog() {
  packageDialog.value?.open()
}

// 회원 정보 조회 상태
const isDetailLoading = ref(true)

// 회원 ID로 회원 정보 조회
const member = computed<MemberDetailData | undefined>(() => {
  const memberId = String(route.params.id)

  // Supabase 회원 UUID로 조회
  const dbMember = memberStore.dbMembers.find((item) => item.id === memberId)

  if (dbMember) {
    return dbMember
  }

  // 기존 임시 회원 숫자 ID로 조회
  if (/^\d+$/.test(memberId)) {
    return memberStore.getMemberById(Number(memberId))
  }

  return undefined
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

// 회원 상세 페이지 진입 시 Supabase 데이터 조회
onMounted(async () => {
  const memberId = String(route.params.id)

  try {
    // UUID 회원은 Supabase에서 조회
    if (!/^\d+$/.test(memberId)) {
      await Promise.all([memberStore.fetchMembers(), memberStore.fetchMemberPackages(memberId)])
    }
  } finally {
    isDetailLoading.value = false
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

    <!-- 회원 정보가 있는 경우 -->
    <template v-if="member">
      <!-- 페이지 제목 -->
      <h1 class="mt-6 text-2xl font-bold text-slate-900 sm:text-3xl">
        {{ member.name }}
      </h1>

      <!-- 페이지 설명 -->
      <p class="mt-2 text-slate-500">회원 정보와 PT 이용 현황을 확인합니다.</p>

      <!-- 회원 정보 -->
      <div class="mt-8 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
        <h2 class="text-lg font-semibold text-slate-900">기본 정보</h2>

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
            v-if="typeof member.id === 'string'"
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
            <span class="text-slate-600"
              >잔여
              {{ member.remainingSessions === null ? '—' : `${member.remainingSessions}회` }}</span
            >
          </div>
        </div>
      </div>

      <!-- PT 이용권 내역 -->
      <div
        v-if="typeof member.id === 'string'"
        class="mt-6 rounded-xl border border-slate-200 bg-white p-5 sm:p-6"
      >
        <!-- 이용권 내역 제목 -->
        <h2 class="text-lg font-semibold text-slate-900">PT 이용권 내역</h2>

        <!-- 이용권 조회 중 -->
        <p v-if="memberStore.isPackagesLoading" class="mt-5 text-sm text-slate-500">
          PT 이용권을 불러오는 중...
        </p>

        <!-- 이용권 조회 오류 -->
        <p v-else-if="memberStore.packagesError" role="alert" class="mt-5 text-sm text-red-600">
          {{ memberStore.packagesError }}
        </p>

        <!-- 등록된 이용권 없음 -->
        <p v-else-if="memberStore.dbPtPackages.length === 0" class="mt-5 text-sm text-slate-500">
          등록된 PT 이용권이 없습니다.
        </p>

        <!-- PT 이용권 목록 -->
        <div v-else class="mt-5 space-y-3">
          <div
            v-for="pkg in memberStore.dbPtPackages"
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
      <AddPtPackageDialog
        v-if="typeof member.id === 'string'"
        ref="packageDialog"
        :member-id="member.id"
      />
    </template>

    <!-- 회원 정보 조회 중 -->
    <div
      v-else-if="isDetailLoading"
      class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center"
    >
      <p class="text-sm text-slate-500">회원 정보를 불러오는 중...</p>
    </div>

    <!-- 회원 정보가 없는 경우 -->
    <div v-else class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center">
      <h1 class="text-xl font-semibold text-slate-900">회원을 찾을 수 없습니다.</h1>
      <p class="mt-2 text-sm text-slate-500">회원 정보가 없거나 잘못된 주소입니다.</p>
    </div>
  </div>
</template>
