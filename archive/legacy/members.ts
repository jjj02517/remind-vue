import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Member } from '@/types/member'

// TanStack Query로 이전하여 현재 사용하지 않음
// import { supabase } from '@/lib/supabase'

/*
 * ========================================
 * 기존 Pinia 서버 데이터 타입 (참고용)
 * ========================================
 */

// Supabase 회원 데이터 타입
/*
interface DbMember {
  id: string
  name: string
  phone: string
  totalSessions: number | null
  remainingSessions: number | null
}
*/

// Supabase PT 이용권 데이터 타입
/*
interface DbPtPackage {
  id: string
  member_id: string
  package_type: string
  usage_type: string
  total_sessions: number | null
  remaining_sessions: number | null
  starts_on: string | null
  ends_on: string | null
  status: string
  created_at: string
}
*/

// 회원 데이터 전역 관리
export const useMemberStore = defineStore('members', () => {
  // 임시 회원 데이터 (Mock Data)
  const members = ref<Member[]>([
    {
      id: 1,
      name: '김민수',
      phone: '01012345678',
      totalSessions: 20,
      remainingSessions: 12,
    },
    {
      id: 2,
      name: '이지은',
      phone: '01023456789',
      totalSessions: 30,
      remainingSessions: 18,
    },
    {
      id: 3,
      name: '박서준',
      phone: '01034567890',
      totalSessions: 10,
      remainingSessions: 3,
    },
  ])

  /*
   * ========================================
   * 기존 Pinia 서버 데이터 관리 (참고용)
   *
   * 현재는 TanStack Query로 이전 완료
   * - useQuery: 회원 및 이용권 조회
   * - useMutation: 회원 등록 및 PT 이용권 추가
   * - invalidateQueries: 변경 후 캐시 갱신
   * ========================================
   */

  /*
  // Supabase 회원 데이터
  const dbMembers = ref<DbMember[]>([])

  // 회원별 PT 이용권 데이터
  const dbPtPackages = ref<DbPtPackage[]>([])

  // PT 이용권 조회 상태
  const isPackagesLoading = ref(false)
  const packagesError = ref('')

  // 회원 목록 조회 상태
  const isLoading = ref(false)
  const fetchError = ref('')

  // 회원 등록 상태
  const isRegistering = ref(false)
  const registerError = ref('')

  // PT 이용권 추가 상태
  const isAddingPackage = ref(false)
  const addPackageError = ref('')

  // Supabase 회원 목록 조회
  async function fetchMembers() {
    if (isLoading.value) return

    isLoading.value = true
    fetchError.value = ''

    try {
      // 로그인한 트레이너의 회원 및 이용권 목록 조회
      const { data, error } = await supabase
        .from('members')
        .select(
          `
          id,
          name,
          phone,
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

      if (error) {
        console.error('회원 목록 조회 오류:', error.message)
        fetchError.value = '회원 목록을 불러오지 못했습니다.'
        return
      }

      // 조회한 회원 데이터 및 PT 횟수 계산
      dbMembers.value = (data ?? []).map((member) => {
        // PT 횟수제 이용권만 필터링
        const ptPackages = member.member_packages.filter(
          (pkg) =>
            pkg.package_type === 'pt' &&
            pkg.usage_type === 'count' &&
            pkg.status !== 'cancelled',
        )

        // PT 이용권 정보가 없는 경우
        if (ptPackages.length === 0) {
          return {
            id: member.id,
            name: member.name,
            phone: member.phone,
            totalSessions: null,
            remainingSessions: null,
          }
        }

        // 총 PT 횟수 합산
        const totalSessions = ptPackages.reduce(
          (total, pkg) => total + (pkg.total_sessions ?? 0),
          0,
        )

        // 이용 중인 PT의 잔여 횟수 합산
        const remainingSessions = ptPackages.reduce(
          (total, pkg) =>
            total +
            (pkg.status === 'active' ? (pkg.remaining_sessions ?? 0) : 0),
          0,
        )

        return {
          id: member.id,
          name: member.name,
          phone: member.phone,
          totalSessions,
          remainingSessions,
        }
      })
    } catch (error) {
      console.error('회원 목록 조회 중 오류:', error)
      fetchError.value = '회원 목록 조회 중 문제가 발생했습니다.'
    } finally {
      isLoading.value = false
    }
  }

  // 회원별 PT 이용권 목록 조회
  async function fetchMemberPackages(memberId: string) {
    if (isPackagesLoading.value) return

    isPackagesLoading.value = true
    packagesError.value = ''
    dbPtPackages.value = []

    try {
      // Supabase에서 해당 회원의 PT 이용권 조회
      const { data, error } = await supabase
        .from('member_packages')
        .select(
          'id, member_id, package_type, usage_type, total_sessions, remaining_sessions, starts_on, ends_on, status, created_at',
        )
        .eq('member_id', memberId)
        .eq('package_type', 'pt')
        .order('created_at', { ascending: false })

      if (error) {
        console.error('PT 이용권 목록 조회 오류:', error.message)
        packagesError.value = 'PT 이용권 목록을 불러오지 못했습니다.'
        return
      }

      // 조회한 이용권 데이터 저장
      dbPtPackages.value = data ?? []
    } catch (error) {
      console.error('PT 이용권 조회 중 오류:', error)
      packagesError.value = 'PT 이용권 조회 중 문제가 발생했습니다.'
    } finally {
      isPackagesLoading.value = false
    }
  }

  // 신규 회원 등록
  async function registerMember(
    member: Pick<Member, 'name' | 'phone' | 'totalSessions'>,
  ) {
    if (isRegistering.value) return false

    isRegistering.value = true
    registerError.value = ''

    try {
      // Supabase에 회원 정보 및 PT 이용권 동시 등록
      const { error } = await supabase.rpc('register_member_with_pt', {
        p_name: member.name.trim(),
        p_phone: member.phone,
        p_total_sessions: member.totalSessions,
      })

      if (error) {
        console.error('회원 등록 오류:', error.message)
        registerError.value = '회원 등록에 실패했습니다.'
        return false
      }

      // 회원 등록 성공 시 목록 다시 조회
      await fetchMembers()

      return true
    } catch {
      registerError.value = '회원 등록 중 문제가 발생했습니다.'
      return false
    } finally {
      isRegistering.value = false
    }
  }

  // 기존 회원의 PT 이용권 추가
  async function addPtPackage(memberId: string, totalSessions: number) {
    if (isAddingPackage.value) return false

    isAddingPackage.value = true
    addPackageError.value = ''

    try {
      // PT 횟수 유효성 검사
      if (!Number.isInteger(totalSessions) || totalSessions < 1) {
        addPackageError.value = 'PT 횟수는 1 이상의 정수여야 합니다.'
        return false
      }

      // Supabase에 PT 이용권 추가
      const { error } = await supabase.rpc('add_pt_package', {
        p_member_id: memberId,
        p_total_sessions: totalSessions,
      })

      if (error) {
        console.error('PT 이용권 추가 오류:', error.message)
        addPackageError.value = 'PT 이용권 추가에 실패했습니다.'
        return false
      }

      // 이용권 추가 성공 시 회원 목록 및 이용권 내역 다시 조회
      await Promise.all([
        fetchMembers(),
        fetchMemberPackages(memberId),
      ])

      return true
    } catch (error) {
      console.error('PT 이용권 추가 중 오류:', error)
      addPackageError.value = 'PT 이용권 추가 중 문제가 발생했습니다.'
      return false
    } finally {
      isAddingPackage.value = false
    }
  }
  */

  // 회원 ID로 조회
  function getMemberById(id: number) {
    return members.value.find((member) => member.id === id)
  }

  return {
    // 현재 사용 중인 Mock 회원 데이터 및 조회 함수
    members,
    getMemberById,

    /*
     * 기존 Pinia 서버 데이터 관련 항목 (참고용)
     *
    dbMembers,
    isLoading,
    fetchError,
    isRegistering,
    registerError,
    isAddingPackage,
    addPackageError,
    dbPtPackages,
    isPackagesLoading,
    packagesError,
    fetchMemberPackages,
    fetchMembers,
    registerMember,
    addPtPackage,
    */
  }
})
