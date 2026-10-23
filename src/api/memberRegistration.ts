import { supabase } from '@/lib/supabase'

// 회원 및 PT 이용권 등록 데이터 타입
export interface RegisterMemberWithPtParams {
  name: string
  phone: string
  totalSessions: number
}

// 회원 기본 정보 등록 데이터 타입
export interface RegisterMemberOnlyParams {
  name: string
  phone: string
}

// 신규 회원 및 PT 이용권 등록
export async function registerMemberWithPt(member: RegisterMemberWithPtParams) {
  const { error } = await supabase.rpc('register_member_with_pt', {
    p_name: member.name.trim(),
    p_phone: member.phone,
    p_total_sessions: member.totalSessions,
  })

  if (error) throw error
}

// 이용권 없이 회원 기본 정보만 등록
export async function registerMemberOnly(member: RegisterMemberOnlyParams): Promise<string> {
  const { data, error } = await supabase.rpc('register_member_only', {
    p_name: member.name.trim(),
    p_phone: member.phone,
  })

  if (error) throw error

  return data
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

// 월 회원권 등록 데이터 타입
export interface RegisterMemberWithMembershipParams {
  name: string
  phone: string
  startsOn: string
  endsOn: string
}

// 신규 회원 및 월 회원권 등록
export async function registerMemberWithMembership(
  member: RegisterMemberWithMembershipParams,
): Promise<string> {
  const { data, error } = await supabase.rpc('register_member_with_membership', {
    p_name: member.name.trim(),
    p_phone: member.phone,
    p_starts_on: member.startsOn,
    p_ends_on: member.endsOn,
  })

  if (error) throw error

  return data
}

// 신규 회원 및 그룹 횟수제 등록 데이터 타입
export interface RegisterMemberWithGroupParams {
  name: string
  phone: string
  totalSessions: number
}

// 신규 회원과 그룹 횟수제 이용권 등록
export async function registerMemberWithGroup(
  member: RegisterMemberWithGroupParams,
): Promise<string> {
  const { data, error } = await supabase.rpc('register_member_with_group', {
    p_name: member.name.trim(),
    p_phone: member.phone,
    p_total_sessions: member.totalSessions,
  })

  if (error) throw error

  return data
}
