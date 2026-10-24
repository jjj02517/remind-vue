<script setup lang="ts">
import { computed, ref } from 'vue'
import PackagePauseHistory from '@/components/members/PackagePauseHistory.vue'
import { useQuery } from '@tanstack/vue-query'
import { getPackagePauses } from '@/api/packagePauses'
import { getTodayString } from '@/utils/date'
import { isPackagePaused } from '@/utils/packagePauseStatus'
import PausePackageDialog from '@/components/members/dialogs/PausePackageDialog.vue'
// 이용권 데이터 타입
interface MemberPackage {
  id: string
  member_id: string
  package_type: string
  usage_type: string
  total_sessions: number | null
  remaining_sessions: number | null
  starts_on: string | null
  ends_on: string | null
  status: string
  created_at: string
}

// 부모 컴포넌트에서 이용권 정보 전달받기
const props = defineProps<{
  pkg: MemberPackage
  // 해당 이용권이 등록된 근무처 이름 (부모에서 전달)
  companyName?: string | null
}>()
// 이용권 일시정지 모달 컴포넌트 참조
const pauseDialog = ref<InstanceType<typeof PausePackageDialog> | null>(null)
// 일시정지 등록 가능한 이용권인지 확인
const canPausePackage = computed(() => {
  const pkg = props.pkg
  // 우선 기간제 월 회원권만 일시정지 지원
  if (pkg.package_type !== 'membership') return false
  if (pkg.usage_type !== 'period') return false
  // 정상 등록된 활성 이용권만 허용
  if (pkg.status !== 'active') return false
  // 이용 기간 정보 필수
  if (!pkg.starts_on || !pkg.ends_on) return false
  // 이미 만료된 회원권은 일시정지 불가
  return pkg.ends_on >= getTodayString()
})

// 일시정지 모달 열기
function openPauseDialog() {
  pauseDialog.value?.open()
}

// 이용권별 일시정지 내역 조회
const {
  data: packagePauses,
  isPending: isPausesLoading,
  isError: isPausesError,
} = useQuery({
  // PackagePauseHistory와 동일한 캐시 키 사용
  queryKey: computed(() => ['package-pauses', props.pkg.id]),
  // 해당 이용권의 일시정지 내역 조회
  queryFn: () => getPackagePauses(props.pkg.id),
  // 이용권 ID가 있는 경우에만 조회
  enabled: computed(() => !!props.pkg.id),
})

// 현재 이용권이 일시정지 중인지 확인
const isPaused = computed(() => {
  return isPackagePaused(packagePauses.value ?? [], getTodayString())
})

// 날짜 표시 형식
function formatDate(date: string | null): string {
  if (!date) return '미설정'
  return date.slice(0, 10).replaceAll('-', '.')
}

// 이용권 종류별 이름 표시
const packageName = computed(() => {
  const pkg = props.pkg
  // PT 횟수제 이용권
  if (pkg.package_type === 'pt' && pkg.usage_type === 'count') {
    return `PT ${pkg.total_sessions ?? 0}회권`
  }
  // 그룹 횟수제 이용권
  if (pkg.package_type === 'group' && pkg.usage_type === 'count') {
    return `그룹 수업 ${pkg.total_sessions ?? 0}회권`
  }
  // 월 회원권
  if (pkg.package_type === 'membership') {
    return '월 회원권'
  }
  // 그룹 기간제 이용권
  if (pkg.package_type === 'group' && pkg.usage_type === 'period') {
    return '그룹 수업 기간권'
  }
  return '기타 이용권'
})

// 이용권 상태 표시 이름
const packageStatusLabel = computed(() => {
  const pkg = props.pkg
  // DB에 저장된 종료 상태 우선 적용
  const statusLabels: Record<string, string> = {
    completed: '사용 완료',
    expired: '기간 만료',
    cancelled: '취소',
  }
  if (pkg.status !== 'active') {
    return statusLabels[pkg.status] ?? '상태 확인 필요'
  }
  const today = getTodayString()
  // 이용권 기간이 이미 종료된 경우
  if (pkg.ends_on && today > pkg.ends_on) {
    return '기간 만료'
  }
  // 횟수제 이용권의 잔여 횟수가 없는 경우
  if (pkg.usage_type === 'count' && (pkg.remaining_sessions ?? 0) <= 0) {
    return '사용 완료'
  }
  // 아직 이용 시작일이 되지 않은 경우
  if (pkg.starts_on && today < pkg.starts_on) {
    return '이용 예정'
  }
  // 일시정지 데이터 조회 중 또는 오류
  if (isPausesLoading.value) {
    return '상태 확인 중'
  }
  if (isPausesError.value) {
    return '상태 확인 필요'
  }
  // 현재 일시정지 기간에 해당하는 경우
  if (isPaused.value) {
    return '일시정지 중'
  }
  return '이용 중'
})

// 이용권 상태별 배지 스타일
const packageStatusClass = computed(() => {
  switch (packageStatusLabel.value) {
    case '이용 중':
      return 'bg-green-50 text-green-700'
    case '이용 예정':
      return 'bg-blue-50 text-blue-700'
    case '일시정지 중':
      return 'bg-amber-50 text-amber-700'
    case '사용 완료':
    case '기간 만료':
      return 'bg-slate-100 text-slate-600'
    case '취소':
      return 'bg-red-50 text-red-600'
    case '상태 확인 중':
    case '상태 확인 필요':
      return 'bg-slate-100 text-slate-500'
    default:
      return 'bg-slate-100 text-slate-600'
  }
})

// 이용권 종류별 아이콘 색상
const packageTypeClass = computed(() => {
  switch (props.pkg.package_type) {
    case 'pt':
      return 'bg-blue-50 text-blue-700'
    case 'group':
      return 'bg-violet-50 text-violet-700'
    case 'membership':
      return 'bg-emerald-50 text-emerald-700'
    default:
      return 'bg-slate-100 text-slate-600'
  }
})

// 횟수제 이용권 여부
const isCountPackage = computed(() => props.pkg.usage_type === 'count')
// 이용권 총 횟수
const totalSessions = computed(() => props.pkg.total_sessions ?? 0)
// 이용권 잔여 횟수
const remainingSessions = computed(() => props.pkg.remaining_sessions ?? 0)
// 사용한 횟수
const usedSessions = computed(() => {
  return Math.max(0, totalSessions.value - remainingSessions.value)
})

// 횟수제 이용권 사용 진행률
const usagePercent = computed(() => {
  if (totalSessions.value <= 0) return 0
  const percent = (usedSessions.value / totalSessions.value) * 100
  return Math.min(100, Math.round(percent))
})

// 횟수제 이용권 표시 이름
const sessionLabel = computed(() => {
  return props.pkg.package_type === 'pt' ? 'PT' : '그룹 수업'
})
</script>

<template>
  <!-- 회원 이용권 카드 -->
  <div class="rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
    <!-- 이용권명 및 상태 -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex flex-wrap items-center gap-2">
        <!-- 이용권 종류 -->
        <span class="rounded-lg px-2.5 py-1 text-xs font-semibold" :class="packageTypeClass">
          {{
            pkg.package_type === 'pt'
              ? 'PT'
              : pkg.package_type === 'group'
                ? '그룹'
                : pkg.package_type === 'membership'
                  ? '회원권'
                  : '기타'
          }}
        </span>
        <!-- 이용권 이름 -->
        <h3 class="font-semibold text-slate-900">
          {{ packageName }}
        </h3>
      </div>
      <!-- 이용권 상태 -->
      <span class="rounded-full px-3 py-1 text-xs font-medium" :class="packageStatusClass">
        {{ packageStatusLabel }}
      </span>
    </div>
    <!-- 이용권 소속 근무처 -->
    <div v-if="companyName" class="mt-3 flex items-center gap-2 text-sm text-slate-600">
      <span class="font-medium text-slate-500">근무처</span>
      <span class="font-medium text-slate-800">{{ companyName }}</span>
    </div>

    <!-- 횟수제 이용권 정보 -->
    <div v-if="isCountPackage" class="mt-5 space-y-4">
      <!-- 총 횟수 및 잔여 횟수 -->
      <div class="grid grid-cols-2 gap-3">
        <!-- 총 횟수 -->
        <div class="rounded-lg bg-slate-50 p-4">
          <p class="text-xs text-slate-500">총 {{ sessionLabel }}</p>
          <p class="mt-2 text-xl font-bold text-slate-900">{{ totalSessions }}회</p>
        </div>
        <!-- 잔여 횟수 -->
        <div class="rounded-lg bg-blue-50 p-4">
          <p class="text-xs text-blue-600">잔여 {{ sessionLabel }}</p>
          <p class="mt-2 text-xl font-bold text-blue-600">{{ remainingSessions }}회</p>
        </div>
      </div>
      <!-- 이용권 사용 진행률 -->
      <div>
        <div class="mb-2 flex items-center justify-between">
          <span class="text-sm font-medium text-slate-700"> 사용 진행률 </span>
          <span class="text-sm font-semibold text-blue-600"> {{ usagePercent }}% </span>
        </div>
        <!-- 진행률 바 -->
        <div
          role="progressbar"
          :aria-label="`${packageName} 사용 진행률`"
          :aria-valuenow="usagePercent"
          aria-valuemin="0"
          aria-valuemax="100"
          class="h-2.5 overflow-hidden rounded-full bg-slate-200"
        >
          <div
            class="h-full rounded-full bg-blue-600 transition-all duration-300"
            :style="{ width: `${usagePercent}%` }"
          ></div>
        </div>
        <!-- 사용 및 잔여 횟수 안내 -->
        <div class="mt-2 flex justify-between text-xs text-slate-500">
          <span>사용 {{ usedSessions }}회</span>
          <span>잔여 {{ remainingSessions }}회</span>
        </div>
      </div>
    </div>
    <!-- 기간제 이용권 정보 -->
    <div v-else-if="pkg.usage_type === 'period'" class="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-2">
      <!-- 이용 시작일 -->
      <div class="rounded-lg bg-slate-50 p-4">
        <p class="text-xs text-slate-500">이용 시작일</p>
        <p class="mt-2 text-sm font-semibold text-slate-900">
          {{ formatDate(pkg.starts_on) }}
        </p>
      </div>
      <!-- 이용 만료일 -->
      <div class="rounded-lg bg-slate-50 p-4">
        <p class="text-xs text-slate-500">이용 만료일</p>
        <p class="mt-2 text-sm font-semibold text-slate-900">
          {{ formatDate(pkg.ends_on) }}
        </p>
      </div>
    </div>
    <!-- 이용권 기본 정보 -->
    <div class="mt-5 space-y-3 border-t border-slate-100 pt-4">
      <!-- 등록일 -->
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm text-slate-500"> 등록일 </span>
        <span class="text-sm text-slate-800">
          {{ formatDate(pkg.created_at) }}
        </span>
      </div>
      <!-- 횟수제 이용권 개시일 -->
      <div v-if="isCountPackage && pkg.starts_on" class="flex items-center justify-between gap-3">
        <span class="text-sm text-slate-500"> 개시일 </span>
        <span class="text-sm text-slate-800">
          {{ formatDate(pkg.starts_on) }}
        </span>
      </div>
      <!-- 횟수제 이용권 만료일 -->
      <div v-if="isCountPackage && pkg.ends_on" class="flex items-center justify-between gap-3">
        <span class="text-sm text-slate-500"> 만료일 </span>
        <span class="text-sm text-slate-800">
          {{ formatDate(pkg.ends_on) }}
        </span>
      </div>
    </div>
    <!-- 이용권 일시정지 등록 -->
    <div v-if="canPausePackage" class="mt-5 flex justify-end">
      <button
        type="button"
        class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-2.5 text-sm font-medium text-amber-700 transition hover:bg-amber-100 focus-visible:outline-2 focus-visible:outline-amber-500"
        @click="openPauseDialog"
      >
        일시정지 등록
      </button>
    </div>
    <!-- 이용권별 일시정지 내역 -->
    <PackagePauseHistory :package-id="pkg.id" />
    <!-- 이용권 일시정지 등록 모달 -->
    <PausePackageDialog v-if="canPausePackage" ref="pauseDialog" :package-id="pkg.id" />
  </div>
</template>
