import { supabase } from '@/lib/supabase'
import { getMemberStatus } from '@/utils/memberStatus'
import type { MemberStatus } from '@/utils/memberStatus'

// 회원 목록에서 사용하는 데이터 타입
export interface MemberListData {
  id: string
  name: string
  phone: string
  status: MemberStatus
  totalSessions: number | null
  remainingSessions: number | null
}

// Supabase 회원 목록 조회
export async function getMembers(): Promise<MemberListData[]> {
  // 로그인한 트레이너의 회원 및 이용권 조회
  const { data, error } = await supabase
    .from('members')
    .select(
      `
      id,
      name,
      phone,
      status,
      member_packages (
        package_type,
        usage_type,
        total_sessions,
        remaining_sessions,
        status
      )
    `,
    )
    .order('created_at', { ascending: false })

  // 오류 발생 시 TanStack Query에 전달
  if (error) {
    throw error
  }

  // 회원별 PT 횟수 계산
  return (data ?? []).map((member) => {
    // 회원이 보유한 이용권을 기준으로 활동 상태 자동 계산
    const status = getMemberStatus(member.status, member.member_packages)

    // 취소되지 않은 PT 횟수제 이용권만 필터링
    const ptPackages = member.member_packages.filter(
      (pkg) =>
        pkg.package_type === 'pt' && pkg.usage_type === 'count' && pkg.status !== 'cancelled',
    )

    // PT 이용권 정보가 없는 회원
    if (ptPackages.length === 0) {
      return {
        id: member.id,
        name: member.name,
        phone: member.phone,
        status,
        totalSessions: null,
        remainingSessions: null,
      }
    }

    // 총 PT 횟수 계산
    const totalSessions = ptPackages.reduce((total, pkg) => total + (pkg.total_sessions ?? 0), 0)

    // 이용 중인 PT 잔여 횟수 계산
    const remainingSessions = ptPackages.reduce(
      (total, pkg) => total + (pkg.status === 'active' ? (pkg.remaining_sessions ?? 0) : 0),
      0,
    )

    return {
      id: member.id,
      name: member.name,
      phone: member.phone,
      status,
      totalSessions,
      remainingSessions,
    }
  })
}
