import { supabase } from '@/lib/supabase'
import type { CompanyType } from '@/api/companies'
import type { PackagePause } from '@/api/packagePauses'
import type { MonthlySessionExportRecord } from '@/api/sessionExports'
import type { AttendanceStatus, SessionStatus, SessionType } from '@/api/sessions'
import type { PackageStatus, PackageType, UsageType } from '@/types/package'
import { getMemberStatus, type MemberStatus } from '@/utils/memberStatus'
import { getPackagePauseStatus, type PackagePauseStatus } from '@/utils/packagePauseStatus'

// 회원 내역 다운로드에서 사용할 데이터 타입
export interface MemberExportMember {
  id: string
  name: string
  phone: string
  status: MemberStatus
  createdAt: string
}

export interface MemberExportCompany {
  companyId: string
  companyName: string
  companyType: CompanyType
  isActive: boolean
}

export interface MemberExportPackage {
  id: string
  memberId: string
  companyId: string | null
  companyName: string | null
  companyIsActive: boolean | null
  packageType: PackageType
  usageType: UsageType
  totalSessions: number | null
  remainingSessions: number | null
  startsOn: string | null
  endsOn: string | null
  status: PackageStatus
  createdAt: string
}

export interface MemberExportPause {
  id: string
  packageId: string
  startsOn: string
  endsOn: string
  resumedOn: string | null
  cancelledAt: string | null
  reason: string | null
  status: PackagePauseStatus
  createdAt: string
}

// 월간 다운로드와 같은 수업 정보에 연결된 이용권 ID를 추가
export interface MemberExportRecord extends MonthlySessionExportRecord {
  packageId: string | null
}

export interface MemberExportData {
  exportedAt: string
  asOfDate: string
  timezone: 'Asia/Seoul'
  member: MemberExportMember
  companies: MemberExportCompany[]
  packages: MemberExportPackage[]
  pauses: MemberExportPause[]
  records: MemberExportRecord[]
  companyCount: number
  packageCount: number
  pauseCount: number
  recordCount: number
}

export interface GetMemberExportParams {
  memberId: string
  signal?: AbortSignal
}

// DB 조회 함수가 반환하는 데이터 타입
type DatabaseCount = number | string

interface MemberExportPackageResponse {
  id: string
  member_id: string
  company_id: string | null
  company_name: string | null
  company_is_active: boolean | null
  package_type: PackageType
  usage_type: UsageType
  total_sessions: DatabaseCount | null
  remaining_sessions: DatabaseCount | null
  starts_on: string | null
  ends_on: string | null
  status: PackageStatus
  created_at: string
}

interface MemberExportResponse {
  exported_at: string
  as_of_date: string
  timezone: string
  member: {
    id: string
    name: string
    phone: string
    status: MemberStatus
    created_at: string
  }
  companies: {
    company_id: string
    company_name: string
    company_type: CompanyType
    is_active: boolean
  }[]
  packages: MemberExportPackageResponse[]
  pauses: PackagePause[]
  records: {
    attendance_id: string
    session_id: string
    member_id: string
    member_name: string
    package_id: string | null
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
  company_count: DatabaseCount
  package_count: DatabaseCount
  pause_count: DatabaseCount
  record_count: DatabaseCount
}

// 누락되거나 잘못된 숫자를 0으로 바꾸지 않고 오류로 처리
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

// 기간제 이용권의 횟수는 null로 유지
function toNullableCount(value: DatabaseCount | null): number | null {
  return value === null ? null : toCount(value)
}

function isDateString(value: string): boolean {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false

  const date = new Date(`${value}T00:00:00Z`)
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
}

// 회원의 모든 근무처와 전체 기간 내역 조회
export async function getMemberExport(params: GetMemberExportParams): Promise<MemberExportData> {
  const memberId = params.memberId.trim().toLowerCase()

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(memberId)) {
    throw new Error('올바른 회원을 선택해 주세요.')
  }

  let request = supabase.rpc('get_member_export', { p_member_id: memberId })

  if (params.signal) {
    request = request.abortSignal(params.signal)
  }

  const { data, error } = await request

  if (error) throw error

  const response = data as MemberExportResponse | null

  // 빈 내역은 허용하되, 요청한 회원과 응답 형식은 확인
  if (
    !response ||
    response.member?.id !== memberId ||
    response.timezone !== 'Asia/Seoul' ||
    !isDateString(response.as_of_date) ||
    !Number.isFinite(Date.parse(response.exported_at)) ||
    !Array.isArray(response.companies) ||
    !Array.isArray(response.packages) ||
    !Array.isArray(response.pauses) ||
    !Array.isArray(response.records)
  ) {
    throw new Error('회원 다운로드 데이터를 확인하지 못했습니다. 다시 시도해 주세요.')
  }

  const companyCount = toCount(response.company_count)
  const packageCount = toCount(response.package_count)
  const pauseCount = toCount(response.pause_count)
  const recordCount = toCount(response.record_count)
  const packageIds = new Set(response.packages.map((pkg) => pkg.id))

  // 일부 내역이 누락되거나 다른 회원의 내역이 섞인 경우 파일 생성 중단
  if (
    response.companies.length !== companyCount ||
    response.packages.length !== packageCount ||
    response.pauses.length !== pauseCount ||
    response.records.length !== recordCount ||
    response.packages.some((pkg) => pkg.member_id !== memberId) ||
    response.records.some((record) => record.member_id !== memberId) ||
    response.pauses.some((pause) => !packageIds.has(pause.package_id))
  ) {
    throw new Error('회원 다운로드 내역이 일치하지 않습니다. 다시 시도해 주세요.')
  }

  // 이용권별 일시정지 내역을 연결해 기존 회원 상태 계산에 사용
  const pausesByPackage = new Map<string, PackagePause[]>()

  for (const pause of response.pauses) {
    const pauses = pausesByPackage.get(pause.package_id)

    if (pauses) pauses.push(pause)
    else pausesByPackage.set(pause.package_id, [pause])
  }

  const statusPackages = response.packages.map((pkg) => ({
    ...pkg,
    total_sessions: toNullableCount(pkg.total_sessions),
    remaining_sessions: toNullableCount(pkg.remaining_sessions),
    package_pauses: pausesByPackage.get(pkg.id) ?? [],
  }))

  // 브라우저 날짜 대신 DB가 반환한 한국 날짜를 기준으로 계산
  const member: MemberExportMember = {
    id: response.member.id,
    name: response.member.name,
    phone: response.member.phone,
    status: getMemberStatus(response.member.status, statusPackages, response.as_of_date),
    createdAt: response.member.created_at,
  }

  const companies: MemberExportCompany[] = response.companies.map((company) => ({
    companyId: company.company_id,
    companyName: company.company_name,
    companyType: company.company_type,
    isActive: company.is_active,
  }))

  const packages: MemberExportPackage[] = statusPackages.map((pkg) => ({
    id: pkg.id,
    memberId: pkg.member_id,
    companyId: pkg.company_id,
    companyName: pkg.company_name,
    companyIsActive: pkg.company_is_active,
    packageType: pkg.package_type,
    usageType: pkg.usage_type,
    totalSessions: pkg.total_sessions,
    remainingSessions: pkg.remaining_sessions,
    startsOn: pkg.starts_on,
    endsOn: pkg.ends_on,
    status: pkg.status,
    createdAt: pkg.created_at,
  }))

  const pauses: MemberExportPause[] = response.pauses.map((pause) => ({
    id: pause.id,
    packageId: pause.package_id,
    startsOn: pause.starts_on,
    endsOn: pause.ends_on,
    resumedOn: pause.resumed_on,
    cancelledAt: pause.cancelled_at,
    reason: pause.reason,
    status: getPackagePauseStatus(pause, response.as_of_date),
    createdAt: pause.created_at,
  }))

  const records: MemberExportRecord[] = response.records.map((record) => ({
    attendanceId: record.attendance_id,
    sessionId: record.session_id,
    memberId: record.member_id,
    memberName: record.member_name,
    packageId: record.package_id,
    companyId: record.company_id,
    companyName: record.company_name,
    sessionType: record.session_type,
    sessionStatus: record.session_status,
    attendanceStatus: record.attendance_status,
    startsAt: record.starts_at,
    endsAt: record.ends_at,
    sessionNotes: record.session_notes,
    workoutNotes: record.workout_notes,
    deductedSessions: toCount(record.deducted_sessions),
  }))

  return {
    exportedAt: response.exported_at,
    asOfDate: response.as_of_date,
    timezone: 'Asia/Seoul',
    member,
    companies,
    packages,
    pauses,
    records,
    companyCount,
    packageCount,
    pauseCount,
    recordCount,
  }
}
