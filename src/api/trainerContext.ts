import { supabase } from '@/lib/supabase'

// ============================================
// 트레이너 컨텍스트 타입
// ============================================

// 일반 사용자 또는 데모 방문자의 데이터 조회 기준
export interface TrainerContext {
  trainerId: string
  isDemo: boolean
}

// Supabase RPC 응답 타입
interface TrainerContextRow {
  trainer_id: string
  is_demo: boolean
}

// ============================================
// 현재 트레이너 컨텍스트 조회
// ============================================

export async function getTrainerContext(): Promise<TrainerContext> {
  // DB에서 현재 사용자에 맞는 데이터 소유자 조회
  // 일반 사용자: 로그인한 본인의 UUID
  // 데모 방문자: 설정된 데모 트레이너의 UUID
  const { data, error } = await supabase.rpc('get_trainer_context')

  if (error) {
    console.error('트레이너 컨텍스트 조회 오류:', error)
    throw error
  }

  // RPC는 TABLE 형태로 결과를 반환
  const rows = data as TrainerContextRow[] | null
  const context = rows?.[0]

  // 조회 결과 검증
  if (
    !context ||
    typeof context.trainer_id !== 'string' ||
    !context.trainer_id ||
    typeof context.is_demo !== 'boolean'
  ) {
    throw new Error('트레이너 정보를 확인하지 못했습니다.')
  }

  return {
    trainerId: context.trainer_id,
    isDemo: context.is_demo,
  }
}
