import { supabase } from '@/lib/supabase'

// 데모 모드 저장 불가 안내 메시지
export const DEMO_WRITE_MESSAGE = '데모 모드에서는 데이터를 저장할 수 없습니다.'

// 데모 모드에서 데이터 저장 차단
// true: 저장 중단
// false: 일반 사용자이므로 기존 저장 로직 진행
export async function blockDemoWrite(): Promise<boolean> {
  // 현재 로그인한 사용자 확인
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()

  // 로그인 정보를 확인할 수 없다면 저장 중단
  if (error || !user) {
    window.alert('로그인 정보를 확인할 수 없습니다. 다시 로그인해 주세요.')
    return true
  }

  // 일반 로그인 사용자라면 저장 허용
  if (!user.is_anonymous) return false

  // 익명 로그인 사용자는 데모 모드이므로 저장 차단
  window.alert(DEMO_WRITE_MESSAGE)
  return true
}
