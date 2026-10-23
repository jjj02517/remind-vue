import { computed, ref } from 'vue'
import { checkMemberNameDuplicate, checkMemberPhoneDuplicate } from '@/api/memberRegistration'
import { isValidPhone, normalizePhone } from '@/utils/phone'

// 회원 중복 검사에 필요한 옵션
interface MemberDuplicateCheckOptions {
  getName: () => string
  getPhone: () => string
  getOriginalName?: () => string
  getOriginalPhone?: () => string
  excludeMemberId?: string
}

// 회원명 및 연락처 중복 검사 상태 관리
export function useMemberDuplicateCheck(options: MemberDuplicateCheckOptions) {
  // 회원명 중복 검사 상태
  const nameWarning = ref('')
  const nameCheckError = ref('')
  const isNameDuplicateConfirmed = ref(false)
  const isCheckingName = ref(false)
  const checkedName = ref('')

  // 연락처 중복 검사 상태
  const phoneError = ref('')
  const phoneCheckError = ref('')
  const isCheckingPhone = ref(false)
  const checkedPhone = ref('')

  // 이전 검사 응답을 구분하는 번호
  let nameCheckId = 0
  let phoneCheckId = 0

  // 중복 검사 진행 여부
  const isChecking = computed(() => isCheckingName.value || isCheckingPhone.value)

  // 회원명 중복 검사 결과 초기화
  function resetNameCheck() {
    nameCheckId++

    nameWarning.value = ''
    nameCheckError.value = ''
    isNameDuplicateConfirmed.value = false
    isCheckingName.value = false
    checkedName.value = ''
  }

  // 연락처 중복 검사 결과 초기화
  function resetPhoneCheck() {
    phoneCheckId++

    phoneError.value = ''
    phoneCheckError.value = ''
    isCheckingPhone.value = false
    checkedPhone.value = ''
  }

  // 모든 중복 검사 상태 초기화
  function resetDuplicateCheck() {
    resetNameCheck()
    resetPhoneCheck()
  }

  // 회원명 중복 검사
  async function checkNameDuplicate(): Promise<boolean | null> {
    const name = options.getName().trim()
    const requestId = ++nameCheckId

    checkedName.value = ''
    nameWarning.value = ''
    nameCheckError.value = ''

    if (!name) return null

    // 회원 수정 시 이름이 변경되지 않았다면 검사 생략
    if (options.getOriginalName && name === options.getOriginalName().trim()) {
      checkedName.value = name
      return false
    }

    isCheckingName.value = true

    try {
      // 공백과 대소문자를 무시하고 회원명 중복 검사
      const isDuplicate = await checkMemberNameDuplicate(name, options.excludeMemberId)

      // 검사 중 이름이 변경되었다면 이전 결과 무시
      if (requestId !== nameCheckId || name !== options.getName().trim()) {
        return null
      }

      // 검사 완료된 회원명 저장
      checkedName.value = name

      // 중복 이름은 확인 후 등록 또는 수정 허용
      if (isDuplicate) {
        nameWarning.value = '이미 같은 이름의 회원이 있습니다. 동명이인인지 확인해 주세요.'
      }

      return isDuplicate
    } catch (error) {
      console.error('회원명 중복 검사 오류:', error)

      if (requestId === nameCheckId) {
        nameCheckError.value = '회원명 중복 확인 중 문제가 발생했습니다.'
      }

      return null
    } finally {
      if (requestId === nameCheckId) {
        isCheckingName.value = false
      }
    }
  }

  // 연락처 중복 검사
  async function checkPhoneDuplicate(): Promise<boolean> {
    const phone = normalizePhone(options.getPhone())
    const requestId = ++phoneCheckId

    checkedPhone.value = ''
    phoneError.value = ''
    phoneCheckError.value = ''

    // 연락처 형식 확인
    if (!isValidPhone(phone)) {
      phoneError.value = '010으로 시작하는 11자리 휴대폰 번호를 입력해 주세요.'
      return false
    }

    // 회원 수정 시 기존 본인 연락처는 검사 생략
    if (options.getOriginalPhone && phone === normalizePhone(options.getOriginalPhone())) {
      checkedPhone.value = phone
      return true
    }

    isCheckingPhone.value = true

    try {
      // 같은 연락처를 가진 다른 회원 조회
      const isDuplicate = await checkMemberPhoneDuplicate(phone, options.excludeMemberId)

      // 검사 중 연락처가 변경되었다면 이전 결과 무시
      if (requestId !== phoneCheckId || phone !== normalizePhone(options.getPhone())) {
        return false
      }

      // 연락처가 중복되면 등록 또는 수정 차단
      if (isDuplicate) {
        phoneError.value = '이미 등록된 연락처입니다. 기존 회원을 확인해 주세요.'
        return false
      }

      // 사용 가능한 연락처로 확인 완료
      checkedPhone.value = phone

      return true
    } catch (error) {
      console.error('연락처 중복 검사 오류:', error)

      if (requestId === phoneCheckId) {
        phoneCheckError.value = '연락처 중복 확인 중 문제가 발생했습니다.'
      }

      return false
    } finally {
      if (requestId === phoneCheckId) {
        isCheckingPhone.value = false
      }
    }
  }

  return {
    // 회원명 중복 검사 상태
    nameWarning,
    nameCheckError,
    isNameDuplicateConfirmed,
    isCheckingName,
    checkedName,

    // 연락처 중복 검사 상태
    phoneError,
    phoneCheckError,
    isCheckingPhone,
    checkedPhone,

    // 중복 검사 진행 상태
    isChecking,

    // 중복 검사 함수
    checkNameDuplicate,
    checkPhoneDuplicate,

    // 검사 상태 초기화
    resetNameCheck,
    resetPhoneCheck,
    resetDuplicateCheck,
  }
}
