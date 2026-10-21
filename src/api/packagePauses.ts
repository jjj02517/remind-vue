import { supabase } from '@/lib/supabase'

// 일시정지 내역 데이터 타입
export interface PackagePause {
  id: string
  package_id: string
  starts_on: string
  ends_on: string
  resumed_on: string | null
  cancelled_at: string | null
  reason: string | null
  created_at: string
}

// 특정 이용권의 일시정지 내역 조회
export async function getPackagePauses(packageId: string): Promise<PackagePause[]> {
  // Supabase에서 해당 이용권의 일시정지 내역 조회
  const { data, error } = await supabase
    .from('package_pauses')
    .select(
      `
      id,
      package_id,
      starts_on,
      ends_on,
      resumed_on,
      cancelled_at,
      reason,
      created_at
    `,
    )
    .eq('package_id', packageId)
    .order('starts_on', { ascending: false })

  // 오류 발생 시 TanStack Query에 전달
  if (error) {
    throw error
  }

  return data ?? []
}
