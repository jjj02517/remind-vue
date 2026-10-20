<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { formatPhone, isValidPhone, normalizePhone } from '@/utils/phone'
import { useMemberStore } from '@/stores/members'
import type { Member } from '@/types/member'

// 신규 회원 등록 데이터 타입
type NewMember = Pick<Member, 'name' | 'phone' | 'totalSessions'>

// 회원 데이터 Store
const memberStore = useMemberStore()

// 회원 등록 상태
const { isRegistering, registerError } = storeToRefs(memberStore)

// 회원 등록 모달
const registerDialog = ref<HTMLDialogElement | null>(null)

// 신규 회원 입력 데이터
const newMember = ref<NewMember>({
  name: '',
  phone: '',
  totalSessions: 1,
})

// 연락처 유효성 검사 메시지
const phoneError = ref('')

// 연락처 입력 시 자동 하이픈 처리
function handlePhoneInput(event: Event) {
  const input = event.target as HTMLInputElement

  const formattedPhone = formatPhone(input.value)

  input.value = formattedPhone
  newMember.value.phone = formattedPhone

  phoneError.value = ''
}

// 회원 등록 모달 열기
function openRegisterDialog() {
  registerError.value = ''
  registerDialog.value?.showModal()
}

// 회원 등록 모달 닫기
function closeRegisterDialog() {
  if (isRegistering.value) return

  registerDialog.value?.close()
}

// 등록 중 ESC로 모달이 닫히지 않도록 처리
function handleCancel(event: Event) {
  if (isRegistering.value) {
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

  phoneError.value = ''
  registerError.value = ''
}

// 신규 회원 등록
async function submitMember() {
  if (isRegistering.value) return

  const name = newMember.value.name.trim()
  const phone = normalizePhone(newMember.value.phone)
  const totalSessions = newMember.value.totalSessions

  if (!name || !Number.isInteger(totalSessions) || totalSessions < 1) {
    return
  }

  // 연락처 유효성 검사
  if (!isValidPhone(phone)) {
    phoneError.value = '010으로 시작하는 11자리 휴대폰 번호를 입력해 주세요.'
    return
  }

  // Supabase 회원 및 PT 이용권 등록
  const isSuccess = await memberStore.registerMember({
    name,
    phone,
    totalSessions,
  })

  // 등록 성공 시 모달 닫기
  if (isSuccess) {
    closeRegisterDialog()
  }
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
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500"
        />
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
          class="w-full rounded-lg border px-4 py-3 text-sm outline-none focus:border-blue-500"
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
          class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500"
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
          :disabled="isRegistering"
          class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          @click="closeRegisterDialog"
        >
          취소
        </button>

        <button
          type="submit"
          :disabled="isRegistering"
          class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {{ isRegistering ? '등록 중...' : '회원 등록' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
