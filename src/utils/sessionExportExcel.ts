import type { Workbook, Worksheet } from 'exceljs'
import type { MonthlySessionExportData } from '@/api/sessionExports'
import type { AttendanceStatus, SessionStatus } from '@/api/sessions'

// ============================================
// 엑셀 표시 설정
// ============================================

interface ExportColumn {
  header: string
  width: number
  numFmt?: string
}

type ExportCellValue = string | number | Date | null

const HEADER_ROW = 5
const EXCEL_MIME_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'

const sessionLabels: Record<SessionStatus, string> = {
  scheduled: '예정',
  completed: '처리 완료',
  cancelled: '취소',
}

const attendanceLabels: Record<AttendanceStatus, string> = {
  scheduled: '예정',
  attended: '출석',
  no_show: '노쇼',
  same_day_cancelled: '당일 취소',
  cancelled: '일반 취소',
}

// 엑셀은 시간대 정보를 저장하지 않으므로 한국 날짜·시각을 따로 구성
const koreaDateTimeFormatter = new Intl.DateTimeFormat('en-GB', {
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

  if (Number.isNaN(date.getTime())) {
    throw new Error('수업 날짜를 확인하지 못했습니다. 다시 시도해 주세요.')
  }

  const parts = koreaDateTimeFormatter.formatToParts(date)
  const get = (type: string) => Number(parts.find((part) => part.type === type)?.value)

  // UTC 필드에 한국 시각을 담아 ExcelJS의 날짜 직렬화 시 9시간 오차 방지
  return new Date(
    Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second')),
  )
}

// ============================================
// 시트 공통 서식
// ============================================

function createSheet(
  workbook: Workbook,
  name: string,
  period: string,
  columns: ExportColumn[],
  note: string,
): Worksheet {
  const sheet = workbook.addWorksheet(name)

  sheet.columns = columns.map((column) => ({
    width: column.width,
    style: {
      font: { name: '맑은 고딕', size: 11 },
      alignment: { vertical: 'top', wrapText: true },
    },
  }))

  sheet.views = [{ state: 'frozen', ySplit: HEADER_ROW, showGridLines: false }]

  sheet.mergeCells(1, 1, 1, columns.length)
  sheet.getCell('A1').value = `Remind PT ${name}`
  sheet.getCell('A1').font = {
    name: '맑은 고딕',
    size: 18,
    bold: true,
    color: { argb: 'FF1E3A5F' },
  }
  sheet.getRow(1).height = 34

  sheet.mergeCells(2, 1, 2, columns.length)
  sheet.getCell('A2').value = period
  sheet.getCell('A2').font = { name: '맑은 고딕', size: 11, bold: true }
  sheet.getRow(2).height = 24

  sheet.mergeCells(3, 1, 3, columns.length)
  sheet.getCell('A3').value = note
  sheet.getCell('A3').font = {
    name: '맑은 고딕',
    size: 10,
    color: { argb: 'FF64748B' },
  }
  sheet.getRow(3).height = 32
  sheet.getRow(4).height = 8

  const header = sheet.getRow(HEADER_ROW)
  header.values = columns.map((column) => column.header)
  header.height = 32
  header.eachCell((cell) => {
    cell.font = {
      name: '맑은 고딕',
      size: 11,
      bold: true,
      color: { argb: 'FFFFFFFF' },
    }
    cell.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FF1E3A5F' },
    }
    cell.alignment = {
      vertical: 'middle',
      horizontal: 'center',
      wrapText: true,
    }
  })

  return sheet
}

// 줄바꿈과 한글 글자 폭을 고려해 행 높이 계산
function getTextLineCount(text: string, width: number): number {
  const usableWidth = Math.max(1, width - 2)

  return text.split(/\r\n|\r|\n/).reduce((total, line) => {
    const lineWidth = Array.from(line).reduce(
      (sum, character) => sum + ((character.codePointAt(0) ?? 0) > 255 ? 2 : 1),
      0,
    )

    return total + Math.max(1, Math.ceil(lineWidth / usableWidth))
  }, 0)
}

function addDataRow(sheet: Worksheet, columns: ExportColumn[], values: ExportCellValue[]) {
  const row = sheet.addRow(values)
  let lineCount = 1

  values.forEach((value, index) => {
    const cell = row.getCell(index + 1)
    const column = columns[index]

    cell.alignment = {
      vertical: 'top',
      horizontal: typeof value === 'number' ? 'right' : 'left',
      wrapText: true,
    }
    cell.border = {
      bottom: { style: 'hair', color: { argb: 'FFE2E8F0' } },
    }

    if (row.number % 2 === 0) {
      cell.fill = {
        type: 'pattern',
        pattern: 'solid',
        fgColor: { argb: 'FFF8FAFC' },
      }
    }

    if (column?.numFmt) cell.numFmt = column.numFmt

    if (typeof value === 'string') {
      lineCount = Math.max(lineCount, getTextLineCount(value, column?.width ?? 20))
    }
  })

  // Excel의 최대 행 높이 안에서 표시하고 기록 원문은 그대로 저장
  row.height = Math.min(409, Math.max(28, lineCount * 16 + 8))
}

function finishTableSheet(sheet: Worksheet, columnCount: number, recordCount: number) {
  if (recordCount > 0) {
    sheet.autoFilter = {
      from: { row: HEADER_ROW, column: 1 },
      to: { row: HEADER_ROW + recordCount, column: columnCount },
    }
    return
  }

  sheet.mergeCells(HEADER_ROW + 1, 1, HEADER_ROW + 1, columnCount)
  const cell = sheet.getCell(HEADER_ROW + 1, 1)
  cell.value = '선택한 월에 표시할 내역이 없습니다.'
  cell.font = {
    name: '맑은 고딕',
    size: 11,
    color: { argb: 'FF64748B' },
  }
  cell.alignment = {
    vertical: 'middle',
    horizontal: 'center',
    wrapText: true,
  }
  sheet.getRow(HEADER_ROW + 1).height = 32
}

// ============================================
// 월별 엑셀 파일 생성 및 다운로드
// ============================================

export async function downloadMonthlySessionExcel(data: MonthlySessionExportData): Promise<void> {
  // 다운로드할 때만 라이브러리를 불러옴
  const { default: ExcelJS } = await import('exceljs')
  const workbook = new ExcelJS.Workbook()
  workbook.creator = 'Remind PT'
  workbook.created = new Date()

  const period = `${data.year}년 ${data.month}월 (한국 시간 기준)`
  const summary = data.summary

  // 전체 월간 수업 현황
  const summaryColumns: ExportColumn[] = [
    { header: '구분', width: 16 },
    { header: '항목', width: 24 },
    { header: '건수', width: 14, numFmt: '#,##0' },
    { header: '단위', width: 10 },
  ]
  const summarySheet = createSheet(
    workbook,
    '월간 수업 현황',
    period,
    summaryColumns,
    '수업 횟수와 회원별 참여 기록 건수를 구분하여 집계합니다.',
  )

  const summaryRows: ExportCellValue[][] = [
    ['수업', '전체 수업', summary.totalSessions, '회'],
    ['수업', 'PT', summary.ptSessions, '회'],
    ['수업', '그룹', summary.groupSessions, '회'],
    ['수업', '처리 완료', summary.completedSessions, '회'],
    ['수업', '예정', summary.scheduledSessions, '회'],
    ['수업', '취소', summary.cancelledSessions, '회'],
    ['회원별 참여', '전체 참여 기록', data.recordCount, '건'],
    ['회원별 참여', '출석', summary.attendedCount, '건'],
    ['회원별 참여', '노쇼', summary.noShowCount, '건'],
    ['회원별 참여', '당일 취소', summary.sameDayCancelledCount, '건'],
    ['회원별 참여', '일반 취소', summary.attendanceCancelledCount, '건'],
    ['회원별 참여', '미처리', summary.attendanceScheduledCount, '건'],
  ]
  summaryRows.forEach((row) => addDataRow(summarySheet, summaryColumns, row))

  // 근무처별 월간 수업 현황
  const companyColumns: ExportColumn[] = [
    { header: '근무처', width: 26 },
    { header: '종류', width: 14 },
    { header: '운영 상태', width: 12 },
    { header: '전체 수업(회)', width: 18, numFmt: '#,##0' },
    { header: 'PT(회)', width: 12, numFmt: '#,##0' },
    { header: '그룹(회)', width: 12, numFmt: '#,##0' },
    { header: '처리 완료(회)', width: 18, numFmt: '#,##0' },
    { header: '예정(회)', width: 12, numFmt: '#,##0' },
    { header: '취소(회)', width: 12, numFmt: '#,##0' },
  ]
  const companySheet = createSheet(
    workbook,
    '근무처별 월간 현황',
    period,
    companyColumns,
    '활성 근무처와 선택한 월에 수업이 있는 보관 근무처를 표시합니다.',
  )

  data.companies.forEach((company) => {
    addDataRow(companySheet, companyColumns, [
      company.companyName,
      company.companyType === 'personal' ? '개인 고객' : '근무처',
      company.isActive ? '활성' : '보관',
      company.totalSessions,
      company.ptSessions,
      company.groupSessions,
      company.completedSessions,
      company.scheduledSessions,
      company.cancelledSessions,
    ])
  })
  finishTableSheet(companySheet, companyColumns.length, data.companies.length)

  // 회원별 수업 기록: 참여 회원 한 명당 한 행
  const recordColumns: ExportColumn[] = [
    { header: '수업 시작', width: 23, numFmt: 'yyyy-mm-dd hh:mm' },
    { header: '수업 종료', width: 23, numFmt: 'yyyy-mm-dd hh:mm' },
    { header: '근무처', width: 26 },
    { header: '회원명', width: 16 },
    { header: '수업 종류', width: 12 },
    { header: '수업 상태', width: 14 },
    { header: '출석 상태', width: 14 },
    { header: '차감(회)', width: 12, numFmt: '#,##0' },
    { header: '수업 계획', width: 44 },
    { header: '실제 운동 기록', width: 52 },
  ]
  const recordSheet = createSheet(
    workbook,
    '회원별 수업 기록',
    period,
    recordColumns,
    '한 행은 회원 한 명의 수업 참여 기록입니다. 차감 횟수는 현재 출석 상태 기준입니다.',
  )

  data.records.forEach((record) => {
    addDataRow(recordSheet, recordColumns, [
      toKoreaExcelDate(record.startsAt),
      toKoreaExcelDate(record.endsAt),
      record.companyName,
      record.memberName,
      record.sessionType === 'pt' ? 'PT' : '그룹',
      sessionLabels[record.sessionStatus],
      attendanceLabels[record.attendanceStatus],
      record.deductedSessions,
      record.sessionNotes ?? '',
      record.workoutNotes ?? '',
    ])
  })
  finishTableSheet(recordSheet, recordColumns.length, data.records.length)

  // 엑셀 파일을 생성하고 브라우저 다운로드로 전달
  const buffer = await workbook.xlsx.writeBuffer()
  const bytes = new Uint8Array(buffer)
  const blob = new Blob([bytes.buffer], { type: EXCEL_MIME_TYPE })
  const link = document.createElement('a')
  const url = URL.createObjectURL(blob)

  try {
    link.href = url
    link.download = `RemindPT_${data.year}-${String(data.month).padStart(2, '0')}_수업내역.xlsx`
    document.body.appendChild(link)
    link.click()
  } finally {
    link.remove()
    // 브라우저가 다운로드를 시작할 시간을 둔 뒤 임시 URL 해제
    setTimeout(() => URL.revokeObjectURL(url), 60_000)
  }
}
