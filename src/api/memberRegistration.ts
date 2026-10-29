import { supabase } from '@/lib/supabase'

// 회원 등록 공통 데이터 타입
interface RegisterMemberBaseParams {
  name: string
  phone: string
  memo?: string
  companyId?: string | null
}

// 회원 및 PT 이용권 등록 데이터 타입
export interface RegisterMemberWithPtParams extends RegisterMemberBaseParams {
  totalSessions: number
}

// 회원 기본 정보 등록 데이터 타입
export interface RegisterMemberOnlyParams extends RegisterMemberBaseParams {}

// 월 회원권 등록 데이터 타입
export interface RegisterMemberWithMembershipParams extends RegisterMemberBaseParams {
  startsOn: string
  endsOn: string
}

// 신규 회원 및 그룹 횟수제 등록 데이터 타입
export interface RegisterMemberWithGroupParams extends RegisterMemberBaseParams {
  totalSessions: number
}

// 회원 등록 방식
type RegistrationType = 'pt' | 'group' | 'membership' | 'none'

// 회원 등록 공통 RPC 요청 데이터 타입
interface RegisterMemberWithMemoParams extends RegisterMemberBaseParams {
  registrationType: RegistrationType
  totalSessions?: number
  startsOn?: string
  endsOn?: string
}

// 메모를 포함한 회원 등록 공통 함수
async function registerMemberWithMemo(member: RegisterMemberWithMemoParams): Promise<string> {
  // 회원 등록과 메모 저장을 하나의 DB 트랜잭션으로 처리
  const { data, error } = await supabase.rpc('register_member_with_memo', {
    p_registration_type: member.registrationType,
    p_name: member.name.trim(),
    p_phone: member.phone,
    p_company_id: member.companyId ?? null,
    p_total_sessions: member.totalSessions ?? null,
    p_starts_on: member.startsOn || null,
    p_ends_on: member.endsOn || null,
    p_memo: member.memo?.trim() || null,
  })

  if (error) throw error

  if (!data) {
    throw new Error('회원 등록 결과를 확인하지 못했습니다.')
  }

  return data as string
}

// 신규 회원 및 PT 이용권 등록
export async function registerMemberWithPt(member: RegisterMemberWithPtParams) {
  await registerMemberWithMemo({
    ...member,
    registrationType: 'pt',
  })
}

// 이용권 없이 회원 기본 정보만 등록
export async function registerMemberOnly(member: RegisterMemberOnlyParams): Promise<string> {
  return registerMemberWithMemo({
    ...member,
    registrationType: 'none',
  })
}

// 회원명 중복 검사
export async function checkMemberNameDuplicate(
  name: string,
  excludeMemberId?: string,
): Promise<boolean> {
  // 공백과 대소문자를 무시하고 회원명 중복 검사
  const { data, error } = await supabase.rpc('check_member_name_duplicate', {
    p_name: name.trim(),
    p_exclude_member_id: excludeMemberId ?? null,
  })

  if (error) throw error

  return data === true
}

// 연락처 중복 검사
export async function checkMemberPhoneDuplicate(
  phone: string,
  excludeMemberId?: string,
): Promise<boolean> {
  // 동일한 연락처의 회원 조회
  let query = supabase.from('members').select('id').eq('phone', phone)

  // 회원 수정 시 자기 자신은 제외
  if (excludeMemberId) {
    query = query.neq('id', excludeMemberId)
  }

  const { data, error } = await query.limit(1)

  if (error) throw error

  return (data?.length ?? 0) > 0
}

// 신규 회원 및 월 회원권 등록
export async function registerMemberWithMembership(
  member: RegisterMemberWithMembershipParams,
): Promise<string> {
  return registerMemberWithMemo({
    ...member,
    registrationType: 'membership',
  })
}

// 신규 회원과 그룹 횟수제 이용권 등록
export async function registerMemberWithGroup(
  member: RegisterMemberWithGroupParams,
): Promise<string> {
  return registerMemberWithMemo({
    ...member,
    registrationType: 'group',
  })
}
