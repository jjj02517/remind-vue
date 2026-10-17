import { createClient } from '@supabase/supabase-js'

// Supabase 환경변수 가져오기
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

// 환경변수 설정 확인
if (!supabaseUrl || !supabasePublishableKey) {
  throw new Error('Supabase 환경변수가 설정되지 않았습니다.')
}

// Supabase 클라이언트 생성
export const supabase = createClient(supabaseUrl, supabasePublishableKey)
