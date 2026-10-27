import { supabase } from '@/lib/supabase'
import type { CompanyType } from '@/api/companies'
import type { AttendanceStatus, SessionStatus, SessionType } from '@/api/sessions'

// ============================================
// 화면 및 엑셀 생성에서 사용할 데이터 타입
// ============================================

export interface MonthlySessionExportSummary {
  totalSessions: number
  ptSessions: number
  groupSessions: number
  completedSessions: number
  scheduledSessions: number
  cancelledSessions: number
  attendedCount: number
  noShowCount: number
  sameDayCancelledCount: number
  attendanceCancelledCount: number
  attendanceScheduledCount: number
}

export interface MonthlySessionExportCompany {
  companyId: string
  companyName: string
  companyType: CompanyType
  isActive: boolean
  totalSessions: number
  ptSessions: number
  groupSessions: number
  completedSessions: number
  scheduledSessions: number
  cancelledSessions: number
}

export interface MonthlySessionExportRecord {
  attendanceId: string
  sessionId: string
  memberId: string
  memberName: string
  companyId: string
  companyName: string
  sessionType: SessionType
  sessionStatus: SessionStatus
  attendanceStatus: AttendanceStatus
  startsAt: string
  endsAt: string
  sessionNotes: string | null
  workoutNotes: string | null
  deductedSessions: number
}

export interface MonthlySessionExportData {
  year: number
  month: number
  timezone: 'Asia/Seoul'
  summary: MonthlySessionExportSummary
  companies: MonthlySessionExportCompany[]
  records: MonthlySessionExportRecord[]
  recordCount: number
}

export interface GetMonthlySessionExportParams {
  year: number
  month: number
  signal?: AbortSignal
}

// ============================================
// DB 조회 함수가 반환하는 데이터 타입
// ============================================

// 집계 결과는 숫자 또는 숫자 문자열로 전달될 수 있음
type DatabaseCount = number | string

interface MonthlySessionExportResponse {
  year: number
  month: number
  timezone: string
  summary: {
    total_sessions: DatabaseCount
    pt_sessions: DatabaseCount
    group_sessions: DatabaseCount
    completed_sessions: DatabaseCount
    scheduled_sessions: DatabaseCount
    cancelled_sessions: DatabaseCount
    attended_count: DatabaseCount
    no_show_count: DatabaseCount
    same_day_cancelled_count: DatabaseCount
    attendance_cancelled_count: DatabaseCount
    attendance_scheduled_count: DatabaseCount
  }
  companies: {
    company_id: string
    company_name: string
    company_type: CompanyType
    is_active: boolean
    total_sessions: DatabaseCount
    pt_sessions: DatabaseCount
    group_sessions: DatabaseCount
    completed_sessions: DatabaseCount
    scheduled_sessions: DatabaseCount
    cancelled_sessions: DatabaseCount
  }[]
  records: {
    attendance_id: string
    session_id: string
    member_id: string
    member_name: string
    company_id: string
    company_name: string
    session_type: SessionType
    session_status: SessionStatus
    attendance_status: AttendanceStatus
    starts_at: string
    ends_at: string
    session_notes: string | null
    workout_notes: string | null
    deducted_sessions: DatabaseCount
  }[]
  record_count: DatabaseCount
}

// 누락된 값이나 잘못된 숫자를 0으로 바꾸지 않고 오류로 처리
function toCount(value: DatabaseCount): number {
  const count =
    typeof value === 'number'
      ? value
      : typeof value === 'string' && /^\d+$/.test(value)
        ? Number(value)
        : NaN

  if (!Number.isSafeInteger(count) || count < 0) {
    throw new Error('다운로드 데이터의 건수가 올바르지 않습니다. 다시 시도해 주세요.')
  }

  return count
}

// ============================================
// 월별 엑셀 다운로드용 데이터 조회
// ============================================

export async function getMonthlySessionExport(
  params: GetMonthlySessionExportParams,
): Promise<MonthlySessionExportData> {
  const { year, month, signal } = params

  if (
    !Number.isInteger(year) ||
    year < 2000 ||
    year > 2100 ||
    !Number.isInteger(month) ||
    month < 1 ||
    month > 12
  ) {
    throw new Error('올바른 연도와 월을 선택해 주세요.')
  }

  let request = supabase.rpc('get_monthly_session_export', {
    p_year: year,
    p_month: month,
  })

  if (signal) {
    request = request.abortSignal(signal)
  }

  const { data, error } = await request

  if (error) throw error

  const response = data as MonthlySessionExportResponse | null

  // 요청한 월의 응답인지 확인하고, 빈 배열과 조회 실패를 구분
  if (
    !response ||
    response.year !== year ||
    response.month !== month ||
    response.timezone !== 'Asia/Seoul' ||
    !response.summary ||
    !Array.isArray(response.companies) ||
    !Array.isArray(response.records)
  ) {
    throw new Error('다운로드 데이터를 확인하지 못했습니다. 다시 시도해 주세요.')
  }

  const rawSummary = response.summary

  // DB의 snake_case를 화면에서 사용하는 camelCase로 변환
  const summary: MonthlySessionExportSummary = {
    totalSessions: toCount(rawSummary.total_sessions),
    ptSessions: toCount(rawSummary.pt_sessions),
    groupSessions: toCount(rawSummary.group_sessions),
    completedSessions: toCount(rawSummary.completed_sessions),
    scheduledSessions: toCount(rawSummary.scheduled_sessions),
    cancelledSessions: toCount(rawSummary.cancelled_sessions),
    attendedCount: toCount(rawSummary.attended_count),
    noShowCount: toCount(rawSummary.no_show_count),
    sameDayCancelledCount: toCount(rawSummary.same_day_cancelled_count),
    attendanceCancelledCount: toCount(rawSummary.attendance_cancelled_count),
    attendanceScheduledCount: toCount(rawSummary.attendance_scheduled_count),
  }

  const companies: MonthlySessionExportCompany[] = response.companies.map((company) => ({
    companyId: company.company_id,
    companyName: company.company_name,
    companyType: company.company_type,
    isActive: company.is_active,
    totalSessions: toCount(company.total_sessions),
    ptSessions: toCount(company.pt_sessions),
    groupSessions: toCount(company.group_sessions),
    completedSessions: toCount(company.completed_sessions),
    scheduledSessions: toCount(company.scheduled_sessions),
    cancelledSessions: toCount(company.cancelled_sessions),
  }))

  const records: MonthlySessionExportRecord[] = response.records.map((record) => ({
    attendanceId: record.attendance_id,
    sessionId: record.session_id,
    memberId: record.member_id,
    memberName: record.member_name,
    companyId: record.company_id,
    companyName: record.company_name,
    sessionType: record.session_type,
    sessionStatus: record.session_status,
    attendanceStatus: record.attendance_status,
    // 날짜는 원본 시각을 유지하고, 엑셀 생성 시 한국 시간으로 표시
    startsAt: record.starts_at,
    endsAt: record.ends_at,
    sessionNotes: record.session_notes,
    workoutNotes: record.workout_notes,
    deductedSessions: toCount(record.deducted_sessions),
  }))

  const recordCount = toCount(response.record_count)

  // 수업 건수와 참여 회원 건수를 별도로 확인
  const attendanceCount =
    summary.attendedCount +
    summary.noShowCount +
    summary.sameDayCancelledCount +
    summary.attendanceCancelledCount +
    summary.attendanceScheduledCount

  const companySessionCount = companies.reduce((sum, company) => sum + company.totalSessions, 0)

  // 일부 기록이 누락되거나 집계가 맞지 않으면 파일 생성을 중단
  if (
    records.length !== recordCount ||
    attendanceCount !== recordCount ||
    companySessionCount !== summary.totalSessions ||
    summary.ptSessions + summary.groupSessions !== summary.totalSessions ||
    summary.completedSessions + summary.scheduledSessions + summary.cancelledSessions !==
      summary.totalSessions
  ) {
    throw new Error('다운로드 통계와 수업 기록이 일치하지 않습니다. 다시 시도해 주세요.')
  }

  return {
    year,
    month,
    timezone: 'Asia/Seoul',
    summary,
    companies,
    records,
    recordCount,
  }
}
