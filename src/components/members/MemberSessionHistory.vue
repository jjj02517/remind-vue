<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/vue-query'
import { CalendarDays, ChevronDown, LoaderCircle, Pencil, Save, X } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'
import { saveSessionWorkoutRecord, type AttendanceStatus, type SessionType } from '@/api/sessions'

// ============================================
// Props
// ============================================

const props = defineProps<{
  memberId: string
}>()

// ============================================
// 회원 수업 이력 타입
// ============================================

interface MemberSessionRecord {
  attendanceId: string
  sessionId: string
  startsAt: string
  endsAt: string
  sessionType: SessionType
  attendanceStatus: AttendanceStatus
  companyId: string
  companyName: string
  sessionNotes: string | null
  workoutNotes: string | null
}

// ============================================
// 날짜 및 출석 상태 표시
// ============================================

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

const attendanceLabels: Record<AttendanceStatus, string> = {
  scheduled: '예정',
  attended: '출석',
  no_show: '노쇼',
  same_day_cancelled: '당일 취소',
  cancelled: '일반 취소',
}

function getStatusClass(status: AttendanceStatus): string {
  switch (status) {
    case 'attended':
      return 'bg-emerald-50 text-emerald-700'
    case 'no_show':
      return 'bg-rose-50 text-rose-700'
    case 'same_day_cancelled':
      return 'bg-amber-50 text-amber-700'
    case 'cancelled':
      return 'bg-slate-100 text-slate-600'
    default:
      return 'bg-blue-50 text-blue-700'
  }
}

// ============================================
// 회원별 수업 이력 조회 (서버 페이지네이션)
// ============================================

const queryClient = useQueryClient()
const PAGE_SIZE = 5

// 근무처별 수업 이력 필터 (전체 근무처가 기본값)
const selectedCompanyId = ref('all')

// ============================================
// 1. 전체 이력을 기준으로 근무처와 수업 건수 조회
// ============================================

// 현재 화면에 불러온 첫 5건만으로 근무처 목록을 만들지 않음.
// 과거에 다른 근무처의 수업이 있어도 필터에 정확히 표시됨.
const {
  data: historyCompanies,
  error: companiesError,
  isPending: isCompaniesLoading,
} = useQuery({
  queryKey: computed(() => ['member-session-history-companies', props.memberId]),
  enabled: computed(() => !!props.memberId),
  queryFn: async () => {
    const { data, error } = await supabase.rpc('get_member_session_history_companies', {
      p_member_id: props.memberId,
    })
    if (error) throw error

    return (data ?? []).map(
      (company: { company_id: string; company_name: string; session_count: string }) => ({
        id: company.company_id,
        name: company.company_name,
        count: Number(company.session_count),
      }),
    )
  },
  refetchOnMount: 'always',
  staleTime: 1000 * 60,
})

const companyOptions = computed(() => historyCompanies.value ?? [])

// 현재 선택한 근무처의 전체 수업 개수 (아직 불러오지 않은 수업 포함)
const filteredTotalCount = computed(() => {
  if (selectedCompanyId.value === 'all') {
    return companyOptions.value.reduce(
      (sum: number, company: { id: string; name: string; count: number }) => sum + company.count,
      0,
    )
  }
  return (
    companyOptions.value.find(
      (company: { id: string; name: string; count: number }) =>
        company.id === selectedCompanyId.value,
    )?.count ?? 0
  )
})

// ============================================
// 2. 실제 수업 날짜 기준으로 5건씩 조회
// ============================================

const {
  data: sessionPages,
  isPending: isLoading,
  error: queryError,
  hasNextPage,
  isFetchingNextPage,
  isFetchNextPageError,
  fetchNextPage,
} = useInfiniteQuery({
  // 회원이나 근무처가 달라지면 다른 페이지 목록 사용
  queryKey: computed(() => ['member-session-history', props.memberId, selectedCompanyId.value]),
  enabled: computed(() => !!props.memberId),
  initialPageParam: 0,
  queryFn: async ({ pageParam }): Promise<MemberSessionRecord[]> => {
    const { data, error } = await supabase.rpc('get_member_session_history_page', {
      p_member_id: props.memberId,
      p_company_id: selectedCompanyId.value === 'all' ? null : selectedCompanyId.value,
      p_page_size: PAGE_SIZE,
      p_offset: pageParam,
    })

    if (error) throw error

    return (data ?? []).map(
      (record: {
        attendance_id: string
        session_id: string
        starts_at: string
        ends_at: string
        session_type: SessionType
        attendance_status: AttendanceStatus
        company_id: string
        company_name: string
        session_notes: string | null
        workout_notes: string | null
      }) => ({
        attendanceId: record.attendance_id,
        sessionId: record.session_id,
        startsAt: record.starts_at,
        endsAt: record.ends_at,
        sessionType: record.session_type as SessionType,
        attendanceStatus: record.attendance_status as AttendanceStatus,
        companyId: record.company_id,
        companyName: record.company_name,
        sessionNotes: record.session_notes,
        workoutNotes: record.workout_notes,
      }),
    )
  },
  // 5건을 모두 가져왔을 때 다음 페이지가 있을 수 있음.
  // 마지막 페이지가 5건으로 끝나도 전체 건수와 비교해 버튼을 숨김.
  getNextPageParam: (lastPage, allPages) =>
    lastPage.length === PAGE_SIZE ? allPages.length * PAGE_SIZE : undefined,
  refetchOnMount: 'always',
  staleTime: 1000 * 60,
})

// 이미 가져온 페이지를 화면에 이어 붙임 (조회 순서는 DB가 보장)
const sessionRecords = computed<MemberSessionRecord[]>(() => sessionPages.value?.pages.flat() ?? [])

// ============================================
// 3. 이전 수업 더 보기
// ============================================

const hasMoreRecords = computed(() => {
  if (!hasNextPage.value) return false
  // 근무처 건수 조회가 실패했더라도 페이지별 조회는 계속 가능
  if (isCompaniesLoading.value || companiesError.value) return true
  return sessionRecords.value.length < filteredTotalCount.value
})

async function showMoreRecords() {
  if (!hasMoreRecords.value || isFetchingNextPage.value || isSaving.value) return
  await fetchNextPage()
}

// 근무처를 바꾸면 새 쿼리가 자동으로 첫 5건부터 조회됨
watch(selectedCompanyId, () => {
  editingAttendanceId.value = null
  editWorkoutNotes.value = ''
  saveError.value = ''
  saveSuccessId.value = null
})

// 다른 회원 상세 화면으로 이동하면 근무처 필터 초기화
watch(
  () => props.memberId,
  () => {
    selectedCompanyId.value = 'all'
    editingAttendanceId.value = null
    editWorkoutNotes.value = ''
    saveError.value = ''
    saveSuccessId.value = null
  },
)

// ============================================
// 회원별 운동 기록 수정
// ============================================

const editingAttendanceId = ref<string | null>(null)
const editWorkoutNotes = ref('')
const isSaving = ref(false)
const saveError = ref('')
const saveSuccessId = ref<string | null>(null)

function startEditing(record: MemberSessionRecord) {
  if (isSaving.value) return

  editingAttendanceId.value = record.attendanceId
  editWorkoutNotes.value = record.workoutNotes ?? ''
  saveError.value = ''
  saveSuccessId.value = null
}

function cancelEditing() {
  if (isSaving.value) return

  editingAttendanceId.value = null
  editWorkoutNotes.value = ''
  saveError.value = ''
}

async function saveWorkoutNotes(record: MemberSessionRecord) {
  if (isSaving.value) return

  if (editWorkoutNotes.value.length > 2000) {
    saveError.value = '운동 기록은 2000자 이하로 입력해 주세요.'
    return
  }

  isSaving.value = true
  saveError.value = ''
  saveSuccessId.value = null

  try {
    // ============================================
    // 1. 운동 기록만 DB에 저장
    // ============================================

    await saveSessionWorkoutRecord({
      attendanceId: record.attendanceId,
      workoutNotes: editWorkoutNotes.value,
    })
  } catch (error) {
    console.error('회원 운동 기록 수정 오류:', error)
    saveError.value = error instanceof Error ? error.message : '운동 기록 수정에 실패했습니다.'
    isSaving.value = false
    return
  }

  // ============================================
  // 2. 회원 상세 및 수업 상세 데이터 갱신
  // ============================================

  editingAttendanceId.value = null
  saveSuccessId.value = record.attendanceId

  try {
    await Promise.all([
      queryClient.invalidateQueries({
        queryKey: ['member-session-history', props.memberId],
      }),
      queryClient.invalidateQueries({
        queryKey: ['session-detail'],
      }),
    ])
  } catch (error) {
    console.error('운동 기록 캐시 갱신 오류:', error)
  } finally {
    isSaving.value = false
  }
}
</script>

<template>
  <!-- ============================================ -->
  <!-- 회원별 수업 이력 -->
  <!-- ============================================ -->
  <section class="mt-8 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
    <!-- 수업 이력 제목 -->
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-lg font-semibold text-slate-900">수업 이력</h2>
        <p class="mt-1 text-sm text-slate-500">
          지난 수업과 회원별 운동 기록을 확인할 수 있습니다.
        </p>
      </div>
      <span
        v-if="!isCompaniesLoading && !companiesError"
        class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-600"
      >
        총 {{ filteredTotalCount }}개
      </span>
    </div>

    <!-- ============================================ -->
    <!-- 근무처별 수업 이력 필터 -->
    <!-- ============================================ -->
    <div v-if="companyOptions.length > 1" class="mt-4">
      <label
        for="member-session-company-filter"
        class="mb-2 block text-xs font-medium text-slate-600"
      >
        근무처별 수업 보기
      </label>
      <select
        id="member-session-company-filter"
        v-model="selectedCompanyId"
        :disabled="isSaving"
        class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-700 outline-none focus:border-blue-500 disabled:opacity-50 sm:max-w-xs"
      >
        <option value="all">전체 근무처</option>
        <option v-for="company in companyOptions" :key="company.id" :value="company.id">
          {{ company.name }}
        </option>
      </select>
    </div>

    <!-- 근무처 목록 조회 오류 (수업 이력 자체는 계속 조회 가능) -->
    <p v-if="companiesError" role="alert" class="mt-3 text-xs text-amber-700">
      근무처 필터 정보를 불러오지 못했습니다. 수업 이력은 계속 조회할 수 있습니다.
    </p>

    <!-- ============================================ -->
    <!-- 조회 상태 -->
    <!-- ============================================ -->
    <div
      v-if="isLoading"
      class="mt-5 flex items-center justify-center gap-2 py-8 text-sm text-slate-500"
    >
      <LoaderCircle :size="18" class="animate-spin" />
      수업 이력을 불러오는 중...
    </div>

    <p
      v-else-if="queryError && sessionRecords.length === 0"
      role="alert"
      class="mt-5 rounded-lg bg-rose-50 p-4 text-sm text-rose-700"
    >
      수업 이력을 불러오지 못했습니다.
    </p>

    <p
      v-else-if="sessionRecords.length === 0"
      class="mt-5 rounded-lg bg-slate-50 p-6 text-center text-sm text-slate-500"
    >
      {{
        selectedCompanyId === 'all'
          ? '아직 등록된 수업 내역이 없습니다.'
          : '선택한 근무처의 수업 이력이 없습니다.'
      }}
    </p>

    <!-- ============================================ -->
    <!-- 수업 이력 카드 목록 -->
    <!-- ============================================ -->
    <div v-else class="mt-5 space-y-3">
      <article
        v-for="record in sessionRecords"
        :key="record.attendanceId"
        class="rounded-xl border border-slate-200 p-4"
      >
        <!-- 수업 날짜 및 출석 상태 -->
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <CalendarDays :size="16" class="text-slate-400" />
            <span class="text-sm font-semibold text-slate-900">
              {{ formatDate(record.startsAt) }}
            </span>
            <span class="text-xs text-slate-500">
              {{ formatTime(record.startsAt) }} ~ {{ formatTime(record.endsAt) }}
            </span>
          </div>
          <span
            class="rounded-full px-2.5 py-1 text-xs font-medium"
            :class="getStatusClass(record.attendanceStatus)"
          >
            {{ attendanceLabels[record.attendanceStatus] }}
          </span>
        </div>

        <!-- 수업 종류 및 근무처 -->
        <div class="mt-3 flex flex-wrap items-center gap-2">
          <span
            class="rounded-full px-2.5 py-1 text-xs font-semibold"
            :class="
              record.sessionType === 'pt'
                ? 'bg-blue-50 text-blue-700'
                : 'bg-violet-50 text-violet-700'
            "
          >
            {{ record.sessionType === 'pt' ? 'PT' : '그룹' }}
          </span>
          <span class="text-xs text-slate-500">{{ record.companyName }}</span>
        </div>

        <!-- ============================================ -->
        <!-- 수업 공통 계획 -->
        <!-- ============================================ -->
        <div v-if="record.sessionNotes" class="mt-4">
          <p class="mb-1 text-xs font-semibold text-slate-500">수업 계획</p>
          <p class="whitespace-pre-wrap text-sm text-slate-700">{{ record.sessionNotes }}</p>
        </div>

        <!-- ============================================ -->
        <!-- 회원별 실제 운동 기록 -->
        <!-- ============================================ -->
        <div class="mt-4 rounded-lg bg-slate-50 p-3">
          <div class="flex items-center justify-between gap-2">
            <p class="text-xs font-semibold text-slate-600">실제 운동 기록</p>
            <button
              v-if="editingAttendanceId !== record.attendanceId"
              type="button"
              :disabled="isSaving"
              class="inline-flex items-center gap-1 text-xs font-semibold text-blue-600 hover:text-blue-700 disabled:opacity-50"
              @click="startEditing(record)"
            >
              <Pencil :size="13" />
              {{ record.workoutNotes ? '수정' : '기록 작성' }}
            </button>
          </div>

          <!-- 기존 운동 기록 -->
          <p
            v-if="editingAttendanceId !== record.attendanceId"
            class="mt-2 whitespace-pre-wrap text-sm text-slate-700"
          >
            {{ record.workoutNotes || '작성된 운동 기록이 없습니다.' }}
          </p>

          <!-- ============================================ -->
          <!-- 운동 기록 수정 폼 -->
          <!-- ============================================ -->
          <div v-else class="mt-3">
            <textarea
              v-model="editWorkoutNotes"
              rows="4"
              maxlength="2000"
              :disabled="isSaving"
              placeholder="수업에서 진행한 운동을 입력하세요."
              class="w-full resize-y rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-800 outline-none focus:border-blue-500 disabled:opacity-50"
            />
            <p class="mt-1 text-right text-xs text-slate-400">
              {{ editWorkoutNotes.length }} / 2000
            </p>
            <p v-if="saveError" role="alert" class="mt-2 text-xs text-rose-600">
              {{ saveError }}
            </p>
            <div class="mt-3 flex justify-end gap-2">
              <button
                type="button"
                :disabled="isSaving"
                class="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 disabled:opacity-50"
                @click="cancelEditing"
              >
                <X :size="14" /> 취소
              </button>
              <button
                type="button"
                :disabled="isSaving"
                class="inline-flex items-center gap-1 rounded-lg bg-blue-600 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-700 disabled:opacity-50"
                @click="saveWorkoutNotes(record)"
              >
                <LoaderCircle v-if="isSaving" :size="14" class="animate-spin" />
                <Save v-else :size="14" />
                {{ isSaving ? '저장 중...' : '저장' }}
              </button>
            </div>
          </div>

          <!-- 저장 성공 안내 -->
          <p
            v-if="
              saveSuccessId === record.attendanceId && editingAttendanceId !== record.attendanceId
            "
            class="mt-2 text-xs text-emerald-600"
          >
            운동 기록이 저장되었습니다.
          </p>
        </div>
      </article>

      <!-- ============================================ -->
      <!-- 이전 수업 더 보기 -->
      <!-- ============================================ -->
      <p v-if="isFetchNextPageError" role="alert" class="text-center text-xs text-rose-600">
        이전 수업을 불러오지 못했습니다. 다시 시도해 주세요.
      </p>

      <button
        v-if="hasMoreRecords"
        type="button"
        :disabled="isFetchingNextPage || isSaving"
        class="flex w-full items-center justify-center gap-2 rounded-lg border border-slate-200 py-3 text-sm font-medium text-slate-600 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
        @click="showMoreRecords"
      >
        <LoaderCircle v-if="isFetchingNextPage" :size="16" class="animate-spin" />
        <ChevronDown v-else :size="16" />
        {{ isFetchingNextPage ? '불러오는 중...' : '이전 수업 5개 더 보기' }}
      </button>

      <p v-if="!isCompaniesLoading && !companiesError" class="text-center text-xs text-slate-400">
        {{ sessionRecords.length }} / {{ filteredTotalCount }}개 불러옴
      </p>
    </div>
  </section>
</template>
