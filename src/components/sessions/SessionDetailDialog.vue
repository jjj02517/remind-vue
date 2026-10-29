<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useQuery, useQueryClient } from '@tanstack/vue-query'
import { supabase } from '@/lib/supabase'
import {
  X,
  CalendarDays,
  CalendarClock,
  Clock3,
  MapPin,
  UsersRound,
  LoaderCircle,
  AlertCircle,
  Ban,
  Trash2,
  Pencil,
  ChevronDown,
  StickyNote,
} from 'lucide-vue-next'

import {
  getSessionDetail,
  cancelSession,
  deleteSession,
  updateSessionDetails,
  type AttendanceStatus,
  type SessionDetail,
} from '@/api/sessions'
import SessionWorkoutRecordEditor from '@/components/sessions/SessionWorkoutRecordEditor.vue'
import PreviousWorkoutRecords from '@/components/sessions/PreviousWorkoutRecords.vue'
import { blockDemoWrite } from '@/utils/demoGuard'

// ============================================
// Props / Emits
// ============================================

const props = defineProps<{
  sessionId: string
}>()

const emit = defineEmits<{
  close: []
  updated: []
}>()

// ============================================
// TanStack Query 캐시 관리
// ============================================

const queryClient = useQueryClient()

// 수업 일정 수정 / 취소 / 삭제 후 관련 데이터 갱신
// 회원별 운동 기록 및 출석 저장 후 캐시 갱신은 자식 컴포넌트에서도 처리
async function refreshRelatedQueries() {
  await Promise.all([
    queryClient.invalidateQueries({ queryKey: ['members'] }),
    queryClient.invalidateQueries({ queryKey: ['member-packages'] }),
    queryClient.invalidateQueries({ queryKey: ['session-member-options'] }),
    queryClient.invalidateQueries({ queryKey: ['sessions'] }),
    queryClient.invalidateQueries({ queryKey: ['session-detail'] }),
    queryClient.invalidateQueries({ queryKey: ['member-session-history'] }),
    queryClient.invalidateQueries({ queryKey: ['member-session-history-companies'] }),
    queryClient.invalidateQueries({ queryKey: ['previous-workout-records'] }),
  ])
}

// ============================================
// 출석 상태 및 이용권 차감 판단
// ============================================

const deductedStatuses = new Set<AttendanceStatus>(['attended', 'no_show', 'same_day_cancelled'])

// ============================================
// 수업 상세 데이터
// ============================================

const detail = ref<SessionDetail | null>(null)
const isLoading = ref(false)
const isRefreshingAttendance = ref(false)
const isUpdating = ref(false)
const isCancelling = ref(false)
const isDeleting = ref(false)
const isEditing = ref(false)
const errorMessage = ref('')

// ============================================
// 이전 운동 기록 참고
// ============================================

// 그룹 수업에서는 이전 기록을 확인할 참여 회원을 선택
const selectedHistoryAttendanceId = ref('')
const isPreviousRecordsOpen = ref(false)

const selectedHistoryAttendance = computed(() =>
  detail.value?.attendees.find((attendee) => attendee.id === selectedHistoryAttendanceId.value),
)

// ============================================
// 수업 참여 회원별 메모 조회
// ============================================

// 현재 수업의 출석 기록 ID
const attendanceIds = computed(() => (detail.value?.attendees ?? []).map((attendee) => attendee.id))

// 회원별 메모를 출석 기록 ID 기준으로 조회
const {
  data: memberMemos,
  isFetching: isMemberMemosLoading,
  error: memberMemosError,
} = useQuery({
  queryKey: computed(() => ['session-member-memos', props.sessionId, ...attendanceIds.value]),

  queryFn: async (): Promise<Record<string, string>> => {
    const ids = attendanceIds.value

    if (!ids.length) return {}

    // 출석 기록과 회원 ID 연결
    const { data: attendances, error: attendanceError } = await supabase
      .from('session_attendances')
      .select('id, member_id')
      .in('id', ids)

    if (attendanceError) throw attendanceError

    const memberIds = [
      ...new Set(
        (attendances ?? [])
          .map((attendance) => attendance.member_id)
          .filter((id): id is string => !!id),
      ),
    ]

    if (!memberIds.length) return {}

    // 회원 기본 정보에 저장된 메모 조회
    const { data: members, error: memberError } = await supabase
      .from('members')
      .select('id, memo')
      .in('id', memberIds)

    if (memberError) throw memberError

    const memoByMemberId = new Map((members ?? []).map((member) => [member.id, member.memo ?? '']))

    // 출석 기록 ID별 회원 메모 구성
    return Object.fromEntries(
      (attendances ?? []).map((attendance) => [
        attendance.id,
        memoByMemberId.get(attendance.member_id) ?? '',
      ]),
    )
  },

  // 수업 참여 회원이 있을 때만 조회
  enabled: computed(() => attendanceIds.value.length > 0),

  // 다시 열었을 때 최신 회원 메모 확인
  staleTime: 0,
})

// ============================================
// 수업 수정 폼
// ============================================

const editDate = ref('')
const editStartTime = ref('')
const editNotes = ref('')

// 정시에 시작하는 1시간 수업만 허용
const hourOptions = Array.from({ length: 24 }, (_, hour) => {
  const start = `${String(hour).padStart(2, '0')}:00`
  const end = `${String((hour + 1) % 24).padStart(2, '0')}:00`
  return { value: start, label: `${start} ~ ${end}` }
})

function resetEditForm() {
  if (!detail.value) return

  editDate.value = detail.value.date
  editStartTime.value = detail.value.startTime
  editNotes.value = detail.value.notes ?? ''
}

// 수업 자체를 변경하는 중에는 다른 관리 버튼 중복 실행 방지
const isBusy = computed(
  () =>
    isLoading.value ||
    isRefreshingAttendance.value ||
    isUpdating.value ||
    isCancelling.value ||
    isDeleting.value,
)

// ============================================
// 수업 수정 / 취소 / 삭제 가능 여부
// ============================================

const hasDeductedAttendance = computed(() =>
  (detail.value?.attendees ?? []).some((attendee) => deductedStatuses.has(attendee.status)),
)

// 예정 상태이고 이용권 차감이 없는 수업만 일정 수정 가능
const canEditSession = computed(
  () =>
    detail.value?.status === 'scheduled' &&
    detail.value.attendees.length > 0 &&
    !hasDeductedAttendance.value,
)

const canCancelEntireSession = computed(() => canEditSession.value)
const canDeleteSession = computed(() => canEditSession.value)

const hasEditChanges = computed(() => {
  if (!detail.value) return false

  return (
    editDate.value !== detail.value.date ||
    editStartTime.value !== detail.value.startTime ||
    editNotes.value.trim() !== (detail.value.notes ?? '').trim()
  )
})

// ============================================
// 수업 상세 조회
// ============================================

async function loadDetail(): Promise<boolean> {
  isLoading.value = true
  errorMessage.value = ''

  try {
    detail.value = await getSessionDetail(props.sessionId)

    // 최초 조회는 첫 회원을 선택하고, 새로고침 시에는 기존 선택 유지
    if (
      !detail.value.attendees.some((attendee) => attendee.id === selectedHistoryAttendanceId.value)
    ) {
      selectedHistoryAttendanceId.value = detail.value.attendees[0]?.id ?? ''
    }

    return true
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '수업 정보를 불러오지 못했습니다.'
    return false
  } finally {
    isLoading.value = false
  }
}

// ============================================
// 회원별 운동 기록 / 출석 저장 완료
// ============================================

async function handleWorkoutRecordUpdated(nextStatus: AttendanceStatus | null) {
  // 자식 컴포넌트가 저장 후 관련 캐시를 이미 갱신한 상태
  // 부모는 최신 출석 상태를 확인하여 팝업 자동 닫기 여부 판단
  isRefreshingAttendance.value = true

  try {
    const loaded = await loadDetail()

    try {
      // 다른 화면에서도 수정된 운동 기록을 다시 조회할 수 있도록 갱신
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['member-session-history'] }),
        queryClient.invalidateQueries({ queryKey: ['previous-workout-records'] }),
      ])
    } catch (error) {
      console.error('운동 기록 저장 후 참고 기록 갱신 오류:', error)
    }

    emit('updated')

    // 운동 기록만 저장했다면 팝업을 그대로 유지
    if (!loaded || !detail.value || nextStatus === null) return

    // PT는 출석 상태를 변경하면 자동 닫기
    const isPt = detail.value.type === 'pt'

    // 그룹은 모든 회원의 출석 상태가 확정되면 닫기
    const isGroupCompleted =
      detail.value.type === 'group' &&
      detail.value.attendees.length > 0 &&
      detail.value.attendees.every((person) => person.status !== 'scheduled')

    if (isPt || isGroupCompleted) {
      emit('close')
    }
  } finally {
    isRefreshingAttendance.value = false
  }
}

// ============================================
// 수업 수정 화면
// ============================================

function openEditForm() {
  if (isBusy.value || !canEditSession.value) return

  resetEditForm()
  errorMessage.value = ''
  isEditing.value = true
}

function closeEditForm() {
  if (isBusy.value) return

  isEditing.value = false
  errorMessage.value = ''
  resetEditForm()
}

// ============================================
// 수업 날짜·시간·공통 계획 수정
// ============================================

async function handleUpdateSession() {
  if (isBusy.value || !canEditSession.value || !hasEditChanges.value) return

  if (await blockDemoWrite()) return

  if (!editDate.value || !editStartTime.value) {
    errorMessage.value = '수업 날짜와 시작 시간을 선택해 주세요.'
    return
  }

  isUpdating.value = true
  errorMessage.value = ''

  try {
    // DB에서 시간 중복, 이용권 유효기간, 수업 수정 가능 여부 검증
    await updateSessionDetails({
      sessionId: props.sessionId,
      date: editDate.value,
      startTime: editStartTime.value,
      notes: editNotes.value,
    })
  } catch (error) {
    console.error('수업 수정 오류:', error)
    errorMessage.value = error instanceof Error ? error.message : '수업을 수정하지 못했습니다.'
    isUpdating.value = false
    return
  }

  try {
    await refreshRelatedQueries()
  } catch (error) {
    // DB 저장 성공과 캐시 갱신 오류를 구분
    console.error('수업 수정 후 캐시 갱신 오류:', error)
  }

  isUpdating.value = false
  emit('updated')
  emit('close')
}

// ============================================
// 수업 전체 취소
// ============================================

async function handleCancelSession() {
  if (isBusy.value || isEditing.value || !canCancelEntireSession.value || !detail.value) {
    return
  }

  if (await blockDemoWrite()) return

  const session = detail.value
  const confirmed = window.confirm(
    `${session.date} ${session.startTime} 수업을 취소할까요?\n\n` +
      `근무처: ${session.companyName}\n` +
      `참여 회원: ${session.attendees.length}명\n\n` +
      '참여 회원의 예약도 함께 취소됩니다.\n' +
      '수업 취소 기록은 달력에 남습니다.',
  )

  if (!confirmed) return

  isCancelling.value = true
  errorMessage.value = ''

  try {
    await cancelSession(props.sessionId)
  } catch (error) {
    console.error('수업 전체 취소 오류:', error)
    errorMessage.value = error instanceof Error ? error.message : '수업 전체 취소에 실패했습니다.'
    isCancelling.value = false
    return
  }

  try {
    await refreshRelatedQueries()
  } catch (error) {
    console.error('수업 취소 후 캐시 갱신 오류:', error)
  }

  isCancelling.value = false
  emit('updated')
  emit('close')
}

// ============================================
// 수업 소프트 삭제
// ============================================

async function handleDeleteSession() {
  if (isBusy.value || isEditing.value || !canDeleteSession.value || !detail.value) {
    return
  }
  if (await blockDemoWrite()) return

  const session = detail.value
  const confirmed = window.confirm(
    '잘못 등록한 수업을 삭제할까요?\n\n' +
      `날짜: ${session.date}\n` +
      `시간: ${session.startTime}~${session.endTime}\n` +
      `근무처: ${session.companyName}\n` +
      `참여 회원: ${session.attendees.length}명\n\n` +
      '삭제하면 일반 달력에서 사라집니다.\n' +
      '회원·이용권·변경 이력은 보존됩니다.\n' +
      '현재 화면에서는 삭제를 되돌릴 수 없습니다.',
  )

  if (!confirmed) return

  isDeleting.value = true
  errorMessage.value = ''

  try {
    await deleteSession(props.sessionId)
  } catch (error) {
    console.error('수업 삭제 오류:', error)
    errorMessage.value = error instanceof Error ? error.message : '수업 삭제에 실패했습니다.'
    isDeleting.value = false
    return
  }

  try {
    await refreshRelatedQueries()
  } catch (error) {
    console.error('수업 삭제 후 캐시 갱신 오류:', error)
  }

  isDeleting.value = false
  emit('updated')
  emit('close')
}

// ============================================
// 모달 닫기 및 수업 변경 감지
// ============================================

function closeDialog() {
  if (isBusy.value) return
  emit('close')
}

watch(
  () => props.sessionId,
  () => {
    detail.value = null
    isEditing.value = false
    selectedHistoryAttendanceId.value = ''
    isPreviousRecordsOpen.value = false
    void loadDetail()
  },
)

onMounted(() => {
  void loadDetail()
})
</script>

<template>
  <Teleport to="body">
    <!-- 수업 상세 모달 배경 -->
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      @click.self="closeDialog"
    >
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="session-detail-title"
        class="flex max-h-[90vh] w-full max-w-xl flex-col overflow-hidden rounded-2xl bg-white shadow-xl lg:max-w-5xl"
      >
        <!-- 모달 헤더 -->
        <header
          class="flex shrink-0 items-center justify-between border-b border-slate-200 px-5 py-4"
        >
          <div>
            <h2 id="session-detail-title" class="text-lg font-semibold text-slate-900">
              수업 상세
            </h2>
            <p class="mt-1 text-xs text-slate-500">
              수업 계획과 회원별 실제 운동 기록·출석을 관리하세요.
            </p>
          </div>

          <button
            type="button"
            aria-label="닫기"
            :disabled="isBusy"
            class="rounded-lg p-2 text-slate-500 transition hover:bg-slate-100 disabled:opacity-50"
            @click="closeDialog"
          >
            <X :size="20" />
          </button>
        </header>

        <!-- 모달 본문 -->
        <div class="min-h-0 flex-1 overflow-y-auto p-5">
          <!-- 수업 정보 조회 중 -->
          <div
            v-if="isLoading && !detail"
            class="flex min-h-48 items-center justify-center gap-2 text-sm text-slate-500"
          >
            <LoaderCircle :size="20" class="animate-spin" />
            수업 정보를 불러오는 중...
          </div>

          <div
            v-else-if="detail"
            class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.85fr)]"
          >
            <!-- 현재 수업의 계획, 운동 기록 및 출석 관리 -->
            <div class="min-w-0">
              <!-- 수업 기본 정보 -->
              <div class="rounded-xl border border-slate-200 bg-slate-50 p-4">
                <div class="mb-4 flex items-center gap-2">
                  <!-- PT / 그룹 구분 -->
                  <span
                    class="rounded-full px-3 py-1 text-xs font-semibold"
                    :class="
                      detail.type === 'pt'
                        ? 'bg-blue-100 text-blue-700'
                        : 'bg-violet-100 text-violet-700'
                    "
                  >
                    {{ detail.type === 'pt' ? 'PT' : '그룹' }}
                  </span>

                  <!-- 수업 상태 -->
                  <span class="text-sm font-medium text-slate-700">
                    {{
                      detail.status === 'scheduled'
                        ? '예정'
                        : detail.status === 'completed'
                          ? '완료'
                          : '취소'
                    }}
                  </span>
                </div>

                <!-- 수업 일정 -->
                <div class="space-y-3 text-sm text-slate-700">
                  <div class="flex items-center gap-3">
                    <CalendarDays :size="17" class="text-slate-400" />
                    <span>{{ detail.date }}</span>
                  </div>

                  <div class="flex items-center gap-3">
                    <Clock3 :size="17" class="text-slate-400" />
                    <span>{{ detail.startTime }} ~ {{ detail.endTime }}</span>
                  </div>

                  <div class="flex items-center gap-3">
                    <MapPin :size="17" class="text-slate-400" />
                    <span>{{ detail.companyName }}</span>
                  </div>

                  <div class="flex items-center gap-3">
                    <UsersRound :size="17" class="text-slate-400" />
                    <span>참여 회원 {{ detail.attendees.length }}명</span>
                  </div>
                </div>

                <!-- 수업 공통 계획 -->
                <div v-if="detail.notes" class="mt-4 border-t border-slate-200 pt-3">
                  <p class="mb-1 text-xs font-medium text-slate-500">수업 공통 계획</p>
                  <p class="whitespace-pre-wrap text-sm text-slate-700">
                    {{ detail.notes }}
                  </p>
                </div>

                <!-- 수업 수정 버튼 -->
                <div
                  v-if="detail.status === 'scheduled'"
                  class="mt-4 border-t border-slate-200 pt-4"
                >
                  <button
                    v-if="!isEditing"
                    type="button"
                    :disabled="isBusy || !canEditSession"
                    class="inline-flex items-center gap-2 rounded-lg border border-blue-200 bg-white px-3 py-2 text-xs font-semibold text-blue-700 transition hover:bg-blue-50 disabled:cursor-not-allowed disabled:opacity-40"
                    @click="openEditForm"
                  >
                    <Pencil :size="15" />
                    수업 수정
                  </button>

                  <p v-if="!canEditSession" class="mt-2 text-xs text-rose-600">
                    출석 처리가 진행된 수업은 수정할 수 없습니다.
                  </p>
                </div>
              </div>

              <!-- 수업 일정 및 공통 계획 수정 폼 -->
              <div
                v-if="isEditing"
                class="mt-4 rounded-xl border border-blue-200 bg-blue-50/40 p-4"
              >
                <div class="mb-4 flex items-center gap-2">
                  <CalendarClock :size="19" class="text-blue-600" />
                  <h3 class="text-sm font-semibold text-slate-900">수업 일정·계획 수정</h3>
                </div>

                <form class="space-y-4" @submit.prevent="handleUpdateSession">
                  <!-- 수업 날짜 -->
                  <div>
                    <label
                      for="edit-session-date"
                      class="mb-1.5 block text-xs font-semibold text-slate-700"
                    >
                      수업 날짜
                    </label>
                    <input
                      id="edit-session-date"
                      v-model="editDate"
                      type="date"
                      required
                      :disabled="isBusy"
                      class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-800 outline-none focus:border-blue-500 disabled:opacity-50"
                    />
                  </div>

                  <!-- 시작 시간 -->
                  <div>
                    <label
                      for="edit-session-time"
                      class="mb-1.5 block text-xs font-semibold text-slate-700"
                    >
                      시작 시간
                    </label>
                    <select
                      id="edit-session-time"
                      v-model="editStartTime"
                      required
                      :disabled="isBusy"
                      class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-800 outline-none focus:border-blue-500 disabled:opacity-50"
                    >
                      <option
                        v-for="option in hourOptions"
                        :key="option.value"
                        :value="option.value"
                      >
                        {{ option.label }}
                      </option>
                    </select>
                    <p class="mt-1.5 text-xs text-slate-500">
                      수업은 정시에 시작하며 1시간 진행됩니다.
                    </p>
                  </div>

                  <!-- 수업 공통 계획 -->
                  <div>
                    <label
                      for="edit-session-notes"
                      class="mb-1.5 block text-xs font-semibold text-slate-700"
                    >
                      수업 공통 계획
                    </label>
                    <textarea
                      id="edit-session-notes"
                      v-model="editNotes"
                      rows="3"
                      maxlength="1000"
                      :disabled="isBusy"
                      placeholder="예: 하체 운동 예정, 준비물, 수업 목표"
                      class="w-full resize-y rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-800 outline-none focus:border-blue-500 disabled:opacity-50"
                    />
                    <p class="mt-1 text-right text-xs text-slate-400">
                      {{ editNotes.length }} / 1000
                    </p>
                  </div>

                  <!-- 수업 수정 버튼 -->
                  <div class="grid grid-cols-2 gap-2">
                    <button
                      type="button"
                      :disabled="isBusy"
                      class="rounded-lg border border-slate-200 bg-white px-4 py-2.5 text-sm font-semibold text-slate-600 hover:bg-slate-100 disabled:opacity-50"
                      @click="closeEditForm"
                    >
                      수정 취소
                    </button>

                    <button
                      type="submit"
                      :disabled="isBusy || !hasEditChanges"
                      class="flex items-center justify-center gap-2 rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <LoaderCircle v-if="isUpdating" :size="16" class="animate-spin" />
                      {{ isUpdating ? '저장 중...' : '수정 저장' }}
                    </button>
                  </div>
                </form>
              </div>

              <!-- 회원별 운동 기록 + 출석 관리 -->
              <div class="mt-6">
                <div class="mb-3 flex items-center justify-between gap-2">
                  <h3 class="text-base font-semibold text-slate-900">
                    회원별 운동 기록 · 출석 관리
                  </h3>
                  <span class="text-xs text-slate-500">회원별 개별 저장</span>
                </div>

                <div
                  v-if="detail.attendees.length === 0"
                  class="rounded-xl border border-dashed border-slate-200 p-6 text-center text-sm text-slate-500"
                >
                  등록된 참여 회원이 없습니다.
                </div>

                <!-- 회원별 운동 기록 및 회원 메모 -->
                <div v-else class="space-y-4">
                  <!-- 회원 메모 조회 상태 -->
                  <p v-if="isMemberMemosLoading" role="status" class="text-xs text-slate-500">
                    회원 메모를 불러오는 중...
                  </p>

                  <p v-else-if="memberMemosError" role="alert" class="text-xs text-red-600">
                    회원 메모를 불러오지 못했습니다.
                  </p>

                  <!-- 참여 회원별 정보 -->
                  <div v-for="attendee in detail.attendees" :key="attendee.id" class="space-y-3">
                    <!-- 회원 메모가 등록된 경우 표시 -->
                    <div
                      v-if="memberMemos?.[attendee.id]?.trim()"
                      class="rounded-xl border border-amber-200 bg-amber-50 p-4"
                    >
                      <div class="flex items-center gap-2">
                        <StickyNote :size="16" class="shrink-0 text-amber-600" aria-hidden="true" />
                        <h4 class="text-sm font-semibold text-amber-900">
                          {{ attendee.memberName }} 회원 메모
                        </h4>
                      </div>

                      <p
                        class="mt-2 whitespace-pre-wrap break-words text-sm leading-relaxed text-amber-900"
                      >
                        {{ memberMemos[attendee.id] }}
                      </p>
                    </div>

                    <!-- 기존 운동 기록 및 출석 관리 -->
                    <SessionWorkoutRecordEditor
                      :attendance="attendee"
                      @updated="handleWorkoutRecordUpdated"
                    />
                  </div>
                </div>
              </div>

              <!-- 수업 취소 / 삭제 -->
              <div
                v-if="detail.status === 'scheduled'"
                class="mt-6 rounded-xl border border-slate-200 p-4"
              >
                <h3 class="text-sm font-semibold text-slate-900">수업 관리</h3>
                <p class="mt-1 text-xs leading-5 text-slate-500">
                  실제 예약이 취소됐다면 수업 취소, 잘못 등록한 일정이라면 수업 삭제를 선택하세요.
                </p>

                <div class="mt-4 grid grid-cols-2 gap-2">
                  <!-- 수업 전체 취소 -->
                  <button
                    type="button"
                    :disabled="isBusy || isEditing || !canCancelEntireSession"
                    class="flex min-h-11 items-center justify-center gap-2 rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-40"
                    @click="handleCancelSession"
                  >
                    <LoaderCircle v-if="isCancelling" :size="16" class="animate-spin" />
                    <Ban v-else :size="16" />
                    {{ isCancelling ? '취소 중...' : '수업 취소' }}
                  </button>

                  <!-- 잘못 등록한 수업 삭제 -->
                  <button
                    type="button"
                    :disabled="isBusy || isEditing || !canDeleteSession"
                    class="flex min-h-11 items-center justify-center gap-2 rounded-lg border border-rose-200 bg-rose-50 px-3 py-2 text-xs font-semibold text-rose-700 transition hover:bg-rose-100 disabled:cursor-not-allowed disabled:opacity-40"
                    @click="handleDeleteSession"
                  >
                    <LoaderCircle v-if="isDeleting" :size="16" class="animate-spin" />
                    <Trash2 v-else :size="16" />
                    {{ isDeleting ? '삭제 중...' : '수업 삭제' }}
                  </button>
                </div>

                <p v-if="hasDeductedAttendance" class="mt-3 text-xs leading-5 text-rose-600">
                  출석·노쇼·당일 취소 처리된 회원이 있어 수업 전체 취소 또는 삭제가 제한됩니다.
                </p>
                <p v-else class="mt-3 text-xs leading-5 text-slate-500">
                  수업 취소 기록은 달력에 남지만, 삭제된 수업은 일반 달력에서 숨겨집니다.
                </p>
              </div>

              <!-- 이용권 차감 안내 -->
              <div class="mt-5 rounded-xl bg-slate-50 p-4 text-xs leading-6 text-slate-600">
                <p class="mb-1 font-semibold text-slate-700">이용권 차감 안내</p>
                <p>출석 · 노쇼 · 당일 취소 → 1회 차감</p>
                <p>예정 · 일반 취소 → 차감 없음</p>
                <p>차감된 출석을 예정이나 일반 취소로 변경하면 1회 복구됩니다.</p>
              </div>
            </div>

            <!-- PC에서는 작성 영역 옆, 모바일에서는 접고 펼치는 참고 영역 -->
            <aside
              v-if="detail.attendees.length > 0"
              class="order-first min-w-0 lg:order-last lg:sticky lg:top-0"
            >
              <button
                type="button"
                :aria-expanded="isPreviousRecordsOpen"
                aria-controls="session-previous-records"
                class="flex w-full items-center justify-between gap-2 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm font-semibold text-blue-700 lg:hidden"
                @click="isPreviousRecordsOpen = !isPreviousRecordsOpen"
              >
                <span>이전 운동 기록 {{ isPreviousRecordsOpen ? '접기' : '보기' }}</span>
                <ChevronDown
                  :size="16"
                  class="shrink-0 transition-transform"
                  :class="{ 'rotate-180': isPreviousRecordsOpen }"
                />
              </button>

              <div
                id="session-previous-records"
                class="mt-3 space-y-3 lg:mt-0"
                :class="isPreviousRecordsOpen ? 'block' : 'hidden lg:block'"
              >
                <!-- 그룹 수업에서도 현재 작성 중인 계획을 유지하며 회원 전환 -->
                <div v-if="detail.attendees.length > 1">
                  <label
                    for="session-history-member"
                    class="mb-2 block text-xs font-semibold text-slate-700"
                  >
                    이전 기록을 확인할 회원
                  </label>

                  <select
                    id="session-history-member"
                    v-model="selectedHistoryAttendanceId"
                    class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-700 outline-none focus:border-blue-500"
                  >
                    <option
                      v-for="attendee in detail.attendees"
                      :key="attendee.id"
                      :value="attendee.id"
                    >
                      {{ attendee.memberName }}
                    </option>
                  </select>
                </div>

                <!-- 참고 기록은 변경 중인 입력값이 아닌 저장된 수업 일정 기준 -->
                <p
                  v-if="
                    isEditing && (editDate !== detail.date || editStartTime !== detail.startTime)
                  "
                  class="rounded-lg bg-amber-50 p-3 text-xs leading-5 text-amber-800"
                >
                  이전 기록은 저장된 수업 일정 기준입니다. 변경한 일정은 저장 후 반영됩니다.
                </p>

                <PreviousWorkoutRecords
                  v-if="selectedHistoryAttendance"
                  :attendance-id="selectedHistoryAttendance.id"
                  :member-name="selectedHistoryAttendance.memberName"
                  :session-date="detail.date"
                  :session-start-time="detail.startTime"
                />
              </div>
            </aside>
          </div>

          <!-- 오류 메시지 -->
          <div
            v-if="errorMessage"
            role="alert"
            class="mt-4 flex items-start gap-2 rounded-lg bg-rose-50 p-3 text-sm text-rose-700"
          >
            <AlertCircle :size="18" class="mt-0.5 shrink-0" />
            <span>{{ errorMessage }}</span>
          </div>
        </div>

        <!-- 모달 하단 -->
        <footer class="shrink-0 border-t border-slate-200 px-5 py-4">
          <button
            type="button"
            :disabled="isBusy"
            class="w-full rounded-lg border border-slate-300 px-4 py-2.5 text-sm font-medium text-slate-700 transition hover:bg-slate-50 disabled:opacity-50"
            @click="closeDialog"
          >
            닫기
          </button>
        </footer>
      </section>
    </div>
  </Teleport>
</template>
