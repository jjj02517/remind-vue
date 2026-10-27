<script setup lang="ts">
import { computed } from 'vue'
import { useInfiniteQuery } from '@tanstack/vue-query'
import { CalendarDays, ChevronDown, LoaderCircle, NotebookPen } from 'lucide-vue-next'

import {
  getPreviousWorkoutRecords,
  type PreviousWorkoutRecord,
  type PreviousWorkoutRecordsPage,
} from '@/api/sessions'

// 수업 상세 팝업에서 선택한 회원과 저장된 수업 일정
const props = defineProps<{
  attendanceId: string
  memberName: string
  sessionDate: string
  sessionStartTime: string
}>()

// 이전 수업 날짜와 시각은 한국 시간으로 표시
const dateFormatter = new Intl.DateTimeFormat('ko-KR', {
  timeZone: 'Asia/Seoul',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})

const timeFormatter = new Intl.DateTimeFormat('ko-KR', {
  timeZone: 'Asia/Seoul',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})

function formatDate(value: string): string {
  return dateFormatter.format(new Date(value))
}

function formatTime(value: string): string {
  return timeFormatter.format(new Date(value))
}

// 회원을 바꾸거나 수업 일정을 저장하면 해당 조건으로 다시 조회
const {
  data: recordPages,
  isPending,
  isFetching,
  error: queryError,
  hasNextPage,
  isFetchingNextPage,
  isFetchNextPageError,
  fetchNextPage,
  refetch,
} = useInfiniteQuery({
  queryKey: computed(
    () =>
      [
        'previous-workout-records',
        props.attendanceId,
        props.sessionDate,
        props.sessionStartTime,
      ] as const,
  ),
  enabled: computed(() => !!props.attendanceId),
  initialPageParam: 0,
  queryFn: ({ queryKey, pageParam, signal }): Promise<PreviousWorkoutRecordsPage> => {
    // 실행 중 변경될 수 있는 props 대신 이 요청의 조회 키 사용
    const attendanceId = queryKey[1]

    return getPreviousWorkoutRecords({
      attendanceId,
      offset: pageParam,
      signal,
    })
  },
  getNextPageParam: (lastPage) => lastPage.nextOffset,
  staleTime: 0,
  retry: 1,
})

// 조회한 페이지를 하나의 목록으로 연결
const records = computed<PreviousWorkoutRecord[]>(
  () => recordPages.value?.pages.flatMap((page) => page.records) ?? [],
)

async function showMoreRecords() {
  if (!hasNextPage.value || isFetching.value) return

  await fetchNextPage()
}
</script>

<template>
  <!-- 선택한 회원의 이전 운동 기록 -->
  <section class="min-w-0 rounded-xl border border-slate-200 bg-slate-50 p-4">
    <div class="flex items-center gap-2">
      <NotebookPen :size="18" class="shrink-0 text-blue-600" />
      <h3 class="text-sm font-semibold text-slate-900">이전 운동 기록</h3>
    </div>

    <p v-if="memberName" class="mt-2 text-sm font-semibold text-slate-700">{{ memberName }}님</p>

    <p class="mt-1 text-xs leading-5 text-slate-500">
      현재 수업보다 앞선 수업의 운동 기록을 전체 근무처 기준으로 표시합니다.
    </p>

    <!-- 회원 미선택 -->
    <p v-if="!attendanceId" class="mt-4 text-sm text-slate-500">
      이전 기록을 확인할 회원을 선택해 주세요.
    </p>

    <!-- 첫 조회 중 -->
    <div
      v-else-if="isPending"
      role="status"
      class="mt-4 flex items-center gap-2 py-4 text-sm text-slate-500"
    >
      <LoaderCircle :size="16" class="animate-spin" />
      이전 운동 기록을 불러오는 중...
    </div>

    <!-- 첫 조회 실패 -->
    <div v-else-if="queryError && records.length === 0" class="mt-4 rounded-lg bg-rose-50 p-3">
      <p role="alert" class="text-xs text-rose-700">이전 운동 기록을 불러오지 못했습니다.</p>

      <button
        type="button"
        :disabled="isFetching"
        class="mt-2 text-xs font-semibold text-rose-700 underline disabled:opacity-50"
        @click="refetch()"
      >
        {{ isFetching ? '다시 불러오는 중...' : '다시 시도' }}
      </button>
    </div>

    <!-- 조회된 운동 기록 없음 -->
    <p
      v-else-if="records.length === 0"
      class="mt-4 rounded-lg border border-dashed border-slate-200 bg-white p-4 text-sm text-slate-500"
    >
      이 수업보다 앞선 수업에 작성된 운동 기록이 없습니다.
    </p>

    <div v-else class="mt-4">
      <!-- 기록이 많아져도 입력창 옆에서 스크롤하며 확인 -->
      <div
        role="region"
        aria-label="이전 운동 기록 목록"
        tabindex="0"
        class="max-h-80 space-y-3 overflow-y-auto pr-1 lg:max-h-[55vh]"
      >
        <article
          v-for="record in records"
          :key="record.attendanceId"
          class="min-w-0 rounded-lg border border-slate-200 bg-white p-3"
        >
          <div class="flex flex-wrap items-center gap-2">
            <CalendarDays :size="14" class="shrink-0 text-slate-400" />

            <span class="text-xs font-semibold text-slate-800">
              {{ formatDate(record.startsAt) }}
            </span>

            <span class="text-xs text-slate-500">
              {{ formatTime(record.startsAt) }}
            </span>
          </div>

          <div class="mt-2 flex flex-wrap items-center gap-2">
            <span
              class="rounded-full px-2 py-0.5 text-xs font-semibold"
              :class="
                record.sessionType === 'pt'
                  ? 'bg-blue-50 text-blue-700'
                  : 'bg-violet-50 text-violet-700'
              "
            >
              {{ record.sessionType === 'pt' ? 'PT' : '그룹' }}
            </span>

            <span class="break-words text-xs text-slate-500">
              {{ record.companyName }}
            </span>
          </div>

          <p class="mt-3 whitespace-pre-wrap break-words text-sm leading-6 text-slate-700">
            {{ record.workoutNotes }}
          </p>
        </article>
      </div>

      <!-- 추가 조회 실패 시 기존 기록을 유지하고 재시도 가능 -->
      <p v-if="isFetchNextPageError" role="alert" class="mt-3 text-xs text-rose-700">
        이전 기록을 더 불러오지 못했습니다. 더 보기 버튼으로 다시 시도해 주세요.
      </p>

      <!-- 기존 기록이 있는 상태에서 새로고침에 실패한 경우 -->
      <div v-else-if="queryError" class="mt-3 rounded-lg bg-amber-50 p-3 text-xs text-amber-800">
        <p role="alert">최신 내용을 불러오지 못했습니다. 기존 기록을 표시합니다.</p>

        <button
          type="button"
          :disabled="isFetching"
          class="mt-2 font-semibold underline disabled:opacity-50"
          @click="refetch()"
        >
          다시 시도
        </button>
      </div>

      <!-- 실제로 다음 기록이 있을 때만 더 보기 표시 -->
      <button
        v-if="hasNextPage"
        type="button"
        :disabled="isFetching"
        class="mt-3 flex w-full items-center justify-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-xs font-semibold text-slate-600 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
        @click="showMoreRecords"
      >
        <LoaderCircle v-if="isFetchingNextPage" :size="14" class="animate-spin" />
        <ChevronDown v-else :size="14" />

        {{ isFetchingNextPage ? '불러오는 중...' : '이전 운동 기록 3개 더 보기' }}
      </button>

      <p class="mt-3 text-center text-xs text-slate-400">{{ records.length }}건</p>
    </div>
  </section>
</template>
