<script setup lang="ts">
import { computed, ref } from 'vue'
import { useMutation, useQueryClient } from '@tanstack/vue-query'
import { formatPhone, isValidPhone, normalizePhone } from '@/utils/phone'
import { supabase } from '@/lib/supabase'
import type { Member } from '@/types/member'

// 신규 회원 등록 데이터 타입
type NewMember = Pick<Member, 'name' | 'phone' | 'totalSessions'>

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 회원 등록 오류 메시지
const registerError = ref('')

// Supabase 회원 등록 Mutation
const { mutateAsync: registerMember, isPending: isRegistering } = useMutation({
  // 신규 회원 및 PT 이용권 등록
  mutationFn: async (member: NewMember) => {
    const { error } = await supabase.rpc('register_member_with_pt', {
      p_name: member.name.trim(),
      p_phone: member.phone,
      p_total_sessions: member.totalSessions,
    })

    if (error) {
      throw error
    }
  },

  // 등록 성공 시 회원 목록 캐시 무효화
  onSuccess: async () => {
    await queryClient.invalidateQueries({
      queryKey: ['members'],
    })
  },
})

// 회원 등록 모달
const registerDialog = ref<HTMLDialogElement | null>(null)

// 신규 회원 입력 데이터
const newMember = ref<NewMember>({
  name: '',
  phone: '',
  totalSessions: 1,
})

// 이름 중복 경고 메시지
const nameWarning = ref('')

// 중복 회원명 확인 여부
const isNameDuplicateConfirmed = ref(false)

// 회원명 중복 검사 진행 상태
const isCheckingName = ref(false)

// 중복 검사 완료된 회원명
const checkedName = ref('')

// 이전 이름 검사 결과를 무시하기 위한 요청 번호
let nameCheckId = 0

// 연락처 유효성 검사 메시지
const phoneError = ref('')

// 중복 검사 상태
const isCheckingDuplicates = ref(false)

// 연락처 중복 검사 진행 상태
const isCheckingPhone = ref(false)

// 중복 검사 완료된 연락처
const checkedPhone = ref('')

// 이전 연락처 검사 결과를 무시하기 위한 요청 번호
let phoneCheckId = 0

// 회원 등록 또는 중복 검사 진행 상태
const isBusy = computed(
  () =>
    isRegistering.value ||
    isCheckingDuplicates.value ||
    isCheckingName.value ||
    isCheckingPhone.value,
)

// 회원 등록 버튼 비활성화 조건
const isSubmitDisabled = computed(() => {
  // 등록 또는 중복 검사 진행 중
  if (isBusy.value) return true

  // 회원명 미입력
  const name = newMember.value.name.trim()

  if (!name) return true

  // 현재 회원명의 중복 검사가 완료되지 않은 경우
  if (checkedName.value !== name) return true

  // 중복 이름을 확인하지 않은 경우
  if (nameWarning.value && !isNameDuplicateConfirmed.value) {
    return true
  }

  // 연락처 형식이 올바르지 않은 경우
  const phone = normalizePhone(newMember.value.phone)

  if (!isValidPhone(phone)) return true

  // 연락처 중복 또는 유효성 검사 오류
  if (phoneError.value) return true

  // 현재 연락처의 중복 검사가 완료되지 않은 경우
  if (checkedPhone.value !== phone) return true

  // PT 횟수가 1 이상의 정수가 아닌 경우
  if (!Number.isInteger(newMember.value.totalSessions) || newMember.value.totalSessions < 1) {
    return true
  }

  return false
})

// 회원명 입력 시 경고 초기화
function handleNameInput() {
  // 이전 이름 중복 검사 결과 무효화
  nameCheckId++
  checkedName.value = ''
  isCheckingName.value = false

  // 중복 경고 및 확인 상태 초기화
  nameWarning.value = ''
  isNameDuplicateConfirmed.value = false
  registerError.value = ''
}

// 연락처 입력 시 자동 하이픈 처리
function handlePhoneInput(event: Event) {
  const input = event.target as HTMLInputElement

  const formattedPhone = formatPhone(input.value)

  input.value = formattedPhone
  newMember.value.phone = formattedPhone

  // 기존 중복 검사 결과 초기화
  phoneCheckId++
  checkedPhone.value = ''
  isCheckingPhone.value = false
  phoneError.value = ''
  registerError.value = ''

  // 올바른 11자리 번호가 입력되면 자동 중복 검사
  const phone = normalizePhone(formattedPhone)

  if (isValidPhone(phone)) {
    void checkPhoneDuplicate()
  }
}

// 회원명 중복 검사
async function checkNameDuplicate(): Promise<boolean | null> {
  const name = newMember.value.name.trim()
  const requestId = ++nameCheckId

  // 기존 검사 결과 초기화
  checkedName.value = ''
  nameWarning.value = ''

  if (!name) return null

  isCheckingName.value = true

  try {
    // 공백과 대소문자를 무시하고 회원명 중복 검사
    const { data: isDuplicate, error } = await supabase.rpc('check_member_name_duplicate', {
      p_name: name,
    })

    if (error) throw error

    // 검사 결과 확인용 임시 로그
    console.log('회원명 중복 검사:', name, isDuplicate)

    // 검사 중 입력값이 변경됐다면 이전 결과는 무시
    if (requestId !== nameCheckId || name !== newMember.value.name.trim()) {
      return null
    }

    // 현재 회원명 검사 완료
    checkedName.value = name

    // 이름은 중복되어도 확인 후 등록 허용
    if (isDuplicate === true) {
      nameWarning.value = '이미 같은 이름의 회원이 있습니다. 동명이인인지 확인해 주세요.'
    }

    return isDuplicate === true
  } catch (error) {
    console.error('회원명 중복 검사 오류:', error)

    if (requestId === nameCheckId) {
      registerError.value = '회원명 중복 확인 중 문제가 발생했습니다.'
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
  const phone = normalizePhone(newMember.value.phone)
  const requestId = ++phoneCheckId

  // 기존 검사 결과 초기화
  checkedPhone.value = ''
  phoneError.value = ''

  // 연락처 유효성 검사
  if (!isValidPhone(phone)) {
    phoneError.value = '010으로 시작하는 11자리 휴대폰 번호를 입력해 주세요.'
    return false
  }

  isCheckingPhone.value = true

  try {
    // 같은 트레이너의 동일한 연락처 조회
    const { data, error } = await supabase.from('members').select('id').eq('phone', phone).limit(1)

    if (error) throw error

    // 검사 중 연락처가 변경되었다면 이전 결과 무시
    if (requestId !== phoneCheckId || phone !== normalizePhone(newMember.value.phone)) {
      return false
    }

    // 연락처가 중복되면 등록 차단
    if (data && data.length > 0) {
      phoneError.value = '이미 등록된 연락처입니다. 기존 회원을 확인해 주세요.'
      return false
    }

    // 사용 가능한 연락처로 확인 완료
    checkedPhone.value = phone

    return true
  } catch (error) {
    console.error('연락처 중복 검사 오류:', error)

    if (requestId === phoneCheckId) {
      registerError.value = '연락처 중복 확인 중 문제가 발생했습니다.'
    }

    return false
  } finally {
    if (requestId === phoneCheckId) {
      isCheckingPhone.value = false
    }
  }
}

// 회원 등록 모달 열기
function openRegisterDialog() {
  registerError.value = ''
  registerDialog.value?.showModal()
}

// 회원 등록 모달 닫기
function closeRegisterDialog() {
  if (isBusy.value) return

  registerDialog.value?.close()
}

// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isBusy.value) {
    event.preventDefault()
  }
}

// 입력값 초기화
function resetForm() {
  newMember.value = {
    name: '',
    phone: '',
    totalSessions: 1,
  }

  nameWarning.value = ''
  isNameDuplicateConfirmed.value = false
  phoneError.value = ''
  registerError.value = ''

  // 이름 중복 검사 상태 초기화
  nameCheckId++
  checkedName.value = ''
  isCheckingName.value = false

  // 연락처 중복 검사 상태 초기화
  phoneCheckId++
  checkedPhone.value = ''
  isCheckingPhone.value = false
}

// 신규 회원 등록
async function submitMember() {
  if (isSubmitDisabled.value) return

  const name = newMember.value.name.trim()
  const phone = normalizePhone(newMember.value.phone)
  const totalSessions = newMember.value.totalSessions

  if (!name || !Number.isInteger(totalSessions) || totalSessions < 1) {
    return
  }

  registerError.value = ''
  isCheckingDuplicates.value = true

  try {
    // 연락처 유효성 검사
    if (!isValidPhone(phone)) {
      phoneError.value = '010으로 시작하는 11자리 휴대폰 번호를 입력해 주세요.'
      return
    }

    // 등록 직전 회원명과 연락처 중복 재검사
    const isNameDuplicate = await checkNameDuplicate()
    const isPhoneAvailable = await checkPhoneDuplicate()

    // 중복 검사 실패 시 등록 중단
    if (registerError.value || isNameDuplicate === null || !isPhoneAvailable) {
      return
    }

    // 중복 이름을 사용자가 확인하지 않았다면 등록 중단
    if (isNameDuplicate && !isNameDuplicateConfirmed.value) {
      return
    }

    // Supabase 회원 및 PT 이용권 등록
    await registerMember({
      name,
      phone,
      totalSessions,
    })

    // 등록 성공 시 모달 닫기
    // isCheckingDuplicates 상태는 finally에서 해제
  } catch (error) {
    console.error('회원 등록 오류:', error)

    // DB UNIQUE 제약조건으로 중복 차단된 경우
    if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
      phoneError.value = '이미 등록된 연락처입니다. 기존 회원을 확인해 주세요.'
    } else {
      registerError.value = '회원 등록에 실패했습니다.'
    }

    return
  } finally {
    isCheckingDuplicates.value = false
  }

  closeRegisterDialog()
}

// 부모에서 모달 열기 함수를 사용할 수 있도록 공개
defineExpose({
  open: openRegisterDialog,
})
</script>

<template>
  <!-- 회원 등록 모달 -->
  <dialog
    ref="registerDialog"
    aria-labelledby="register-dialog-title"
    aria-describedby="register-dialog-description"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @close="resetForm"
    @cancel="handleCancel"
  >
    <!-- 모달 제목 -->
    <h2 id="register-dialog-title" class="text-xl font-bold text-slate-900">회원 등록</h2>

    <!-- 모달 설명 -->
    <p id="register-dialog-description" class="mt-2 text-sm text-slate-500">
      새로운 회원의 정보를 등록합니다.
    </p>

    <!-- 회원 정보 입력 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitMember">
      <!-- 회원명 -->
      <div>
        <label for="member-name" class="mb-2 block text-sm font-medium text-slate-700">
          회원명
        </label>

        <input
          id="member-name"
          v-model="newMember.name"
          type="text"
          required
          placeholder="회원명을 입력하세요"
          :disabled="isBusy"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          @input="handleNameInput"
          @blur="checkNameDuplicate"
        />

        <!-- 회원명 중복 경고 메시지 -->
        <p v-if="nameWarning" role="status" class="mt-2 text-xs text-amber-600">
          {{ nameWarning }}
        </p>

        <!-- 중복 회원명 확인 -->
        <label
          v-if="nameWarning"
          class="mt-3 flex cursor-pointer items-center gap-2 text-sm text-slate-700"
        >
          <input
            v-model="isNameDuplicateConfirmed"
            type="checkbox"
            :disabled="isBusy"
            class="h-4 w-4 accent-blue-600"
          />
          동명이인임을 확인했습니다.
        </label>
      </div>

      <!-- 연락처 -->
      <div>
        <label for="member-phone" class="mb-2 block text-sm font-medium text-slate-700">
          연락처
        </label>

        <input
          id="member-phone"
          :value="newMember.phone"
          type="tel"
          inputmode="numeric"
          maxlength="13"
          required
          placeholder="010-0000-0000"
          :aria-invalid="!!phoneError"
          aria-describedby="member-phone-error"
          :disabled="isBusy"
          class="w-full rounded-lg border px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          :class="phoneError ? 'border-red-500' : 'border-slate-200'"
          @input="handlePhoneInput"
        />

        <!-- 연락처 유효성 검사 메시지 -->
        <p v-if="phoneError" id="member-phone-error" role="alert" class="mt-2 text-xs text-red-500">
          {{ phoneError }}
        </p>
      </div>

      <!-- 총 PT 횟수 -->
      <div>
        <label for="member-sessions" class="mb-2 block text-sm font-medium text-slate-700">
          총 PT 횟수
        </label>

        <input
          id="member-sessions"
          v-model.number="newMember.totalSessions"
          type="number"
          min="1"
          step="1"
          required
          :disabled="isBusy"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- 회원 등록 오류 메시지 -->
      <p v-if="registerError" role="alert" class="text-sm text-red-600">
        {{ registerError }}
      </p>

      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <button
          type="button"
          :disabled="isBusy"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closeRegisterDialog"
        >
          취소
        </button>

        <!-- 회원 등록 -->
        <button
          type="submit"
          :disabled="isSubmitDisabled"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-500"
        >
          {{ isBusy ? '확인 중...' : '회원 등록' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
