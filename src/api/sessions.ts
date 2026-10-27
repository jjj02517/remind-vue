import { supabase } from '@/lib/supabase'

// 수업 종류와 수업 자체의 진행 상태
export type SessionType = 'pt' | 'group'
export type SessionStatus = 'scheduled' | 'completed' | 'cancelled'

// 달력과 일일 수업 목록에서 사용하는 데이터
export interface CalendarSession {
  id: string
  date: string
  startTime: string
  endTime: string
  title: string
  companyName: string
  type: SessionType
  status: SessionStatus
}

// 수업 등록에서 선택할 수 있는 횟수제 이용권
export interface SessionPackageOption {
  id: string
  packageType: SessionType
  totalSessions: number
  remainingSessions: number
  startsOn: string | null
  endsOn: string | null
}

// 근무처에 연결된 회원과 수업 종류별 이용권
export interface SessionMemberOption {
  id: string
  name: string
  phone: string
  packages: SessionPackageOption[]
}

// ============================================
// 날짜 및 시간 변환
// ============================================

// Supabase의 서버 시각을 한국 기준 날짜·시간으로 변환
const dateFormatter = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Seoul',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})

const timeFormatter = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Seoul',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})

function sessionDateKey(value: string): string {
  const parts = dateFormatter.formatToParts(new Date(value))
  const get = (name: string) => parts.find((part) => part.type === name)?.value ?? ''

  return `${get('year')}-${get('month')}-${get('day')}`
}

// 캘린더 월간 조회 구간: 한국 시간 기준 월초부터 다음 달 월초 직전까지
function getMonthBounds(year: number, month: number) {
  const start = `${year}-${String(month).padStart(2, '0')}-01T00:00:00+09:00`

  const next = new Date(Date.UTC(year, month, 1))

  const nextDate = `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(
    2,
    '0',
  )}-01T00:00:00+09:00`

  return {
    start: new Date(start).toISOString(),
    end: new Date(nextDate).toISOString(),
  }
}

// ============================================
// 월간 수업 조회
// ============================================

// 월간 달력에서 사용하는 실제 수업과 회원·근무처 이름 조회
export async function getCalendarSessions(year: number, month: number): Promise<CalendarSession[]> {
  const bounds = getMonthBounds(year, month)

  const { data: sessions, error: sessionsError } = await supabase
    .from('sessions')
    .select('id, company_id, session_type, starts_at, ends_at, status')
    // 소프트 삭제된 수업은 달력에 표시하지 않음
    .is('deleted_at', null)
    .gte('starts_at', bounds.start)
    .lt('starts_at', bounds.end)
    .order('starts_at', { ascending: true })

  if (sessionsError) throw sessionsError
  if (!sessions?.length) return []

  const sessionIds = sessions.map((session) => session.id)
  const companyIds = [...new Set(sessions.map((session) => session.company_id))]

  const [
    { data: attendanceRows, error: attendanceError },
    { data: companyRows, error: companyError },
  ] = await Promise.all([
    supabase
      .from('session_attendances')
      .select('session_id, member_id')
      .in('session_id', sessionIds),
    supabase.from('companies').select('id, name').in('id', companyIds),
  ])

  if (attendanceError) throw attendanceError
  if (companyError) throw companyError

  const memberIds = [...new Set((attendanceRows ?? []).map((row) => row.member_id))]

  const memberRows = memberIds.length
    ? await supabase.from('members').select('id, name').in('id', memberIds)
    : { data: [], error: null }

  if (memberRows.error) throw memberRows.error

  const companyNames = new Map((companyRows ?? []).map((row) => [row.id, row.name]))

  const memberNames = new Map((memberRows.data ?? []).map((row) => [row.id, row.name]))

  const membersBySession = new Map<string, string[]>()

  for (const attendance of attendanceRows ?? []) {
    const names = membersBySession.get(attendance.session_id) ?? []

    names.push(memberNames.get(attendance.member_id) ?? '회원 확인 필요')

    membersBySession.set(attendance.session_id, names)
  }

  return sessions.map((session) => {
    const names = membersBySession.get(session.id) ?? []

    return {
      id: session.id,
      date: sessionDateKey(session.starts_at),
      startTime: timeFormatter.format(new Date(session.starts_at)),
      endTime: timeFormatter.format(new Date(session.ends_at)),
      type: session.session_type as SessionType,
      status: session.status as SessionStatus,
      companyName: companyNames.get(session.company_id) ?? '근무처 확인 필요',
      title:
        session.session_type === 'pt'
          ? (names[0] ?? '회원 확인 필요')
          : `그룹 수업 · ${names.length}명`,
    }
  })
}

// ============================================
// 수업 등록용 회원 및 이용권 조회
// ============================================

// 근무처와 수업 종류에 맞는 회원·횟수제 이용권 조회
export async function getSessionMemberOptions(
  companyId: string,
  sessionType: SessionType,
): Promise<SessionMemberOption[]> {
  const { data: links, error: linksError } = await supabase
    .from('company_members')
    .select('member_id')
    .eq('company_id', companyId)

  if (linksError) throw linksError

  const memberIds = [...new Set((links ?? []).map((link) => link.member_id))]

  if (!memberIds.length) return []

  const [{ data: members, error: membersError }, { data: packages, error: packagesError }] =
    await Promise.all([
      supabase
        .from('members')
        .select('id, name, phone, status')
        .in('id', memberIds)
        .neq('status', 'archived')
        .order('name', { ascending: true }),
      supabase
        .from('member_packages')
        .select(
          'id, member_id, package_type, total_sessions, remaining_sessions, starts_on, ends_on',
        )
        .eq('company_id', companyId)
        .eq('package_type', sessionType)
        .eq('usage_type', 'count')
        .eq('status', 'active')
        .gt('remaining_sessions', 0)
        .in('member_id', memberIds),
    ])

  if (membersError) throw membersError
  if (packagesError) throw packagesError

  const packagesByMember = new Map<string, SessionPackageOption[]>()

  for (const pkg of packages ?? []) {
    const existing = packagesByMember.get(pkg.member_id) ?? []

    existing.push({
      id: pkg.id,
      packageType: pkg.package_type as SessionType,
      totalSessions: pkg.total_sessions ?? 0,
      remainingSessions: pkg.remaining_sessions ?? 0,
      startsOn: pkg.starts_on,
      endsOn: pkg.ends_on,
    })

    packagesByMember.set(pkg.member_id, existing)
  }

  // 예약 가능한 횟수제 이용권이 있는 회원만 선택지에 표시
  return (members ?? [])
    .map((member) => ({
      id: member.id,
      name: member.name,
      phone: member.phone,
      packages: packagesByMember.get(member.id) ?? [],
    }))
    .filter((member) => member.packages.length > 0)
}

// ============================================
// 수업 시간 및 중복 검사
// ============================================

// 서울 기준 정시에 시작하는 수업의 1시간 구간 계산
// 23:00 수업의 종료는 다음 날 00:00이므로 시간 문자열끼리 비교하지 않음
function getHourlySessionBounds(date: string, startTime: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error('수업 날짜를 확인해 주세요.')
  }

  if (!/^(?:[01]\d|2[0-3]):00$/.test(startTime)) {
    throw new Error('수업은 정시에만 시작할 수 있습니다.')
  }

  const start = new Date(`${date}T${startTime}:00+09:00`)

  if (Number.isNaN(start.getTime())) {
    throw new Error('수업 날짜를 확인해 주세요.')
  }

  const end = new Date(start.getTime() + 60 * 60 * 1000)

  return {
    startIso: start.toISOString(),
    endIso: end.toISOString(),
  }
}

// 새 예약 전에 시간 중복을 미리 표시
// 확정 검사는 등록 RPC에서 진행
export interface SessionConflict {
  id: string
  companyName: string
  type: SessionType
  startTime: string
  endTime: string
}

export async function getSessionConflicts(
  date: string,
  startTime: string,
): Promise<SessionConflict[]> {
  const { startIso, endIso } = getHourlySessionBounds(date, startTime)

  const { data: rows, error } = await supabase
    .from('sessions')
    .select('id, company_id, session_type, starts_at, ends_at')
    // 삭제된 수업은 시간 충돌 대상에서 제외
    .is('deleted_at', null)
    .neq('status', 'cancelled')
    .lt('starts_at', endIso)
    .gt('ends_at', startIso)
    .order('starts_at', { ascending: true })
    .limit(5)

  if (error) throw error
  if (!rows?.length) return []

  const companyIds = [...new Set(rows.map((row) => row.company_id))]

  const { data: companies, error: companyError } = await supabase
    .from('companies')
    .select('id, name')
    .in('id', companyIds)

  if (companyError) throw companyError

  const names = new Map((companies ?? []).map((company) => [company.id, company.name]))

  return rows.map((row) => ({
    id: row.id,
    companyName: names.get(row.company_id) ?? '근무처 확인 필요',
    type: row.session_type as SessionType,
    startTime: timeFormatter.format(new Date(row.starts_at)),
    endTime: timeFormatter.format(new Date(row.ends_at)),
  }))
}

// ============================================
// 수업 등록
// ============================================

// 수업 등록 파라미터
export interface CreateSessionParams {
  companyId: string
  sessionType: SessionType
  date: string
  startTime: string
  participants: {
    memberId: string
    packageId: string
  }[]
  notes: string
}

// 하나의 RPC에서 수업 및 참여 회원을 원자적으로 저장
export async function createSession(params: CreateSessionParams): Promise<string> {
  if (!params.companyId) {
    throw new Error('근무처를 선택해 주세요.')
  }

  const { startIso, endIso } = getHourlySessionBounds(params.date, params.startTime)

  if (!params.participants.length) {
    throw new Error('참여 회원과 이용권을 선택해 주세요.')
  }

  if (params.sessionType === 'pt' && params.participants.length !== 1) {
    throw new Error('PT 수업에는 회원을 1명만 등록할 수 있습니다.')
  }

  const { data, error } = await supabase.rpc('create_session_with_participants', {
    p_company_id: params.companyId,
    p_session_type: params.sessionType,
    p_starts_at: startIso,
    p_ends_at: endIso,
    p_participants: params.participants.map((person) => ({
      member_id: person.memberId,
      package_id: person.packageId,
    })),
    p_notes: params.notes.trim() || null,
  })

  if (error) throw error

  return data as string
}

// ============================================
// 수업 상세 · 출석 관리
// ============================================

// 회원별 출석 상태
// 출석·노쇼·당일 취소는 1회 차감 대상
export type AttendanceStatus =
  'scheduled' | 'attended' | 'no_show' | 'same_day_cancelled' | 'cancelled'

// 참여 회원별 출석 상태 및 이용권 정보
export interface SessionAttendanceDetail {
  id: string
  memberId: string
  memberName: string
  packageId: string | null
  packageRemaining: number | null
  packageTotal: number | null
  status: AttendanceStatus
  // 회원별 실제 운동 기록
  workoutNotes: string | null
}

// 수업 상세 정보
export interface SessionDetail {
  id: string
  type: SessionType
  status: SessionStatus
  companyName: string
  date: string
  startTime: string
  endTime: string
  notes: string | null
  attendees: SessionAttendanceDetail[]
}

// 선택한 수업과 참여 회원별 현재 이용권 잔여 횟수 조회
export async function getSessionDetail(sessionId: string): Promise<SessionDetail> {
  const { data: session, error: sessionError } = await supabase
    .from('sessions')
    .select('id, company_id, session_type, status, starts_at, ends_at, notes')
    .eq('id', sessionId)
    .maybeSingle()

  if (sessionError) throw sessionError

  if (!session) {
    throw new Error('수업을 찾을 수 없습니다.')
  }

  const [attendancesResponse, companyResponse] = await Promise.all([
    supabase
      .from('session_attendances')
      .select('id, member_id, package_id, attendance_status, created_at, workout_notes')
      .eq('session_id', sessionId)
      .order('created_at', { ascending: true }),

    supabase.from('companies').select('name').eq('id', session.company_id).maybeSingle(),
  ])

  if (attendancesResponse.error) {
    throw attendancesResponse.error
  }

  if (companyResponse.error) {
    throw companyResponse.error
  }

  const attendanceRows = attendancesResponse.data ?? []

  const memberIds = [...new Set(attendanceRows.map((row) => row.member_id))]

  const packageIds = [
    ...new Set(attendanceRows.map((row) => row.package_id).filter((id): id is string => !!id)),
  ]

  const [membersResponse, packagesResponse] = await Promise.all([
    memberIds.length
      ? supabase.from('members').select('id, name').in('id', memberIds)
      : Promise.resolve({
          data: [],
          error: null,
        }),

    packageIds.length
      ? supabase
          .from('member_packages')
          .select('id, total_sessions, remaining_sessions')
          .in('id', packageIds)
      : Promise.resolve({
          data: [],
          error: null,
        }),
  ])

  if (membersResponse.error) {
    throw membersResponse.error
  }

  if (packagesResponse.error) {
    throw packagesResponse.error
  }

  const memberNames = new Map(
    (membersResponse.data ?? []).map((member) => [member.id, member.name]),
  )

  const packages = new Map((packagesResponse.data ?? []).map((pkg) => [pkg.id, pkg]))

  return {
    id: session.id,
    type: session.session_type as SessionType,
    status: session.status as SessionStatus,
    companyName: companyResponse.data?.name ?? '근무처 확인 필요',
    date: sessionDateKey(session.starts_at),
    startTime: timeFormatter.format(new Date(session.starts_at)),
    endTime: timeFormatter.format(new Date(session.ends_at)),
    notes: session.notes,

    attendees: attendanceRows.map((row) => {
      const pkg = row.package_id ? packages.get(row.package_id) : undefined

      return {
        id: row.id,
        memberId: row.member_id,
        memberName: memberNames.get(row.member_id) ?? '회원 확인 필요',
        packageId: row.package_id,
        packageRemaining: pkg?.remaining_sessions ?? null,
        packageTotal: pkg?.total_sessions ?? null,
        status: row.attendance_status as AttendanceStatus,

        // 회원별 실제 운동 기록
        workoutNotes: row.workout_notes ?? null,
      }
    }),
  }
}

// 출석 상태 변경은 반드시 RPC로 실행
// 이용권 차감·복구·변경 이력을 하나의 DB 트랜잭션으로 저장
export async function setSessionAttendanceStatus(
  attendanceId: string,
  status: AttendanceStatus,
): Promise<void> {
  const { error } = await supabase.rpc('set_session_attendance_status', {
    p_attendance_id: attendanceId,
    p_new_status: status,
  })

  if (error) throw error
}

// ============================================
// 수업 전체 취소
// ============================================

// PT·그룹 수업 전체 취소
// 참여 회원의 예약 상태도 함께 취소하며 변경 이력을 저장
// 이미 출석·노쇼·당일 취소가 처리된 수업은 DB에서 취소 차단
// 수업 및 회원·이용권 데이터는 삭제하지 않음
export async function cancelSession(sessionId: string): Promise<void> {
  if (!sessionId) {
    throw new Error('취소할 수업을 선택해 주세요.')
  }

  // 수업 취소와 참여 회원 상태 변경을 하나의 트랜잭션으로 처리
  const { error } = await supabase.rpc('cancel_session', {
    p_session_id: sessionId,
  })

  if (error) {
    throw error
  }
}

// ============================================
// 수업 소프트 삭제
// ============================================

// 잘못 등록한 수업을 달력에서 제거
// 실제 DB 행과 출석 변경 이력은 삭제하지 않음
// 예약 상태이며 이용권 차감 이력이 없는 수업만 삭제 가능
export async function deleteSession(sessionId: string): Promise<void> {
  if (!sessionId) {
    throw new Error('삭제할 수업을 선택해 주세요.')
  }

  // DB에서 수업 취소 및 소프트 삭제를 원자적으로 처리
  const { error } = await supabase.rpc('delete_session', {
    p_session_id: sessionId,
  })

  if (error) {
    throw error
  }
}

// ============================================
// 수업 날짜·시간·메모 수정
// ============================================

// 수업 수정 요청 데이터
export interface UpdateSessionDetailsParams {
  sessionId: string
  date: string
  startTime: string
  notes: string
}

// 예정된 수업의 일정과 메모 수정
// 회원 및 이용권 연결은 변경하지 않음
export async function updateSessionDetails(params: UpdateSessionDetailsParams): Promise<void> {
  // ============================================
  // 1. 입력값 확인
  // ============================================

  if (!params.sessionId) {
    throw new Error('수정할 수업을 선택해 주세요.')
  }

  // 기존 수업 등록과 동일하게 1시간 단위로 처리
  const { startIso } = getHourlySessionBounds(params.date, params.startTime)

  if (params.notes.length > 1000) {
    throw new Error('메모는 1000자 이하로 입력해 주세요.')
  }

  // ============================================
  // 2. 수업 수정 RPC 호출
  // ============================================

  // DB에서 다른 수업과의 시간 중복,
  // 이용권 유효기간, 수업 수정 가능 여부를 검증
  const { error } = await supabase.rpc('update_session_details', {
    p_session_id: params.sessionId,
    p_starts_at: startIso,
    p_notes: params.notes.trim() || null,
  })

  if (error) {
    throw error
  }
}

// ============================================
// 회원별 운동 기록 저장
// ============================================

// 운동 기록 저장 요청 데이터
export interface SaveSessionWorkoutRecordParams {
  attendanceId: string
  workoutNotes: string
  newStatus?: AttendanceStatus
}

// 운동 기록만 저장하거나 출석 상태와 함께 저장
export async function saveSessionWorkoutRecord(
  params: SaveSessionWorkoutRecordParams,
): Promise<void> {
  // ============================================
  // 1. 입력값 검증
  // ============================================

  if (!params.attendanceId) {
    throw new Error('수업 참여 기록을 선택해 주세요.')
  }

  if (params.workoutNotes.length > 2000) {
    throw new Error('운동 기록은 2000자 이하로 입력해 주세요.')
  }

  // ============================================
  // 2. 운동 기록 저장 RPC 호출
  // ============================================

  const { error } = await supabase.rpc('save_session_workout_record', {
    p_attendance_id: params.attendanceId,
    p_workout_notes: params.workoutNotes.trim() || null,

    // 출석 상태를 전달하지 않으면 기록만 저장
    // 전달하면 기록과 출석 상태를 함께 저장
    p_new_status: params.newStatus ?? null,
  })

  if (error) {
    throw error
  }
}

// ============================================
// 이전 운동 기록 조회
// ============================================

// 화면에서 사용하는 이전 운동 기록
export interface PreviousWorkoutRecord {
  attendanceId: string
  sessionId: string
  startsAt: string
  sessionType: SessionType
  companyName: string
  workoutNotes: string
}

// DB 조회 함수가 반환하는 데이터
interface PreviousWorkoutRecordRow {
  attendance_id: string
  session_id: string
  starts_at: string
  session_type: SessionType
  company_name: string
  workout_notes: string
}

// 이전 운동 기록 조회 요청 데이터
export interface GetPreviousWorkoutRecordsParams {
  attendanceId: string
  offset?: number
  signal?: AbortSignal
}

// 이전 운동 기록 한 페이지와 다음 조회 위치
export interface PreviousWorkoutRecordsPage {
  records: PreviousWorkoutRecord[]
  nextOffset: number | undefined
}

const PREVIOUS_WORKOUT_PAGE_SIZE = 3

// 현재 수업보다 이전인 동일 회원의 운동 기록을 3건씩 조회
export async function getPreviousWorkoutRecords(
  params: GetPreviousWorkoutRecordsParams,
): Promise<PreviousWorkoutRecordsPage> {
  if (!params.attendanceId) {
    throw new Error('수업 참여 기록을 선택해 주세요.')
  }

  const offset = params.offset ?? 0

  if (!Number.isSafeInteger(offset) || offset < 0) {
    throw new Error('운동 기록 조회 위치를 확인해 주세요.')
  }

  // 1건을 더 조회하여 다음 기록이 실제로 있는지 확인
  // 표시할 기록이 정확히 3건이어도 불필요한 더 보기 버튼이 나타나지 않음
  let request = supabase.rpc('get_previous_workout_records', {
    p_attendance_id: params.attendanceId,
    p_page_size: PREVIOUS_WORKOUT_PAGE_SIZE + 1,
    p_offset: offset,
  })

  // 다른 회원으로 전환할 때 이전 조회를 취소할 수 있도록 지원
  if (params.signal) {
    request = request.abortSignal(params.signal)
  }

  const { data, error } = await request

  if (error) throw error

  const rows = (data ?? []) as PreviousWorkoutRecordRow[]

  // DB의 snake_case를 화면에서 사용하는 camelCase로 변환
  const records = rows.slice(0, PREVIOUS_WORKOUT_PAGE_SIZE).map((row) => ({
    attendanceId: row.attendance_id,
    sessionId: row.session_id,
    startsAt: row.starts_at,
    sessionType: row.session_type,
    companyName: row.company_name,
    workoutNotes: row.workout_notes,
  }))

  return {
    records,
    // 추가 확인용 1건은 다음 페이지에서 다시 조회하여 빠짐없이 표시
    nextOffset:
      rows.length > PREVIOUS_WORKOUT_PAGE_SIZE ? offset + PREVIOUS_WORKOUT_PAGE_SIZE : undefined,
  }
}
