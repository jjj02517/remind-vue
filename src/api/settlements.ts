import { supabase } from '@/lib/supabase'
import { getTrainerContext } from '@/api/trainerContext'

// 월별 근무처 정산 데이터 타입
export interface MonthlySettlement {
  company_id: string
  company_name: string
  currency_code: string

  // 확정 정산
  confirmed_units: number
  confirmed_amount: number

  // 예정 수업 예상 정산
  scheduled_units: number
  scheduled_amount: number

  // 수업 당시 단가가 없어 금액 계산이 불가능한 건수
  unpriced_confirmed_units: number
  unpriced_scheduled_units: number
}

// 월별 정산 조회 요청 데이터 타입
export interface GetMonthlySettlementsParams {
  year: number
  month: number
}

// 월별 근무처별 정산 금액 조회
export async function getMonthlySettlements({
  year,
  month,
}: GetMonthlySettlementsParams): Promise<MonthlySettlement[]> {
  // 조회 연도 및 월 유효성 확인
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
  // 데모 계정은 기존 데모 데이터 조회 정책 사용
  const context = await getTrainerContext()

  if (!context.trainerId) {
    throw new Error('트레이너 정보를 확인할 수 없습니다.')
  }

  // Supabase에서 월별 정산 데이터 계산
  const { data, error } = await supabase.rpc('get_monthly_settlement_preview', {
    p_trainer_id: context.trainerId,
    p_year: year,
    p_month: month,
  })

  if (error) throw error

  // 조회 결과가 없으면 빈 배열 반환
  return (data ?? []) as MonthlySettlement[]
}
