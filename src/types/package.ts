// 이용권 유형
export type PackageType = 'pt' | 'group' | 'membership'

// 이용권 관리 방식
export type UsageType = 'count' | 'period'

// 이용권 상태
export type PackageStatus = 'active' | 'expired' | 'completed' | 'cancelled'

// 회원이 구매한 이용권 데이터 타입
export interface MemberPackage {
  id: string
  memberId: string
  name: string
  type: PackageType
  usageType: UsageType
  price: number
  totalSessions: number | null
  remainingSessions: number | null
  startDate: string | null
  endDate: string | null
  status: PackageStatus
  createdAt: string
}

// 이용권 유형별 표시 이름
export const PACKAGE_TYPE_LABELS: Record<PackageType, string> = {
  pt: 'PT',
  group: '그룹수업',
  membership: '일반회원권',
}
