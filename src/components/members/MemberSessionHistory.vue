<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useQuery, useQueryClient } from '@tanstack/vue-query'
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
// 회원별 수업 이력 조회
// ============================================

const queryClient = useQueryClient()

const {
  data: sessionRecords,
  isPending: isLoading,
  error: queryError,
} = useQuery({
  queryKey: computed(() => ['member-session-history', props.memberId]),

  enabled: computed(() => !!props.memberId),

  queryFn: async (): Promise<MemberSessionRecord[]> => {
    // ============================================
    // 1. 해당 회원의 출석 및 운동 기록 조회
    // ============================================

    // 초기 MVP는 최근 등록된 기록 100건까지 조회
    // 전체 이력의 수업일 기준 서버 페이지네이션은 후속 단계에서 적용
    const { data: attendances, error: attendanceError } = await supabase
      .from('session_attendances')
      .select('id, session_id, attendance_status, workout_notes')
      .eq('member_id', props.memberId)
      .order('created_at', { ascending: false })
      .limit(100)

    if (attendanceError) throw attendanceError
    if (!attendances?.length) return []

    // ============================================
    // 2. 연결된 수업 일정 및 계획 조회
    // ============================================

    const sessionIds = [...new Set(attendances.map((attendance) => attendance.session_id))]

    const { data: sessions, error: sessionError } = await supabase
      .from('sessions')
      .select('id, company_id, starts_at, ends_at, session_type, notes')
      .in('id', sessionIds)
      // 소프트 삭제된 수업은 이력에서 제외
      .is('deleted_at', null)

    if (sessionError) throw sessionError
    if (!sessions?.length) return []

    // ============================================
    // 3. 근무처 이름 조회
    // ============================================

    const companyIds = [...new Set(sessions.map((session) => session.company_id))]

    const { data: companies, error: companyError } = await supabase
      .from('companies')
      .select('id, name')
      .in('id', companyIds)

    if (companyError) throw companyError

    const companyNames = new Map((companies ?? []).map((company) => [company.id, company.name]))
    const sessionsById = new Map(sessions.map((session) => [session.id, session]))

    // ============================================
    // 4. 회원별 수업 이력 데이터 구성
    // ============================================

    const records: MemberSessionRecord[] = []

    for (const attendance of attendances) {
      const session = sessionsById.get(attendance.session_id)
      if (!session) continue

      records.push({
        attendanceId: attendance.id,
        sessionId: session.id,
        startsAt: session.starts_at,
        endsAt: session.ends_at,
        sessionType: session.session_type as SessionType,
        attendanceStatus: attendance.attendance_status as AttendanceStatus,
        companyId: session.company_id,
        companyName: companyNames.get(session.company_id) ?? '근무처 확인 필요',
        sessionNotes: session.notes,
        workoutNotes: attendance.workout_notes ?? null,
      })
    }

    // 실제 수업 날짜 기준 최신순 정렬
    return records.sort((a, b) => new Date(b.startsAt).getTime() - new Date(a.startsAt).getTime())
  },

  // 상세 화면에 다시 들어왔을 때 최신 출석/운동 기록 확인
  refetchOnMount: 'always',
  staleTime: 1000 * 60,
})

// ============================================
// 근무처별 수업 이력 필터
// ============================================

const selectedCompanyId = ref('all')

// 수업 이력이 있는 근무처만 선택지에 표시
const companyOptions = computed(() => {
  const companies = new Map<string, string>()

  for (const record of sessionRecords.value ?? []) {
    companies.set(record.companyId, record.companyName)
  }

  return [...companies.entries()]
    .map(([id, name]) => ({ id, name }))
    .sort((a, b) => a.name.localeCompare(b.name, 'ko'))
})

const filteredRecords = computed(() => {
  if (selectedCompanyId.value === 'all') {
    return sessionRecords.value ?? []
  }

  return (sessionRecords.value ?? []).filter(
    (record) => record.companyId === selectedCompanyId.value,
  )
})

// ============================================
// 수업 이력 더 보기
// ============================================

const visibleCount = ref(5)

const visibleRecords = computed(() => filteredRecords.value.slice(0, visibleCount.value))

const hasMoreRecords = computed(() => visibleCount.value < filteredRecords.value.length)

function showMoreRecords() {
  visibleCount.value += 5
}

// 근무처를 바꾸면 다시 최신 수업 5개부터 표시
watch(selectedCompanyId, () => {
  visibleCount.value = 5
  editingAttendanceId.value = null
  saveError.value = ''
  saveSuccessId.value = null
})

// 다른 회원 상세 화면으로 이동하면 필터 초기화
watch(
  () => props.memberId,
  () => {
    selectedCompanyId.value = 'all'
    visibleCount.value = 5
    editingAttendanceId.value = null
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
  <!-- 회원별 수업 이력 -->
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
        v-if="sessionRecords"
        class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-600"
      >
        {{ filteredRecords.length }}개
      </span>
    </div>

    <!-- 근무처별 수업 이력 필터 -->
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

    <!-- 조회 상태 -->
    <div
      v-if="isLoading"
      class="mt-5 flex items-center justify-center gap-2 py-8 text-sm text-slate-500"
    >
      <LoaderCircle :size="18" class="animate-spin" />
      수업 이력을 불러오는 중...
    </div>

    <p
      v-else-if="queryError"
      role="alert"
      class="mt-5 rounded-lg bg-rose-50 p-4 text-sm text-rose-700"
    >
      수업 이력을 불러오지 못했습니다.
    </p>

    <p
      v-else-if="!filteredRecords.length"
      class="mt-5 rounded-lg bg-slate-50 p-6 text-center text-sm text-slate-500"
    >
      {{
        selectedCompanyId === 'all'
          ? '아직 등록된 수업 내역이 없습니다.'
          : '선택한 근무처의 수업 이력이 없습니다.'
      }}
    </p>

    <!-- 수업 이력 카드 목록 -->
    <div v-else class="mt-5 space-y-3">
      <article
        v-for="record in visibleRecords"
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

        <!-- 수업 공통 계획 -->
        <div v-if="record.sessionNotes" class="mt-4">
          <p class="mb-1 text-xs font-semibold text-slate-500">수업 계획</p>
          <p class="whitespace-pre-wrap text-sm text-slate-700">{{ record.sessionNotes }}</p>
        </div>

        <!-- 회원별 실제 운동 기록 -->
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

          <!-- 운동 기록 수정 폼 -->
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

      <!-- 이전 수업 더 보기 -->
      <button
        v-if="hasMoreRecords"
        type="button"
        class="flex w-full items-center justify-center gap-2 rounded-lg border border-slate-200 py-3 text-sm font-medium text-slate-600 hover:bg-slate-50"
        @click="showMoreRecords"
      >
        <ChevronDown :size="16" />
        이전 수업 더 보기
      </button>

      <p
        v-if="sessionRecords && sessionRecords.length >= 100"
        class="text-center text-xs text-slate-400"
      >
        현재 최근 등록된 수업 100건까지 조회합니다.
      </p>
    </div>
  </section>
</template>
