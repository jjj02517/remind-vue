import { supabase } from '@/lib/supabase'

// 기존 회원에게 그룹 횟수제 이용권 추가 데이터 타입
export interface AddGroupPackageParams {
  memberId: string
  totalSessions: number
}

// 기존 회원에게 그룹 횟수제 이용권 추가
export async function addGroupPackage(params: AddGroupPackageParams): Promise<string> {
  // 회원 ID 확인
  if (!params.memberId) {
    throw new Error('회원 ID가 필요합니다.')
  }

  // 그룹 수업 횟수 유효성 검사
  if (!Number.isInteger(params.totalSessions) || params.totalSessions < 1) {
    throw new Error('그룹 수업 횟수는 1회 이상이어야 합니다.')
  }

  // Supabase 그룹 횟수제 이용권 추가 RPC 호출
  // 기존 그룹 API는 다른 호출부의 호환성을 위해 이번에는 변경하지 않음
  const { data, error } = await supabase.rpc('add_group_package', {
    p_member_id: params.memberId,
    p_total_sessions: params.totalSessions,
  })

  if (error) throw error

  // 새로 생성된 이용권 UUID 반환
  return data
}

// 기존 회원에게 월 회원권 추가 시 전달할 데이터 타입
export interface AddMembershipPackageParams {
  memberId: string
  startsOn: string
  endsOn: string
  companyId: string
}

// 기존 회원에게 월 회원권 추가
export async function addMembershipPackage(params: AddMembershipPackageParams): Promise<string> {
  // 회원 ID 필수
  if (!params.memberId) {
    throw new Error('회원 ID가 필요합니다.')
  }

  // 근무처 선택 필수
  if (!params.companyId) {
    throw new Error('근무처를 선택해 주세요.')
  }

  // 이용 시작일과 종료일 필수
  if (!params.startsOn || !params.endsOn) {
    throw new Error('이용 시작일과 종료일을 입력해 주세요.')
  }

  // 종료일은 시작일보다 빠를 수 없음
  if (params.endsOn < params.startsOn) {
    throw new Error('종료일은 시작일보다 빠를 수 없습니다.')
  }

  // Supabase RPC로 선택한 근무처에 월 회원권 추가
  const { data, error } = await supabase.rpc('add_membership_package', {
    p_member_id: params.memberId,
    p_starts_on: params.startsOn,
    p_ends_on: params.endsOn,
    p_company_id: params.companyId,
  })

  // 오류 발생 시 호출한 컴포넌트에 전달
  if (error) {
    throw error
  }

  // 생성된 이용권 UUID 반환
  return data
}
