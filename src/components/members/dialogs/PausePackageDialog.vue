<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'

import { supabase } from '@/lib/supabase'
import { getPackagePauses } from '@/api/packagePauses'
import { getTodayString } from '@/utils/date'

// 부모 컴포넌트에서 이용권 ID 전달받기
const props = defineProps<{
  packageId: string
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 일시정지 등록 모달
const pauseDialog = ref<HTMLDialogElement | null>(null)

// 일시정지 모달 열림 상태
const isDialogOpen = ref(false)

// 일시정지 입력 데이터
const pauseForm = ref({
  startsOn: '',
  endsOn: '',
  reason: '',
})

// 일시정지 등록 오류
const pauseError = ref('')

// 날짜에 지정된 일수를 더함 (UTC 기준)
function addDays(date: string, days: number): string {
  const value = new Date(`${date}T00:00:00Z`)
  value.setUTCDate(value.getUTCDate() + days)

  return value.toISOString().slice(0, 10)
}

// 날짜 표시 형식
function formatDate(date: string | null): string {
  return date ? date.replaceAll('-', '.') : '미설정'
}

// 날짜 선택 시 사용할 오늘 날짜
const today = ref(getTodayString())

// 현재 이용권 정보 조회
const {
  data: packageInfo,
  isPending: isPackagePending,
  isFetching: isPackageFetching,
  isError: isPackageError,
} = useQuery({
  queryKey: computed(() => ['pause-package-info', props.packageId]),
  queryFn: async () => {
    const { data, error } = await supabase
      .from('member_packages')
      .select('id, package_type, usage_type, status, starts_on, ends_on')
      .eq('id', props.packageId)
      .maybeSingle()

    if (error) throw error
    if (!data) throw new Error('이용권 정보를 찾을 수 없습니다.')

    return data
  },
  enabled: computed(() => isDialogOpen.value && !!props.packageId),
  staleTime: 0,
  retry: false,
})

// 기존 일시정지 내역 조회 (내역 컴포넌트와 캐시 공유)
const {
  data: existingPauses,
  isPending: isPausesPending,
  isFetching: isPausesFetching,
  isError: isPausesError,
} = useQuery({
  queryKey: computed(() => ['package-pauses', props.packageId]),
  queryFn: () => getPackagePauses(props.packageId),
  enabled: computed(() => isDialogOpen.value && !!props.packageId),
  staleTime: 0,
  retry: false,
})

// 조회된 이용권에서 등록 가능한 날짜 범위 계산
const minimumStartsOn = computed(() => {
  const startsOn = packageInfo.value?.starts_on

  return startsOn && startsOn > today.value ? startsOn : today.value
})

const maximumEndsOn = computed(() => packageInfo.value?.ends_on ?? '')

// 이용권 정보를 가져오면 최초 등록 가능한 날짜 자동 설정
watch([isDialogOpen, packageInfo], ([isOpen, pkg]) => {
  if (!isOpen || !pkg || pauseForm.value.startsOn) return

  const firstDay = minimumStartsOn.value
  pauseForm.value.startsOn = firstDay
  pauseForm.value.endsOn = firstDay
})

// 일시정지 일수 계산
const pauseDays = computed(() => {
  const { startsOn, endsOn } = pauseForm.value

  if (!startsOn || !endsOn || endsOn < startsOn) {
    return 0
  }

  // UTC 기준으로 계산하여 일광절약시간제 영향을 방지
  const start = Date.parse(`${startsOn}T00:00:00Z`)
  const end = Date.parse(`${endsOn}T00:00:00Z`)

  return Math.round((end - start) / (1000 * 60 * 60 * 24)) + 1
})

// 월 회원권의 유효 상태 확인
const canPausePackage = computed(() => {
  const pkg = packageInfo.value

  return !!(
    pkg &&
    pkg.package_type === 'membership' &&
    pkg.usage_type === 'period' &&
    pkg.status === 'active' &&
    pkg.starts_on &&
    pkg.ends_on &&
    pkg.ends_on >= minimumStartsOn.value
  )
})

// 일시정지 날짜 오류 안내
const dateError = computed(() => {
  const { startsOn, endsOn } = pauseForm.value
  if (!startsOn || !endsOn) return ''

  if (startsOn < minimumStartsOn.value) {
    return `시작일은 ${formatDate(minimumStartsOn.value)} 이후여야 합니다.`
  }

  if (endsOn < startsOn) {
    return '종료일은 시작일보다 빠를 수 없습니다.'
  }

  if (maximumEndsOn.value && endsOn > maximumEndsOn.value) {
    return `일시정지 종료일은 현재 이용권 만료일(${formatDate(maximumEndsOn.value)}) 이내여야 합니다.`
  }

  return ''
})

// 취소되지 않은 일시정지와 새 기간이 겹치는지 확인
const overlappingPause = computed(() => {
  const { startsOn, endsOn } = pauseForm.value
  if (!startsOn || !endsOn || endsOn < startsOn) return null

  return (
    (existingPauses.value ?? []).find((pause) => {
      // 취소된 예약은 중복 검사에서 제외
      if (pause.cancelled_at) return false

      // 조기 복귀한 경우 복귀 전날까지만 실제 정지 기간
      const effectiveEndsOn = pause.resumed_on ? addDays(pause.resumed_on, -1) : pause.ends_on

      if (effectiveEndsOn < pause.starts_on) return false

      // 시작일과 종료일을 모두 포함해 중복 확인
      return pause.starts_on <= endsOn && effectiveEndsOn >= startsOn
    }) ?? null
  )
})

// 일시정지 등록 Mutation
const { mutateAsync: registerPause, isPending: isRegistering } = useMutation({
  // Supabase 일시정지 예약 RPC 호출
  mutationFn: async () => {
    const { data, error } = await supabase.rpc('pause_member_package', {
      p_package_id: props.packageId,
      p_starts_on: pauseForm.value.startsOn,
      p_ends_on: pauseForm.value.endsOn,
      p_reason: pauseForm.value.reason.trim() || null,
    })

    if (error) throw error

    return data
  },

  // 등록 성공 시 일시정지 및 이용권 데이터 갱신
  onSuccess: async () => {
    await Promise.all([
      // 해당 이용권 일시정지 내역 갱신
      queryClient.invalidateQueries({
        queryKey: ['package-pauses', props.packageId],
      }),

      // 회원 상세 페이지의 이용권 정보 갱신
      queryClient.invalidateQueries({
        queryKey: ['member-packages'],
      }),

      // 회원 목록 데이터 갱신
      queryClient.invalidateQueries({
        queryKey: ['members'],
      }),

      // 일시정지 연장으로 변경된 만료일 갱신
      queryClient.invalidateQueries({
        queryKey: ['pause-package-info', props.packageId],
      }),
    ])
  },
})

// 일시정지 등록 버튼 비활성화 조건
const isSubmitDisabled = computed(() => {
  if (isRegistering.value) return true
  if (!props.packageId || !canPausePackage.value) return true

  // 이용권 및 기존 일시정지 정보 조회가 끝나야 등록 가능
  if (
    isPackagePending.value ||
    isPackageFetching.value ||
    isPackageError.value ||
    isPausesPending.value ||
    isPausesFetching.value ||
    isPausesError.value
  ) {
    return true
  }

  // 시작일과 종료일 필수
  if (!pauseForm.value.startsOn || !pauseForm.value.endsOn) return true

  // 과거 날짜, 이용권 기간 이탈 및 역전된 기간 차단
  if (dateError.value) return true

  // 기존 일시정지와 기간이 겹치면 등록 차단
  if (overlappingPause.value) return true

  return pauseDays.value < 1
})

// 일시정지 시작일 변경
function handleStartDateChange() {
  const startsOn = pauseForm.value.startsOn

  if (!startsOn) {
    pauseForm.value.endsOn = ''
  } else if (!pauseForm.value.endsOn || pauseForm.value.endsOn < startsOn) {
    pauseForm.value.endsOn = startsOn
  }

  pauseError.value = ''
}

// 종료일 및 사유 변경 시 등록 오류 초기화
function handleFormChange() {
  pauseError.value = ''
}

// 일시정지 등록 모달 열기
function openPauseDialog() {
  today.value = getTodayString()

  pauseForm.value = {
    startsOn: '',
    endsOn: '',
    reason: '',
  }

  pauseError.value = ''
  isDialogOpen.value = true

  pauseDialog.value?.showModal()
}

// 일시정지 등록 모달 닫기
function closePauseDialog() {
  if (isRegistering.value) return

  pauseDialog.value?.close()
}

// 모달 닫힘 상태 정리
function handleDialogClose() {
  isDialogOpen.value = false
}

// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isRegistering.value) {
    event.preventDefault()
  }
}

// 일시정지 예약 등록
async function submitPause() {
  if (isSubmitDisabled.value) return

  pauseError.value = ''

  try {
    // Supabase RPC로 일시정지 등록
    await registerPause()

    // 등록 성공 시 모달 닫기
    pauseDialog.value?.close()
  } catch (error) {
    console.error('일시정지 등록 오류:', error)

    // Supabase에서 반환한 오류 메시지 표시
    pauseError.value = error instanceof Error ? error.message : '일시정지 등록에 실패했습니다.'
  }
}

// 부모 컴포넌트에서 모달 열기 함수 사용
defineExpose({
  open: openPauseDialog,
})
</script>

<template>
  <!-- 이용권 일시정지 등록 모달 -->
  <dialog
    ref="pauseDialog"
    aria-labelledby="pause-dialog-title"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @cancel="handleCancel"
    @close="handleDialogClose"
  >
    <!-- 모달 제목 -->
    <h2 id="pause-dialog-title" class="text-xl font-bold text-slate-900">이용권 일시정지</h2>

    <!-- 모달 설명 -->
    <p class="mt-2 text-sm text-slate-500">
      일시정지 기간을 선택해 주세요. 미래 날짜로 예약할 수도 있습니다.
    </p>

    <!-- 이용권 정보 조회 중 -->
    <p
      v-if="isPackagePending || isPackageFetching || isPausesPending || isPausesFetching"
      class="mt-4 text-sm text-slate-500"
    >
      이용권 및 기존 일시정지 내역을 확인하는 중...
    </p>

    <!-- 이용권 또는 기존 일시정지 내역 조회 실패 -->
    <p v-else-if="isPackageError || isPausesError" role="alert" class="mt-4 text-sm text-red-600">
      이용권 정보를 확인하지 못했습니다. 팝업을 닫고 다시 열어 주세요.
    </p>

    <!-- 일시정지할 수 없는 이용권 -->
    <p v-else-if="!canPausePackage" role="alert" class="mt-4 text-sm text-red-600">
      현재 이용권은 일시정지를 등록할 수 없습니다.
    </p>

    <!-- 이용권 사용 기간 안내 -->
    <div v-else class="mt-4 rounded-lg bg-slate-50 p-4 text-sm text-slate-700">
      <p>
        이용 기간:
        <span class="font-medium">
          {{ formatDate(packageInfo?.starts_on ?? null) }} ~
          {{ formatDate(packageInfo?.ends_on ?? null) }}
        </span>
      </p>
      <p class="mt-1 text-xs text-slate-500">
        일시정지는 오늘 이후, 현재 이용권 만료일 이내에서 선택할 수 있습니다.
      </p>
    </div>

    <!-- 일시정지 등록 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitPause">
      <!-- 일시정지 시작일 -->
      <div>
        <label for="pause-start-date" class="mb-2 block text-sm font-medium text-slate-700">
          일시정지 시작일
        </label>

        <input
          id="pause-start-date"
          v-model="pauseForm.startsOn"
          type="date"
          required
          :min="minimumStartsOn"
          :max="maximumEndsOn || undefined"
          :disabled="isRegistering || !canPausePackage || isPackageFetching || isPausesFetching"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          @change="handleStartDateChange"
        />
      </div>

      <!-- 일시정지 종료일 -->
      <div>
        <label for="pause-end-date" class="mb-2 block text-sm font-medium text-slate-700">
          일시정지 종료일
        </label>

        <input
          id="pause-end-date"
          v-model="pauseForm.endsOn"
          type="date"
          required
          :min="pauseForm.startsOn || minimumStartsOn"
          :max="maximumEndsOn || undefined"
          :disabled="
            isRegistering ||
            !canPausePackage ||
            isPackageFetching ||
            isPausesFetching ||
            !pauseForm.startsOn
          "
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          @change="handleFormChange"
        />
      </div>

      <!-- 일시정지 사유 -->
      <div>
        <label for="pause-reason" class="mb-2 block text-sm font-medium text-slate-700">
          일시정지 사유 (선택)
        </label>

        <textarea
          id="pause-reason"
          v-model="pauseForm.reason"
          rows="3"
          maxlength="500"
          placeholder="예: 여행, 개인 사정, 부상 등"
          :disabled="isRegistering || !canPausePackage"
          class="w-full resize-none rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          @input="handleFormChange"
        />
      </div>

      <!-- 입력한 일시정지 기간 오류 -->
      <p v-if="dateError" role="alert" class="text-sm text-red-600">
        {{ dateError }}
      </p>

      <!-- 기존 일시정지 내역과 기간 중복 -->
      <div
        v-if="!isPausesFetching && overlappingPause"
        role="alert"
        class="rounded-lg border border-red-200 bg-red-50 p-4"
      >
        <p class="text-sm font-medium text-red-700">기존 일시정지 기간과 겹칩니다.</p>
        <p class="mt-2 text-xs text-red-600">
          기존 기간: {{ formatDate(overlappingPause.starts_on) }} ~
          {{ formatDate(overlappingPause.ends_on) }}
        </p>
        <p class="mt-1 text-xs text-red-600">겹치지 않는 날짜를 선택해 주세요.</p>
      </div>

      <!-- 일시정지 기간 안내 -->
      <div v-if="pauseDays > 0 && !dateError" class="rounded-lg bg-blue-50 p-4">
        <div class="flex items-center justify-between">
          <span class="text-sm text-blue-700">일시정지 기간</span>
          <span class="text-lg font-bold text-blue-700">{{ pauseDays }}일</span>
        </div>

        <p class="mt-2 text-xs text-blue-600">
          만료일이 있는 이용권은 일시정지 일수만큼 자동 연장됩니다.
        </p>
      </div>

      <!-- 일시정지 등록 오류 -->
      <p v-if="pauseError" role="alert" class="text-sm text-red-600">
        {{ pauseError }}
      </p>

      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <button
          type="button"
          :disabled="isRegistering"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closePauseDialog"
        >
          취소
        </button>

        <!-- 일시정지 예약 등록 -->
        <button
          type="submit"
          :disabled="isSubmitDisabled"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-500"
        >
          {{ isRegistering ? '등록 중...' : '일시정지 등록' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
