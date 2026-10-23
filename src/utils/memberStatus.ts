import { isPackagePaused } from '@/utils/packagePauseStatus'
import type { PackagePause } from '@/api/packagePauses'

// 회원 활동 상태 타입
export type MemberStatus = 'active' | 'inactive' | 'archived'

// 회원 활동 상태 계산에 필요한 이용권 정보
interface MemberPackage {
  package_type: string
  usage_type: string
  status: string
  remaining_sessions: number | null
  starts_on?: string | null
  ends_on?: string | null

  // 해당 이용권의 일시정지 내역
  package_pauses?: PackagePause[] | null
}

// 오늘 날짜를 YYYY-MM-DD 형식으로 반환
function getTodayString(): string {
  const now = new Date()

  const year = now.getFullYear()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const day = String(now.getDate()).padStart(2, '0')

  return `${year}-${month}-${day}`
}

// 이용권의 현재 사용 가능 여부 확인
function isPackageAvailable(pkg: MemberPackage, today: string): boolean {
  // 취소, 만료, 사용 완료된 이용권은 제외
  if (pkg.status !== 'active') return false

  // 이용 시작 전인 경우
  if (pkg.starts_on && today < pkg.starts_on) return false

  // 이용 기간이 종료된 경우
  if (pkg.ends_on && today > pkg.ends_on) return false

  // 현재 일시정지 중인 이용권은 사용 불가
  if (isPackagePaused(pkg.package_pauses ?? [], today)) {
    return false
  }

  // 횟수제 이용권: 잔여 횟수가 있어야 이용 가능
  if (pkg.usage_type === 'count') {
    return (pkg.remaining_sessions ?? 0) > 0
  }

  // 기간제 이용권: 시작일과 종료일이 모두 필요
  if (pkg.usage_type === 'period') {
    return !!pkg.starts_on && !!pkg.ends_on && pkg.starts_on <= today && today <= pkg.ends_on
  }

  return false
}

// 회원의 실제 활동 상태 계산
export function getMemberStatus(
  memberStatus: string,
  packages: MemberPackage[],
  today: string = getTodayString(),
): MemberStatus {
  // 보관 회원은 이용권 상태와 관계없이 보관 상태 유지
  if (memberStatus === 'archived') {
    return 'archived'
  }

  // PT, 월 회원권, 그룹 수업권 중 사용 가능한 이용권 확인
  const hasAvailablePackage = packages.some((pkg) => isPackageAvailable(pkg, today))

  return hasAvailablePackage ? 'active' : 'inactive'
}
