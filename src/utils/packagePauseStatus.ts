import { getTodayString } from '@/utils/date'
import type { PackagePause } from '@/api/packagePauses'

// 일시정지 상태 타입
export type PackagePauseStatus = 'scheduled' | 'paused' | 'completed' | 'resumed' | 'cancelled'

// 일시정지 상태 표시 이름
const statusLabels: Record<PackagePauseStatus, string> = {
  scheduled: '일시정지 예정',
  paused: '일시정지 중',
  completed: '일시정지 종료',
  resumed: '조기 복귀',
  cancelled: '예약 취소',
}

// 일시정지 상태 자동 계산
export function getPackagePauseStatus(
  pause: PackagePause,
  today: string = getTodayString(),
): PackagePauseStatus {
  // 취소된 일시정지 예약
  if (pause.cancelled_at !== null) {
    return 'cancelled'
  }

  // 조기 복귀 처리된 일시정지
  if (pause.resumed_on !== null) {
    return 'resumed'
  }

  // 일시정지 시작일이 아직 오지 않은 경우
  // Supabase의 DATE 컬럼은 YYYY-MM-DD 형식이라 문자열로 비교함
  if (today < pause.starts_on) {
    return 'scheduled'
  }

  // 현재 일시정지 기간에 해당하는 경우
  if (today <= pause.ends_on) {
    return 'paused'
  }

  // 예정된 일시정지 기간이 종료된 경우
  return 'completed'
}

// 일시정지 상태 표시 이름 반환
export function getPackagePauseStatusLabel(status: PackagePauseStatus): string {
  return statusLabels[status]
}

// 실제 일시정지 중인지 확인
export function isPackagePaused(pauses: PackagePause[], today: string = getTodayString()): boolean {
  return pauses.some((pause) => getPackagePauseStatus(pause, today) === 'paused')
}
