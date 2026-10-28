<script setup lang="ts">
import { computed, ref } from 'vue'
import { useMutation, useQueryClient } from '@tanstack/vue-query'

import { supabase } from '@/lib/supabase'
import { formatPhone, isValidPhone, normalizePhone } from '@/utils/phone'
import { useMemberDuplicateCheck } from '@/composables/useMemberDuplicateCheck'
import { blockDemoWrite } from '@/utils/demoGuard'

// 부모 컴포넌트에서 회원 정보 전달받기
const props = defineProps<{
  memberId: string
  name: string
  phone: string
}>()

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 회원 수정 모달
const editDialog = ref<HTMLDialogElement | null>(null)

// 수정할 회원 정보
const editMember = ref({
  name: '',
  phone: '',
})

// 기존 회원 정보
const originalName = ref('')
const originalPhone = ref('')

// 회원 수정 오류
const editError = ref('')

// 회원명 및 연락처 중복 검사 상태 관리
const {
  nameWarning,
  nameCheckError,
  isNameDuplicateConfirmed,
  checkedName,
  phoneError,
  phoneCheckError,
  checkedPhone,
  isChecking,
  checkNameDuplicate,
  checkPhoneDuplicate,
  resetNameCheck,
  resetPhoneCheck,
  resetDuplicateCheck,
} = useMemberDuplicateCheck({
  // 현재 수정 중인 회원 정보
  getName: () => editMember.value.name,
  getPhone: () => editMember.value.phone,

  // 기존 회원 정보
  getOriginalName: () => originalName.value,
  getOriginalPhone: () => originalPhone.value,

  // 본인 회원 ID는 중복 검사 대상에서 제외
  excludeMemberId: props.memberId,
})

// Supabase 회원 정보 수정 Mutation
const { mutateAsync: updateMember, isPending: isUpdating } = useMutation({
  // 회원명 및 연락처 수정
  mutationFn: async (member: { name: string; phone: string }) => {
    const { data, error } = await supabase
      .from('members')
      .update({
        name: member.name,
        phone: member.phone,
      })
      .eq('id', props.memberId)
      .select('id')
      .single()

    if (error) throw error

    return data
  },

  // 수정 성공 시 회원 목록 및 상세 정보 갱신
  onSuccess: async () => {
    await Promise.all([
      queryClient.invalidateQueries({
        queryKey: ['members'],
      }),
      queryClient.invalidateQueries({
        queryKey: ['member'],
      }),
    ])
  },
})

// 수정 요청 진행 상태
const isSubmitting = ref(false)

// 수정 또는 검사 진행 상태
const isBusy = computed(() => isSubmitting.value || isUpdating.value || isChecking.value)

// 회원 정보 수정 오류 메시지 통합
const formError = computed(() => editError.value || nameCheckError.value || phoneCheckError.value)

// 수정 내용이 있는지 확인
const hasChanges = computed(() => {
  return (
    editMember.value.name.trim() !== originalName.value ||
    normalizePhone(editMember.value.phone) !== originalPhone.value
  )
})

// 수정 완료 버튼 비활성화 조건
const isSubmitDisabled = computed(() => {
  // 수정 또는 중복 검사 진행 중
  if (isBusy.value) return true

  // 변경된 내용이 없는 경우
  if (!hasChanges.value) return true

  // 회원명 미입력
  const name = editMember.value.name.trim()

  if (!name) return true

  // 회원명이 변경된 경우 중복 검사 완료 여부 확인
  if (name !== originalName.value) {
    if (checkedName.value !== name) return true

    // 중복 이름을 확인하지 않은 경우
    if (nameWarning.value && !isNameDuplicateConfirmed.value) {
      return true
    }
  }

  // 연락처 유효성 검사
  const phone = normalizePhone(editMember.value.phone)

  if (!isValidPhone(phone)) return true

  // 연락처 중복 또는 유효성 검사 오류
  if (phoneError.value) return true

  // 현재 연락처의 중복 검사가 완료되지 않은 경우
  if (checkedPhone.value !== phone) return true

  // 중복 검사 또는 수정 오류 발생
  if (formError.value) return true

  return false
})

// 회원 수정 모달 열기
function openEditDialog() {
  originalName.value = props.name.trim()
  originalPhone.value = normalizePhone(props.phone)

  editMember.value = {
    name: originalName.value,
    phone: formatPhone(originalPhone.value),
  }

  editError.value = ''

  // 기존 중복 검사 상태 초기화
  resetDuplicateCheck()

  // 기존 회원명과 연락처는 이미 사용 중인 본인 정보
  checkedName.value = originalName.value
  checkedPhone.value = originalPhone.value

  editDialog.value?.showModal()
}

// 회원 수정 모달 닫기
function closeEditDialog() {
  if (isBusy.value) return

  editDialog.value?.close()
}

// 수정 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isBusy.value) {
    event.preventDefault()
  }
}

// 회원명 입력 시 경고 초기화
function handleNameInput() {
  // 기존 이름 중복 검사 상태 초기화
  resetNameCheck()
  editError.value = ''

  // 기존 이름으로 돌아오면 다시 검사할 필요 없음
  if (editMember.value.name.trim() === originalName.value) {
    checkedName.value = originalName.value
  }
}

// 연락처 입력 시 자동 하이픈 처리
function handlePhoneInput(event: Event) {
  const input = event.target as HTMLInputElement
  const formattedPhone = formatPhone(input.value)

  input.value = formattedPhone
  editMember.value.phone = formattedPhone

  // 기존 연락처 중복 검사 결과 초기화
  resetPhoneCheck()
  editError.value = ''

  const phone = normalizePhone(formattedPhone)

  // 변경 전 연락처라면 별도 검사 불필요
  if (phone === originalPhone.value) {
    checkedPhone.value = phone
    return
  }

  // 올바른 연락처 형식이면 자동 중복 검사
  if (isValidPhone(phone)) {
    void checkPhoneDuplicate()
  }
}

// 회원 정보 수정
async function submitEdit() {
  if (isSubmitDisabled.value) return

  if (await blockDemoWrite()) return

  const name = editMember.value.name.trim()
  const phone = normalizePhone(editMember.value.phone)

  editError.value = ''
  isSubmitting.value = true

  let isSuccess = false

  try {
    // 저장 직전 회원명 중복 재검사
    const isNameDuplicate = await checkNameDuplicate()

    // 회원명 검사 실패 시 수정 중단
    if (isNameDuplicate === null || nameCheckError.value) return

    // 중복 이름을 확인하지 않았다면 수정 중단
    if (isNameDuplicate && !isNameDuplicateConfirmed.value) {
      return
    }

    // 저장 직전 연락처 중복 재검사
    const isPhoneAvailable = await checkPhoneDuplicate()

    // 연락처 검사 실패 시 수정 중단
    if (!isPhoneAvailable || phoneCheckError.value) return

    // Supabase 회원 정보 수정
    await updateMember({ name, phone })

    isSuccess = true
  } catch (error) {
    console.error('회원 정보 수정 오류:', error)

    // DB UNIQUE 제약조건으로 중복 차단된 경우
    if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
      phoneError.value = '이미 등록된 연락처입니다.'
    } else {
      editError.value = '회원 정보 수정에 실패했습니다.'
    }
  } finally {
    isSubmitting.value = false
  }

  // 수정 성공 시 모달 닫기
  if (isSuccess) {
    closeEditDialog()
  }
}

// 부모에서 모달 열기 함수를 사용할 수 있도록 공개
defineExpose({
  open: openEditDialog,
})
</script>

<template>
  <!-- 회원 정보 수정 모달 -->
  <dialog
    ref="editDialog"
    aria-labelledby="edit-dialog-title"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
    @cancel="handleCancel"
  >
    <!-- 모달 제목 -->
    <h2 id="edit-dialog-title" class="text-xl font-bold text-slate-900">회원 정보 수정</h2>

    <!-- 모달 설명 -->
    <p class="mt-2 text-sm text-slate-500">회원명과 연락처를 수정할 수 있습니다.</p>

    <!-- 회원 정보 수정 폼 -->
    <form class="mt-6 space-y-5" @submit.prevent="submitEdit">
      <!-- 회원명 -->
      <div>
        <label for="edit-member-name" class="mb-2 block text-sm font-medium text-slate-700">
          회원명
        </label>

        <input
          id="edit-member-name"
          v-model="editMember.name"
          type="text"
          required
          :disabled="isBusy"
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          @input="handleNameInput"
          @blur="checkNameDuplicate"
        />

        <!-- 회원명 중복 경고 -->
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
        <label for="edit-member-phone" class="mb-2 block text-sm font-medium text-slate-700">
          연락처
        </label>

        <input
          id="edit-member-phone"
          :value="editMember.phone"
          type="tel"
          inputmode="numeric"
          maxlength="13"
          required
          :disabled="isBusy"
          :aria-invalid="!!phoneError"
          class="w-full rounded-lg border px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
          :class="phoneError ? 'border-red-500' : 'border-slate-200'"
          @input="handlePhoneInput"
        />

        <!-- 연락처 중복 오류 -->
        <p v-if="phoneError" role="alert" class="mt-2 text-xs text-red-600">
          {{ phoneError }}
        </p>
      </div>

      <!-- 회원 정보 수정 오류 -->
      <p v-if="formError" role="alert" class="text-sm text-red-600">
        {{ formError }}
      </p>

      <!-- 모달 하단 버튼 -->
      <div class="flex justify-end gap-3 pt-2">
        <button
          type="button"
          :disabled="isBusy"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closeEditDialog"
        >
          취소
        </button>

        <button
          type="submit"
          :disabled="isSubmitDisabled"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-500"
        >
          {{ isUpdating ? '수정 중...' : '수정 완료' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
