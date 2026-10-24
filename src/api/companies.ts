import { supabase } from '@/lib/supabase'

// 근무처 종류
export type CompanyType = 'personal' | 'workplace'

// 근무처 데이터 타입
export interface Company {
  id: string
  trainer_id: string
  name: string
  company_type: CompanyType
  is_active: boolean
  created_at: string
  updated_at: string
}

// 내 근무처 목록 조회
export async function getCompanies(): Promise<Company[]> {
  const { data, error } = await supabase
    .from('companies')
    .select('id, trainer_id, name, company_type, is_active, created_at, updated_at')
    .order('created_at', { ascending: true })

  if (error) throw error

  const companies = (data ?? []) as Company[]

  // 기본 '개인 고객' 근무처를 목록 맨 위에 표시
  return companies.sort((a, b) => {
    if (a.company_type === 'personal') return -1
    if (b.company_type === 'personal') return 1
    return 0
  })
}

// 일반 근무처 등록
export async function createCompany(name: string): Promise<Company> {
  const trimmedName = name.trim()

  // 빈 이름 등록 방지
  if (!trimmedName) {
    throw new Error('근무처 이름을 입력해 주세요.')
  }

  // 현재 로그인한 트레이너 확인
  const { data: authData, error: authError } = await supabase.auth.getUser()

  if (authError) throw authError

  if (!authData.user) {
    throw new Error('로그인이 필요합니다.')
  }

  // 일반 근무처 생성
  const { data, error } = await supabase
    .from('companies')
    .insert({
      trainer_id: authData.user.id,
      name: trimmedName,
      company_type: 'workplace',
    })
    .select('id, trainer_id, name, company_type, is_active, created_at, updated_at')
    .single()

  if (error) throw error

  return data as Company
}

// 근무처 이름 수정
export async function updateCompany(companyId: string, name: string): Promise<Company> {
  const trimmedName = name.trim()

  // 빈 이름 수정 방지
  if (!trimmedName) {
    throw new Error('근무처 이름을 입력해 주세요.')
  }

  // 일반 근무처의 이름만 수정
  const { data, error } = await supabase
    .from('companies')
    .update({ name: trimmedName })
    .eq('id', companyId)
    .eq('company_type', 'workplace')
    .select('id, trainer_id, name, company_type, is_active, created_at, updated_at')
    .single()

  if (error) throw error

  return data as Company
}

// 근무처 보관 상태 변경
async function setCompanyActive(companyId: string, isActive: boolean): Promise<Company> {
  // 일반 근무처만 보관 또는 복구 가능
  const { data, error } = await supabase
    .from('companies')
    .update({ is_active: isActive })
    .eq('id', companyId)
    .eq('company_type', 'workplace')
    .select('id, trainer_id, name, company_type, is_active, created_at, updated_at')
    .single()

  if (error) throw error

  return data as Company
}

// 일반 근무처 보관
export async function archiveCompany(companyId: string): Promise<Company> {
  return setCompanyActive(companyId, false)
}

// 보관된 근무처 복구
export async function restoreCompany(companyId: string): Promise<Company> {
  return setCompanyActive(companyId, true)
}
