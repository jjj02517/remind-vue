import type { Workbook, Worksheet } from 'exceljs'
import type { MemberExportData, MemberExportPackage } from '@/api/memberExports'
import type { AttendanceStatus, SessionStatus } from '@/api/sessions'
import { PACKAGE_TYPE_LABELS } from '@/types/package'
import { getPackagePauseStatusLabel } from '@/utils/packagePauseStatus'

interface ExportColumn {
  header: string
  width: number
  numFmt?: string
}

type ExportValue = string | number | Date | null

const DATE_FORMAT = 'yyyy-mm-dd'
const DATETIME_FORMAT = 'yyyy-mm-dd hh:mm'

const attendanceLabels: Record<AttendanceStatus, string> = {
  scheduled: '예정',
  attended: '출석',
  no_show: '노쇼',
  same_day_cancelled: '당일 취소',
  cancelled: '일반 취소',
}

const sessionStatusLabels: Record<SessionStatus, string> = {
  scheduled: '예정',
  completed: '완료',
  cancelled: '취소',
}

// 실제 시각을 한국 시각으로 바꾼 뒤 엑셀에 표시할 날짜 값 생성
const koreaDateFormatter = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Seoul',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hourCycle: 'h23',
})

function toKoreaExcelDate(value: string): Date {
  const date = new Date(value)

  if (!Number.isFinite(date.getTime())) {
    throw new Error('다운로드 데이터의 날짜를 확인해 주세요.')
  }

  const parts = new Map(
    koreaDateFormatter.formatToParts(date).map((part) => [part.type, part.value]),
  )

  // 엑셀은 시간대 정보가 없으므로 한국의 날짜·시각을 그대로 저장
  return new Date(
    Date.UTC(
      Number(parts.get('year')),
      Number(parts.get('month')) - 1,
      Number(parts.get('day')),
      Number(parts.get('hour')),
      Number(parts.get('minute')),
      Number(parts.get('second')),
    ),
  )
}

// DB의 DATE 값은 시간대 변환 없이 날짜 그대로 저장
function toExcelDate(value: string | null): Date | null {
  if (value === null) return null

  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error('다운로드 데이터의 날짜를 확인해 주세요.')
  }

  const date = new Date(`${value}T00:00:00Z`)

  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new Error('다운로드 데이터의 날짜를 확인해 주세요.')
  }

  return date
}

// 제목, 안내 문구, 표 머리글과 고정 행 설정
function createSheet(
  workbook: Workbook,
  name: string,
  data: MemberExportData,
  columns: ExportColumn[],
  note: string,
): Worksheet {
  const sheet = workbook.addWorksheet(name)
  sheet.properties.defaultRowHeight = 24
  sheet.views = [{ state: 'frozen', ySplit: 5, showGridLines: false }]
  sheet.pageSetup = { orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0 }
  sheet.pageSetup.printTitlesRow = '1:5'

  columns.forEach((column, index) => {
    const sheetColumn = sheet.getColumn(index + 1)
    sheetColumn.width = column.width
    if (column.numFmt) sheetColumn.numFmt = column.numFmt
  })

  for (const row of [1, 2, 3]) {
    sheet.mergeCells(row, 1, row, columns.length)
  }

  sheet.getCell('A1').value = `Remind PT · ${name}`
  sheet.getCell('A1').font = {
    name: '맑은 고딕',
    size: 18,
    bold: true,
    color: { argb: 'FF0F172A' },
  }
  sheet.getRow(1).height = 36
  sheet.getCell('A2').value =
    `${data.member.name} · 전체 근무처 · 전체 기간 · 기준일 ${data.asOfDate} (한국 시간)`
  sheet.getCell('A3').value = note

  for (const row of [2, 3]) {
    const cell = sheet.getCell(row, 1)
    cell.font = { name: '맑은 고딕', size: 10, color: { argb: 'FF64748B' } }
    cell.alignment = { vertical: 'middle', wrapText: true }
    sheet.getRow(row).height = 32
  }

  const header = sheet.getRow(5)
  header.values = columns.map((column) => column.header)
  header.height = 30
  header.eachCell((cell) => {
    cell.font = { name: '맑은 고딕', size: 11, bold: true, color: { argb: 'FFFFFFFF' } }
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1E3A5F' } }
    cell.alignment = { vertical: 'middle', wrapText: true }
  })

  return sheet
}

function getLineCount(value: ExportValue, width: number): number {
  if (typeof value !== 'string') return 1

  const usableWidth = Math.max(8, width - 2)
  return value.split(/\r\n|\r|\n/).reduce((sum, line) => {
    const length = Array.from(line).reduce(
      (total, char) => total + (char.charCodeAt(0) > 127 ? 2 : 1),
      0,
    )
    return sum + Math.max(1, Math.ceil(length / usableWidth))
  }, 0)
}

// 문자열은 텍스트로, 횟수와 날짜는 실제 숫자·날짜 값으로 저장
function addDataRow(sheet: Worksheet, values: ExportValue[]) {
  const row = sheet.addRow(values)
  let lines = 1

  values.forEach((value, index) => {
    const cell = row.getCell(index + 1)
    cell.font = { name: '맑은 고딕', size: 11, color: { argb: 'FF334155' } }
    cell.alignment = { vertical: 'top', wrapText: true }
    cell.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: row.number % 2 === 0 ? 'FFF1F5F9' : 'FFFFFFFF' },
    }
    lines = Math.max(lines, getLineCount(value, sheet.getColumn(index + 1).width ?? 15))
  })

  row.height = Math.min(409, Math.max(28, lines * 17 + 10))
  return row
}

function finishTable(sheet: Worksheet, columnCount: number, emptyMessage: string) {
  if (sheet.rowCount > 5) {
    sheet.autoFilter = {
      from: { row: 5, column: 1 },
      to: { row: sheet.rowCount, column: columnCount },
    }
    return
  }

  sheet.mergeCells(6, 1, 6, columnCount)
  sheet.getCell('A6').value = emptyMessage
  sheet.getCell('A6').font = { name: '맑은 고딕', size: 11, color: { argb: 'FF64748B' } }
  sheet.getCell('A6').alignment = { vertical: 'middle', wrapText: true }
  sheet.getRow(6).height = 36
}

function getCompanyLabel(name: string | null, isActive: boolean | null): string {
  if (name === null) return '근무처 미지정'
  return isActive === false ? `${name} (보관)` : name
}

// 회원 상세 이용권 카드와 같은 우선순위로 현재 상태 표시
function getPackageStatusLabel(
  pkg: MemberExportPackage,
  today: string,
  pausedPackageIds: Set<string>,
): string {
  if (pkg.status === 'completed') return '사용 완료'
  if (pkg.status === 'expired') return '기간 만료'
  if (pkg.status === 'cancelled') return '취소'
  if (pkg.endsOn && pkg.endsOn < today) return '기간 만료'
  if (pkg.usageType === 'count' && (pkg.remainingSessions ?? 0) <= 0) return '사용 완료'
  if (pkg.startsOn && today < pkg.startsOn) return '이용 예정'
  if (pkg.usageType === 'period' && (!pkg.startsOn || !pkg.endsOn)) return '상태 확인 필요'
  if (pausedPackageIds.has(pkg.id)) return '일시정지 중'
  return '이용 중'
}

function getSafeFileName(name: string): string {
  return (
    name
      .replace(/[\p{Cc}<>:"/\\|?*]/gu, '_')
      .replace(/[.\s]+$/g, '')
      .trim()
      .slice(0, 60) || '회원'
  )
}

// 회원의 전체 내역을 4개 시트로 구성해 다운로드
export async function downloadMemberExcel(data: MemberExportData): Promise<void> {
  const { default: ExcelJS } = await import('exceljs')
  const workbook = new ExcelJS.Workbook()
  workbook.creator = 'Remind PT'
  workbook.created = new Date(data.exportedAt)
  workbook.modified = new Date(data.exportedAt)

  // 이용권 번호는 이 파일 안에서 시트 간 연결에 사용
  const packagesById = new Map(data.packages.map((pkg) => [pkg.id, pkg]))
  const packageNumbers = new Map(data.packages.map((pkg, index) => [pkg.id, index + 1]))
  const pausedPackageIds = new Set(
    data.pauses.filter((pause) => pause.status === 'paused').map((pause) => pause.packageId),
  )

  function getPackageNumber(packageId: string | null): number | null {
    if (packageId === null) return null
    const number = packageNumbers.get(packageId)
    if (number === undefined) throw new Error('연결된 이용권 정보를 확인하지 못했습니다.')
    return number
  }

  // 회원 기본정보
  const memberSheet = createSheet(
    workbook,
    '회원 기본정보',
    data,
    [
      { header: '항목', width: 26 },
      { header: '내용', width: 100 },
    ],
    '회원 상태와 이용권 잔여 횟수는 조회 시점을 기준으로 표시합니다.',
  )

  const memberStatusLabels = { active: '활동 중', inactive: '비활성', archived: '보관' }
  addDataRow(memberSheet, ['회원명', data.member.name])
  const phoneRow = addDataRow(memberSheet, ['연락처', data.member.phone])
  phoneRow.getCell(2).numFmt = '@'
  addDataRow(memberSheet, ['회원 상태', memberStatusLabels[data.member.status]])
  const registeredRow = addDataRow(memberSheet, [
    '회원 등록일',
    toKoreaExcelDate(data.member.createdAt),
  ])
  registeredRow.getCell(2).numFmt = DATETIME_FORMAT
  addDataRow(memberSheet, [
    '연결된 근무처',
    data.companies
      .map((company) => {
        const type = company.companyType === 'personal' ? '개인' : '근무처'
        return `[${type}] ${getCompanyLabel(company.companyName, company.isActive)}`
      })
      .join('\n') || '연결된 근무처 없음',
  ])
  addDataRow(memberSheet, ['이용권 내역 수', data.packageCount])
  addDataRow(memberSheet, ['일시정지 내역 수', data.pauseCount])
  addDataRow(memberSheet, ['수업·운동 기록 수', data.recordCount])
  const basisRow = addDataRow(memberSheet, ['상태 계산 기준일', toExcelDate(data.asOfDate)])
  basisRow.getCell(2).numFmt = DATE_FORMAT
  const exportRow = addDataRow(memberSheet, [
    '조회 시각 (한국 시간)',
    toKoreaExcelDate(data.exportedAt),
  ])
  exportRow.getCell(2).numFmt = DATETIME_FORMAT
  addDataRow(memberSheet, ['조회 범위', '전체 근무처 · 전체 기간 (삭제된 수업 제외)'])

  // 지난 이용권과 보관 근무처의 이용권도 모두 포함
  const packageColumns: ExportColumn[] = [
    { header: '이용권 번호', width: 12, numFmt: '0' },
    { header: '근무처', width: 26 },
    { header: '이용권 종류', width: 18 },
    { header: '관리 방식', width: 12 },
    { header: '현재 상태', width: 16 },
    { header: '총 횟수', width: 12, numFmt: '0' },
    { header: '잔여 횟수', width: 12, numFmt: '0' },
    { header: '시작일', width: 15, numFmt: DATE_FORMAT },
    { header: '종료일', width: 15, numFmt: DATE_FORMAT },
    { header: '등록일', width: 21, numFmt: DATETIME_FORMAT },
  ]
  const packageSheet = createSheet(
    workbook,
    '이용권 내역',
    data,
    packageColumns,
    '현재 잔여 횟수를 표시합니다. 기간제 횟수는 빈칸이며, 이용권 번호로 다른 시트의 내역을 연결합니다.',
  )

  for (const pkg of data.packages) {
    addDataRow(packageSheet, [
      getPackageNumber(pkg.id),
      getCompanyLabel(pkg.companyName, pkg.companyIsActive),
      PACKAGE_TYPE_LABELS[pkg.packageType],
      pkg.usageType === 'count' ? '횟수제' : '기간제',
      getPackageStatusLabel(pkg, data.asOfDate, pausedPackageIds),
      pkg.totalSessions,
      pkg.remainingSessions,
      toExcelDate(pkg.startsOn),
      toExcelDate(pkg.endsOn),
      toKoreaExcelDate(pkg.createdAt),
    ])
  }
  finishTable(packageSheet, packageColumns.length, '등록된 이용권 내역이 없습니다.')

  // 취소된 예약과 조기 복귀한 내역도 포함
  const pauseColumns: ExportColumn[] = [
    { header: '이용권 번호', width: 12, numFmt: '0' },
    { header: '근무처', width: 26 },
    { header: '이용권 종류', width: 18 },
    { header: '일시정지 상태', width: 18 },
    { header: '시작일', width: 15, numFmt: DATE_FORMAT },
    { header: '예정 종료일', width: 15, numFmt: DATE_FORMAT },
    { header: '조기 복귀일', width: 15, numFmt: DATE_FORMAT },
    { header: '예약 취소 시각', width: 21, numFmt: DATETIME_FORMAT },
    { header: '사유', width: 40 },
    { header: '등록일', width: 21, numFmt: DATETIME_FORMAT },
  ]
  const pauseSheet = createSheet(
    workbook,
    '일시정지 내역',
    data,
    pauseColumns,
    '예약 취소와 조기 복귀를 포함한 전체 내역입니다. 시작일·종료일은 등록된 일시정지 예정 기간입니다.',
  )

  for (const pause of data.pauses) {
    const pkg = packagesById.get(pause.packageId)
    if (!pkg) throw new Error('일시정지 내역의 이용권 정보를 확인하지 못했습니다.')

    addDataRow(pauseSheet, [
      getPackageNumber(pause.packageId),
      getCompanyLabel(pkg.companyName, pkg.companyIsActive),
      PACKAGE_TYPE_LABELS[pkg.packageType],
      getPackagePauseStatusLabel(pause.status),
      toExcelDate(pause.startsOn),
      toExcelDate(pause.endsOn),
      toExcelDate(pause.resumedOn),
      pause.cancelledAt === null ? null : toKoreaExcelDate(pause.cancelledAt),
      pause.reason,
      toKoreaExcelDate(pause.createdAt),
    ])
  }
  finishTable(pauseSheet, pauseColumns.length, '등록된 일시정지 내역이 없습니다.')

  // 그룹 수업도 해당 회원의 출석·차감·운동 기록만 표시
  const recordColumns: ExportColumn[] = [
    { header: '수업 시작', width: 21, numFmt: DATETIME_FORMAT },
    { header: '수업 종료', width: 21, numFmt: DATETIME_FORMAT },
    { header: '근무처', width: 26 },
    { header: '수업 종류', width: 12 },
    { header: '수업 상태', width: 12 },
    { header: '출석 상태', width: 14 },
    { header: '차감 횟수', width: 12, numFmt: '0' },
    { header: '이용권 번호', width: 12, numFmt: '0' },
    { header: '수업 계획', width: 45 },
    { header: '운동 기록', width: 55 },
  ]
  const recordSheet = createSheet(
    workbook,
    '수업·운동 기록',
    data,
    recordColumns,
    '삭제된 수업은 제외합니다. 차감 횟수는 각 수업의 현재 출석 상태를 기준으로 표시합니다.',
  )

  for (const record of data.records) {
    addDataRow(recordSheet, [
      toKoreaExcelDate(record.startsAt),
      toKoreaExcelDate(record.endsAt),
      record.companyName,
      record.sessionType === 'pt' ? 'PT' : '그룹 수업',
      sessionStatusLabels[record.sessionStatus],
      attendanceLabels[record.attendanceStatus],
      record.deductedSessions,
      getPackageNumber(record.packageId),
      record.sessionNotes,
      record.workoutNotes,
    ])
  }
  finishTable(recordSheet, recordColumns.length, '등록된 수업·운동 기록이 없습니다.')

  const buffer = await workbook.xlsx.writeBuffer()
  const bytes = new Uint8Array(buffer)
  const blob = new Blob([bytes.buffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })
  const link = document.createElement('a')
  const url = URL.createObjectURL(blob)

  try {
    link.href = url
    link.download = `RemindPT_${getSafeFileName(data.member.name)}_회원내역_${data.asOfDate}.xlsx`
    document.body.appendChild(link)
    link.click()
  } finally {
    link.remove()
    // 브라우저가 파일을 읽을 수 있도록 잠시 후 URL 정리
    setTimeout(() => URL.revokeObjectURL(url), 60_000)
  }
}
