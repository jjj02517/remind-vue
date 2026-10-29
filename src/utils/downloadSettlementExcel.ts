import ExcelJS from 'exceljs'

import { getMonthlySettlementDetails, type MonthlySettlementDetail } from '@/api/settlementDetails'

// 정산 엑셀 다운로드 조건
export interface DownloadSettlementExcelParams {
  year: number
  month: number
  companyId?: string | null
}

// 엑셀 요약 데이터
interface SettlementExcelSummary {
  companyId: string
  companyName: string
  currencyCode: string
  confirmedCount: number
  confirmedAmount: number
  scheduledCount: number
  scheduledAmount: number
  excludedCount: number
  unpricedCount: number
}

// 기본 통화는 원화로 표시
function normalizeCurrency(currencyCode: string) {
  if (!currencyCode || currencyCode === 'UNSET') {
    return 'KRW'
  }

  return currencyCode
}

// 한국 시간 기준 수업 날짜 표시
function formatSessionDate(value: string) {
  const date = new Date(value)

  if (Number.isNaN(date.getTime())) {
    return '-'
  }

  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    hourCycle: 'h23',
  }).formatToParts(date)

  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]))

  return `${values.year}-${values.month}-${values.day} ${values.hour}:${values.minute}`
}

// 수업 유형
function getSessionTypeLabel(type: string) {
  switch (type) {
    case 'pt':
      return 'PT'
    case 'group':
      return '그룹'
    default:
      return type
  }
}

// 출석 상태
function getAttendanceLabel(status: string) {
  switch (status) {
    case 'attended':
      return '출석'
    case 'no_show':
      return '노쇼'
    case 'same_day_cancelled':
      return '당일 취소'
    case 'cancelled':
      return '일반 취소'
    case 'scheduled':
      return '예약'
    default:
      return status
  }
}

// 정산 분류
function getCalculationLabel(status: string) {
  switch (status) {
    case 'confirmed':
      return '확정'
    case 'scheduled':
      return '예정'
    case 'excluded':
      return '제외'
    default:
      return status
  }
}

// 근무처와 통화별 정산 요약 계산
function createSettlementSummaries(details: MonthlySettlementDetail[]): SettlementExcelSummary[] {
  const summaryMap = new Map<string, SettlementExcelSummary>()

  for (const row of details) {
    const currencyCode = normalizeCurrency(row.currency_code)
    const key = `${row.company_id}:${currencyCode}`

    let summary = summaryMap.get(key)

    if (!summary) {
      summary = {
        companyId: row.company_id,
        companyName: row.company_name,
        currencyCode,
        confirmedCount: 0,
        confirmedAmount: 0,
        scheduledCount: 0,
        scheduledAmount: 0,
        excludedCount: 0,
        unpricedCount: 0,
      }

      summaryMap.set(key, summary)
    }

    if (row.calculation_status === 'confirmed') {
      summary.confirmedCount += 1

      if (row.settlement_amount === null) {
        summary.unpricedCount += 1
      } else {
        summary.confirmedAmount += row.settlement_amount
      }
    } else if (row.calculation_status === 'scheduled') {
      summary.scheduledCount += 1

      if (row.settlement_amount === null) {
        summary.unpricedCount += 1
      } else {
        summary.scheduledAmount += row.settlement_amount
      }
    } else {
      summary.excludedCount += 1
    }
  }

  return Array.from(summaryMap.values()).sort(
    (a, b) =>
      a.companyName.localeCompare(b.companyName, 'ko') ||
      a.currencyCode.localeCompare(b.currencyCode),
  )
}

// 시트 제목 및 헤더 공통 스타일
function styleWorksheet(
  sheet: ExcelJS.Worksheet,
  title: string,
  subtitle: string,
  columnCount: number,
) {
  sheet.mergeCells(1, 1, 1, columnCount)
  sheet.mergeCells(2, 1, 2, columnCount)

  const titleCell = sheet.getCell(1, 1)
  titleCell.value = title
  titleCell.font = {
    name: '맑은 고딕',
    size: 16,
    bold: true,
    color: { argb: 'FFFFFFFF' },
  }
  titleCell.fill = {
    type: 'pattern',
    pattern: 'solid',
    fgColor: { argb: 'FF1E293B' },
  }
  titleCell.alignment = {
    vertical: 'middle',
    indent: 1,
  }

  sheet.getRow(1).height = 38

  const subtitleCell = sheet.getCell(2, 1)
  subtitleCell.value = subtitle
  subtitleCell.font = {
    name: '맑은 고딕',
    size: 10,
    color: { argb: 'FF475569' },
  }
  subtitleCell.alignment = {
    vertical: 'middle',
    indent: 1,
  }

  sheet.getRow(2).height = 28
  sheet.getRow(3).height = 12

  // 헤더는 4번째 행
  const header = sheet.getRow(4)
  header.height = 28

  header.eachCell((cell) => {
    cell.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FFE2E8F0' },
    }
    cell.font = {
      name: '맑은 고딕',
      bold: true,
      size: 10,
      color: { argb: 'FF334155' },
    }
    cell.alignment = {
      horizontal: 'center',
      vertical: 'middle',
    }
  })

  // 제목과 헤더 고정
  sheet.views = [
    {
      state: 'frozen',
      ySplit: 4,
    },
  ]

  sheet.autoFilter = {
    from: { row: 4, column: 1 },
    to: { row: 4, column: columnCount },
  }
}

// 데이터 행 공통 스타일
function styleDataRows(sheet: ExcelJS.Worksheet, startRow: number) {
  for (let rowNumber = startRow; rowNumber <= sheet.rowCount; rowNumber++) {
    const row = sheet.getRow(rowNumber)
    row.height = 23

    row.eachCell((cell) => {
      cell.font = {
        name: '맑은 고딕',
        size: 10,
        color: { argb: 'FF334155' },
      }
      cell.alignment = {
        vertical: 'middle',
      }

      if (rowNumber % 2 === 0) {
        cell.fill = {
          type: 'pattern',
          pattern: 'solid',
          fgColor: { argb: 'FFF8FAFC' },
        }
      }
    })
  }
}

// 정산 엑셀 다운로드
export async function downloadSettlementExcel({
  year,
  month,
  companyId = null,
}: DownloadSettlementExcelParams): Promise<void> {
  // 조회 연월 검사
  if (
    !Number.isInteger(year) ||
    year < 1900 ||
    year > 9999 ||
    !Number.isInteger(month) ||
    month < 1 ||
    month > 12
  ) {
    throw new Error('올바른 조회 연도와 월을 선택해 주세요.')
  }

  // 현재 설정된 수업 및 정산 기준으로 최신 상세 데이터 조회
  const details = await getMonthlySettlementDetails({
    year,
    month,
    companyId,
  })

  if (details.length === 0) {
    throw new Error('다운로드할 정산 내역이 없습니다.')
  }

  const summaries = createSettlementSummaries(details)

  const workbook = new ExcelJS.Workbook()
  workbook.creator = 'Remind PT'
  workbook.created = new Date()

  const monthLabel = `${year}년 ${month}월`

  // 정산 요약 시트
  const summarySheet = workbook.addWorksheet('정산 요약')

  summarySheet.columns = [
    { key: 'company', width: 30 },
    { key: 'currency', width: 14 },
    { key: 'confirmedCount', width: 16 },
    { key: 'confirmedAmount', width: 20 },
    { key: 'scheduledCount', width: 16 },
    { key: 'scheduledAmount', width: 20 },
    { key: 'excludedCount', width: 18 },
    { key: 'unpricedCount', width: 18 },
  ]

  summarySheet.getRow(4).values = [
    '근무처',
    '통화',
    '확정 건수',
    '확정 정산액',
    '예정 건수',
    '예정 정산액',
    '정산 제외 건수',
    '단가 미설정 건수',
  ]

  for (const summary of summaries) {
    summarySheet.addRow({
      company: summary.companyName,
      currency: summary.currencyCode,
      confirmedCount: summary.confirmedCount,
      confirmedAmount: summary.confirmedAmount,
      scheduledCount: summary.scheduledCount,
      scheduledAmount: summary.scheduledAmount,
      excludedCount: summary.excludedCount,
      unpricedCount: summary.unpricedCount,
    })
  }

  styleWorksheet(
    summarySheet,
    'Remind PT 월별 정산 요약',
    `${monthLabel} · 수업 기록 및 근무처별 정산 기준 적용`,
    8,
  )

  styleDataRows(summarySheet, 5)

  // 금액 셀을 숫자로 유지해 엑셀에서 합계 계산 가능
  for (let i = 5; i <= summarySheet.rowCount; i++) {
    for (const column of [4, 6]) {
      const cell = summarySheet.getCell(i, column)
      cell.numFmt = '#,##0'
      cell.alignment = { horizontal: 'right' }
    }

    const unpricedCell = summarySheet.getCell(i, 8)

    if (Number(unpricedCell.value) > 0) {
      unpricedCell.font = {
        bold: true,
        color: { argb: 'FFB45309' },
      }
    }
  }

  // 수업별 상세 내역 시트
  const detailSheet = workbook.addWorksheet('수업별 상세')

  detailSheet.columns = [
    { key: 'date', width: 22 },
    { key: 'company', width: 30 },
    { key: 'member', width: 18 },
    { key: 'sessionType', width: 12 },
    { key: 'attendance', width: 16 },
    { key: 'calculation', width: 14 },
    { key: 'unitRate', width: 19 },
    { key: 'amount', width: 19 },
    { key: 'currency', width: 12 },
    { key: 'rateDate', width: 19 },
    { key: 'policyDate', width: 19 },
  ]

  detailSheet.getRow(4).values = [
    '수업 날짜',
    '근무처',
    '회원',
    '수업 유형',
    '출석 상태',
    '정산 분류',
    '적용 단가',
    '정산 금액',
    '통화',
    '단가 적용 시작일',
    '정산 기준 적용일',
  ]

  for (const detail of details) {
    detailSheet.addRow({
      date: formatSessionDate(detail.starts_at),
      company: detail.company_name,
      member: detail.member_name,
      sessionType: getSessionTypeLabel(detail.session_type),
      attendance: getAttendanceLabel(detail.attendance_status),
      calculation: getCalculationLabel(detail.calculation_status),
      unitRate: detail.unit_rate === null ? '미설정' : detail.unit_rate,
      amount: detail.settlement_amount === null ? '단가 미설정' : detail.settlement_amount,
      currency: normalizeCurrency(detail.currency_code),
      rateDate: detail.rate_effective_from ?? '-',
      policyDate: detail.policy_effective_from ?? '-',
    })
  }

  styleWorksheet(
    detailSheet,
    'Remind PT 수업별 정산 내역',
    `${monthLabel} · 그룹 수업은 참여 회원별로 한 건씩 집계`,
    11,
  )

  styleDataRows(detailSheet, 5)

  for (let i = 5; i <= detailSheet.rowCount; i++) {
    for (const column of [7, 8]) {
      const cell = detailSheet.getCell(i, column)

      if (typeof cell.value === 'number') {
        cell.numFmt = '#,##0'
        cell.alignment = { horizontal: 'right' }
      }
    }

    const statusCell = detailSheet.getCell(i, 6)
    const amountCell = detailSheet.getCell(i, 8)

    if (statusCell.value === '제외') {
      statusCell.font = {
        color: { argb: 'FF94A3B8' },
      }
    }

    if (amountCell.value === '단가 미설정') {
      amountCell.font = {
        bold: true,
        color: { argb: 'FFB45309' },
      }
    }
  }

  // 엑셀 파일 생성
  const buffer = await workbook.xlsx.writeBuffer()

  // ExcelJS의 Buffer 타입을 브라우저용 Uint8Array로 변환
  const bytes = new Uint8Array(buffer as unknown as ArrayBuffer)

  const blob = new Blob([bytes.buffer as ArrayBuffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })

  // 다운로드 파일명
  const companyLabel = companyId ? (details[0]?.company_name ?? 'company') : '전체근무처'

  const safeCompanyLabel = companyLabel.replace(/[\\/:*?"<>|]/g, '_').slice(0, 50)

  const monthText = String(month).padStart(2, '0')

  const fileName = `RemindPT_정산_${year}-${monthText}_${safeCompanyLabel}.xlsx`

  // 브라우저 다운로드 실행
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')

  link.href = url
  link.download = fileName

  document.body.appendChild(link)
  link.click()
  link.remove()

  window.setTimeout(() => {
    URL.revokeObjectURL(url)
  }, 1000)
}
