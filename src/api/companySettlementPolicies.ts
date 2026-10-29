import { supabase } from '@/lib/supabase'

// 근무처별 정산 정책 데이터 타입
export interface CompanySettlementPolicy {
  id: number
  company_id: string
  effective_from: string
  include_no_show: boolean
  include_same_day_cancelled: boolean
  created_at: string
  created_by: string
}

// 정산 정책 저장 데이터 타입
export interface SaveCompanySettlementPolicyParams {
  companyId: string
  effectiveFrom: string
  includeNoShow: boolean
  includeSameDayCancelled: boolean
}

// 정산 정책이 등록되지 않은 근무처의 기본값
// 실제 출석만 정산 대상으로 인정
export const DEFAULT_SETTLEMENT_POLICY = {
  includeNoShow: false,
  includeSameDayCancelled: false,
} as const

// 특정 날짜에 적용되는 근무처 정산 정책 조회
export async function getCompanySettlementPolicy(
  companyId: string,
  targetDate: string,
): Promise<CompanySettlementPolicy | null> {
  const { data, error } = await supabase
    .from('company_settlement_policy_history')
    .select(
      `
      id,
      company_id,
      effective_from,
      include_no_show,
      include_same_day_cancelled,
      created_at,
      created_by
      `,
    )
    .eq('company_id', companyId)
    .lte('effective_from', targetDate)
    .order('effective_from', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error) throw error

  return data
}

// 근무처별 전체 정산 정책 변경 이력 조회
export async function getCompanySettlementPolicyHistory(
  companyId: string,
): Promise<CompanySettlementPolicy[]> {
  const { data, error } = await supabase
    .from('company_settlement_policy_history')
    .select(
      `
      id,
      company_id,
      effective_from,
      include_no_show,
      include_same_day_cancelled,
      created_at,
      created_by
      `,
    )
    .eq('company_id', companyId)
    .order('effective_from', { ascending: false })

  if (error) throw error

  return data ?? []
}

// 근무처별 정산 정책 저장
export async function saveCompanySettlementPolicy(
  params: SaveCompanySettlementPolicyParams,
): Promise<CompanySettlementPolicy> {
  const { data, error } = await supabase
    .from('company_settlement_policy_history')
    .upsert(
      {
        company_id: params.companyId,
        effective_from: params.effectiveFrom,
        include_no_show: params.includeNoShow,
        include_same_day_cancelled: params.includeSameDayCancelled,
      },
      {
        // 같은 근무처의 동일 적용일은 수정
        // 새로운 적용일이면 정책 이력 추가
        onConflict: 'company_id,effective_from',
      },
    )
    .select(
      `
      id,
      company_id,
      effective_from,
      include_no_show,
      include_same_day_cancelled,
      created_at,
      created_by
      `,
    )
    .single()

  if (error) throw error

  return data
}
