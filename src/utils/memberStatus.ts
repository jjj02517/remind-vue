// 회원 활동 상태 타입
export type MemberStatus = 'active' | 'inactive' | 'archived'

// 회원 상태 계산에 필요한 이용권 데이터 타입
interface MemberPackage {
  package_type: string
  usage_type: string
  status: string
  remaining_sessions: number | null
}

// 회원 활동 상태 자동 계산
export function getMemberStatus(memberStatus: string, packages: MemberPackage[]): MemberStatus {
  // 관리자가 보관 처리한 회원은 보관 상태 유지
  if (memberStatus === 'archived') {
    return 'archived'
  }

  // 이용 가능한 PT 이용권이 있는지 확인
  const hasActivePtPackage = packages.some(
    (pkg) =>
      pkg.package_type === 'pt' &&
      pkg.usage_type === 'count' &&
      pkg.status === 'active' &&
      (pkg.remaining_sessions ?? 0) > 0,
  )

  // 이용 가능한 PT가 하나라도 있다면 활동 중
  if (hasActivePtPackage) {
    return 'active'
  }

  // 이용 가능한 PT가 없다면 비활성
  return 'inactive'
}
