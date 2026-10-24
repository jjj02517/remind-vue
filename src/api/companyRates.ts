import { supabase } from '@/lib/supabase'

// 근무처별 정산 단가 변경 이력 타입
export interface CompanyRateVersion {
  id: number
  company_id: string
  effective_from: string
  pt_rate_per_session: number | null
  group_rate_per_attendee: number | null
  currency_code: 'KRW'
  created_at: string
  created_by: string
}

// 새 정산 단가 이력 등록 파라미터
export interface AddCompanyRateVersionParams {
  companyId: string
  effectiveFrom: string
  ptRatePerSession: number | null
  groupRatePerAttendee: number | null
}

// 내 근무처의 정산 단가 변경 이력 조회 (RLS로 소유 근무처만 반환)
export async function getCompanyRateHistory(): Promise<CompanyRateVersion[]> {
  const { data, error } = await supabase
    .from('company_rate_history')
    .select(
      'id, company_id, effective_from, pt_rate_per_session, group_rate_per_attendee, currency_code, created_at, created_by',
    )
    .order('effective_from', { ascending: false })
    .order('id', { ascending: false })

  if (error) throw error

  return (data ?? []) as CompanyRateVersion[]
}

// 새 단가를 추가하고 이전 단가 이력은 보존
export async function addCompanyRateVersion(params: AddCompanyRateVersionParams): Promise<number> {
  if (!params.companyId) throw new Error('근무처를 선택해 주세요.')
  if (!/^\d{4}-\d{2}-\d{2}$/.test(params.effectiveFrom)) {
    throw new Error('적용 시작일을 올바르게 입력해 주세요.')
  }

  const rates = [params.ptRatePerSession, params.groupRatePerAttendee]

  if (rates.every((rate) => rate === null)) {
    throw new Error('PT 또는 그룹 단가를 하나 이상 입력해 주세요.')
  }

  if (rates.some((rate) => rate !== null && (!Number.isSafeInteger(rate) || rate < 0))) {
    throw new Error('단가는 0원 이상의 정수로 입력해 주세요.')
  }

  const { data, error } = await supabase.rpc('add_company_rate_version', {
    p_company_id: params.companyId,
    p_effective_from: params.effectiveFrom,
    p_pt_rate_per_session: params.ptRatePerSession,
    p_group_rate_per_attendee: params.groupRatePerAttendee,
  })

  if (error) throw error

  return data as number
}
