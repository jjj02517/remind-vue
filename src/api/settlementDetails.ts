import { supabase } from '@/lib/supabase'
import { getTrainerContext } from '@/api/trainerContext'

// 수업별 정산 상태
export type SettlementCalculationStatus = 'confirmed' | 'scheduled' | 'excluded'

// 수업별 정산 상세 데이터
export interface MonthlySettlementDetail {
  attendance_id: string
  session_id: string

  // 근무처 정보
  company_id: string
  company_name: string

  // 회원 정보
  member_id: string
  member_name: string

  // 수업 정보
  starts_at: string
  session_type: string
  session_status: string
  attendance_status: string

  // 정산 분류
  calculation_status: SettlementCalculationStatus

  // 수업 당시 적용된 단가
  // 단가가 없으면 null
  unit_rate: number | null

  // 수업별 정산 금액
  // 정산 제외: 0
  // 단가 미설정: null
  settlement_amount: number | null

  currency_code: string

  // 적용된 단가 및 정산 기준의 시작일
  rate_effective_from: string | null
  policy_effective_from: string | null
}

// 상세 내역 조회 조건
export interface GetMonthlySettlementDetailsParams {
  year: number
  month: number

  // 선택하지 않으면 전체 근무처 조회
  companyId?: string | null
}

// 월별 수업 정산 상세 내역 조회
export async function getMonthlySettlementDetails({
  year,
  month,
  companyId = null,
}: GetMonthlySettlementDetailsParams): Promise<MonthlySettlementDetail[]> {
  // 조회 연도와 월 검사
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

  // 로그인한 트레이너 정보 확인
  // 데모 계정도 기존 트레이너 컨텍스트 사용
  const context = await getTrainerContext()

  if (!context.trainerId) {
    throw new Error('트레이너 정보를 확인할 수 없습니다.')
  }

  // Supabase 수업별 정산 상세 조회
  const { data, error } = await supabase.rpc('get_monthly_settlement_details', {
    p_trainer_id: context.trainerId,
    p_year: year,
    p_month: month,
    p_company_id: companyId,
  })

  if (error) {
    console.error('월별 정산 상세 조회 오류:', error)
    throw error
  }

  // 데이터가 없다면 빈 배열 반환
  return (data ?? []) as MonthlySettlementDetail[]
}
