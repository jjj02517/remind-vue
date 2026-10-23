import { supabase } from '@/lib/supabase'
import { getTodayString } from '@/utils/date'
import { getMemberStatus } from '@/utils/memberStatus'
import { isPackagePaused } from '@/utils/packagePauseStatus'

import type { MemberStatus } from '@/utils/memberStatus'

// 회원 목록에 표시할 이용권 데이터 타입
export interface MemberListPackage {
  id: string
  packageType: string
  usageType: string
  totalSessions: number | null
  remainingSessions: number | null
  startsOn: string | null
  endsOn: string | null
  isPaused: boolean
  isScheduled: boolean
}

// 회원 목록에서 사용하는 데이터 타입
export interface MemberListData {
  id: string
  name: string
  phone: string
  status: MemberStatus

  // 기존 회원 목록과의 호환을 위해 임시 유지
  totalSessions: number | null
  remainingSessions: number | null

  // 회원이 보유한 현재 및 예정 이용권
  packages: MemberListPackage[]
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
        id,
        package_type,
        usage_type,
        total_sessions,
        remaining_sessions,
        starts_on,
        ends_on,
        status,
        created_at,
        package_pauses (
          id,
          package_id,
          starts_on,
          ends_on,
          resumed_on,
          cancelled_at,
          reason,
          created_at
        )
      )
    `,
    )
    .order('created_at', { ascending: false })

  // 오류 발생 시 TanStack Query에 전달
  if (error) {
    throw error
  }

  const today = getTodayString()

  // 회원별 이용권 및 상태 계산
  return (data ?? []).map((member) => {
    const memberPackages = member.member_packages ?? []

    // 회원이 보유한 모든 이용권과 일시정지 내역을 기준으로 활동 상태 계산
    const status = getMemberStatus(member.status, memberPackages, today)

    // 현재 사용 가능하거나 앞으로 이용할 수 있는 이용권만 목록에 표시
    const displayPackages = memberPackages
      .filter((pkg) => {
        // 이용 완료, 취소, 만료 처리된 이용권 제외
        if (pkg.status !== 'active') return false

        // 실제 만료일이 지난 이용권 제외
        if (pkg.ends_on && pkg.ends_on < today) {
          return false
        }

        // 횟수제 이용권은 잔여 횟수가 있어야 표시
        if (pkg.usage_type === 'count') {
          return (pkg.remaining_sessions ?? 0) > 0
        }

        // 기간제 이용권은 시작일과 종료일이 있어야 표시
        if (pkg.usage_type === 'period') {
          return !!pkg.starts_on && !!pkg.ends_on
        }

        return false
      })
      .map((pkg): MemberListPackage => ({
        id: pkg.id,
        packageType: pkg.package_type,
        usageType: pkg.usage_type,
        totalSessions: pkg.total_sessions,
        remainingSessions: pkg.remaining_sessions,
        startsOn: pkg.starts_on,
        endsOn: pkg.ends_on,

        // 현재 이용권이 일시정지 중인지 확인
        isPaused: isPackagePaused(pkg.package_pauses ?? [], today),

        // 아직 시작하지 않은 이용권인지 확인
        isScheduled: !!pkg.starts_on && pkg.starts_on > today,
      }))

    // 기존 회원 목록과의 호환을 위한 PT 횟수 계산
    // 취소되지 않은 PT 횟수제 이용권만 필터링
    const ptPackages = memberPackages.filter(
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
        packages: displayPackages,
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
      packages: displayPackages,
    }
  })
}
