<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'
import { formatPhone, isValidPhone, normalizePhone } from '@/utils/phone'
import {
  registerMemberWithPt,
  registerMemberOnly,
  registerMemberWithMembership,
  registerMemberWithGroup,
} from '@/api/memberRegistration'
import { useMemberDuplicateCheck } from '@/composables/useMemberDuplicateCheck'
import { getCompanies } from '@/api/companies'
import type { Member } from '@/types/member'
import { blockDemoWrite } from '@/utils/demoGuard'
// 신규 회원 등록 데이터 타입
type NewMember = Pick<Member, 'name' | 'phone' | 'totalSessions'> & {
  memo: string
  startsOn: string
  endsOn: string
}

// 회원 등록 방식
type RegistrationType = 'pt' | 'group' | 'membership' | 'none'

// 회원 등록 요청 데이터 타입

type RegisterMemberParams =
  | {
      registrationType: 'pt' | 'group'
      companyId: string
      name: string
      phone: string
      memo: string
      totalSessions: number
    }
  | {
      registrationType: 'membership'
      companyId: string
      name: string
      phone: string
      memo: string
      startsOn: string
      endsOn: string
    }
  | {
      registrationType: 'none'
      companyId: string
      name: string
      phone: string
      memo: string
    }

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 회원 등록 오류 메시지
const registerError = ref('')

// 회원 등록 모달
const registerDialog = ref<HTMLDialogElement | null>(null)

// 회원 등록 방식 선택
const registrationType = ref<RegistrationType>('pt')

// 등록 모달이 열려 있는지 확인
const isDialogOpen = ref(false)

// 선택한 근무처 ID
const selectedCompanyId = ref('')

// 모달이 열렸을 때 활성 근무처 목록 조회
const {
  data: companies,
  isPending: isCompaniesLoading,
  error: companiesQueryError,
  refetch: refetchCompanies,
} = useQuery({
  queryKey: ['companies'],
  queryFn: getCompanies,
  enabled: computed(() => isDialogOpen.value),
  staleTime: 1000 * 60 * 5,
})

// 보관된 근무처는 신규 회원 등록에서 제외
const activeCompanies = computed(() =>
  (companies.value ?? []).filter((company) => company.is_active),
)

// 근무처 목록을 불러오면 기본 '개인 고객'을 선택
watch([isDialogOpen, activeCompanies], ([isOpen, available]) => {
  if (!isOpen) return

  // 사용자가 선택한 활성 근무처는 유지
  if (available.some((company) => company.id === selectedCompanyId.value)) return

  selectedCompanyId.value =
    available.find((company) => company.company_type === 'personal')?.id ?? ''
})

// 선택한 근무처가 현재 사용 가능한 근무처인지 확인
const isCompanySelectionValid = computed(() =>
  activeCompanies.value.some((company) => company.id === selectedCompanyId.value),
)

// 신규 회원 입력 데이터
const newMember = ref<NewMember>({
  name: '',
  phone: '',
  memo: '',
  totalSessions: 1,
  startsOn: '',
  endsOn: '',
})

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
  // 현재 입력한 회원명과 연락처 전달
  getName: () => newMember.value.name,
  getPhone: () => newMember.value.phone,
})

// Supabase 회원 등록 Mutation
const { mutateAsync: registerMember, isPending: isRegistering } = useMutation({
  // 선택한 등록 방식에 따라 회원 등록
  mutationFn: async (member: RegisterMemberParams) => {
    // PT 이용권과 함께 회원 등록
    if (member.registrationType === 'pt') {
      return registerMemberWithPt({
        companyId: member.companyId,
        name: member.name,
        phone: member.phone,
        memo: member.memo,
        totalSessions: member.totalSessions,
      })
    }

    // 그룹 횟수제 이용권과 함께 회원 등록
    if (member.registrationType === 'group') {
      return registerMemberWithGroup({
        companyId: member.companyId,
        name: member.name,
        phone: member.phone,
        memo: member.memo,
        totalSessions: member.totalSessions,
      })
    }

    // 월 회원권과 함께 회원 등록
    if (member.registrationType === 'membership') {
      return registerMemberWithMembership({
        companyId: member.companyId,
        name: member.name,
        phone: member.phone,
        memo: member.memo,
        startsOn: member.startsOn,
        endsOn: member.endsOn,
      })
    }

    // 이용권 없이 회원 기본 정보만 등록
    return registerMemberOnly({
      companyId: member.companyId,
      name: member.name,
      phone: member.phone,
      memo: member.memo,
    })
  },

  // 등록 성공 시 회원 목록 캐시 무효화
  onSuccess: async () => {
    await queryClient.invalidateQueries({
      queryKey: ['members'],
    })
  },
})

// 등록 직전 중복 검사 진행 상태
const isCheckingDuplicates = ref(false)

// 회원 등록 또는 중복 검사 진행 상태
const isBusy = computed(() => isRegistering.value || isCheckingDuplicates.value || isChecking.value)

// 회원 등록 오류 메시지 통합
const formError = computed(
  () => registerError.value || nameCheckError.value || phoneCheckError.value,
)

// 시작일을 포함하여 30일째 되는 종료일 계산
function addDays(date: string, days: number): string {
  if (!date) return ''

  // 시간대에 따른 날짜 차이를 방지하기 위해 UTC 사용
  const result = new Date(`${date}T00:00:00Z`)
  if (Number.isNaN(result.getTime())) return ''

  result.setUTCDate(result.getUTCDate() + days)
  return result.toISOString().slice(0, 10)
}

// 월 회원권 최소 종료일 (시작일 포함 30일)
const minimumEndsOn = computed(() => addDays(newMember.value.startsOn, 29))

// 월 회원권 기간 유효성 검사
const isMembershipPeriodValid = computed(() => {
  const { startsOn, endsOn } = newMember.value

  // 시작일과 종료일 필수
  if (!startsOn || !endsOn || !minimumEndsOn.value) return false

  // 시작일과 종료일을 포함해 최소 30일 이상
  return endsOn >= minimumEndsOn.value
})

// 월 회원권 기간 오류 표시
const membershipPeriodError = computed(() => {
  const { startsOn, endsOn } = newMember.value

  if (!startsOn || !endsOn) return ''

  // 종료일이 시작일보다 빠른 경우
  if (endsOn < startsOn) {
    return '종료일은 시작일보다 빠를 수 없습니다.'
  }

  // 최소 이용 기간 검사
  if (minimumEndsOn.value && endsOn < minimumEndsOn.value) {
    return '월 회원권은 최소 30일 이상이어야 합니다.'
  }

  return ''
})

// 회원 등록 버튼 비활성화 조건
const isSubmitDisabled = computed(() => {
  // 등록 또는 중복 검사 진행 중
  if (isBusy.value) return true
  // 근무처 조회 중이거나 선택한 근무처가 유효하지 않은 경우
  if (isCompaniesLoading.value || companiesQueryError.value || !isCompanySelectionValid.value) {
    return true
  }
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
  // 이름 또는 연락처 중복 검사 오류 발생
  if (nameCheckError.value || phoneCheckError.value) {
    return true
  }
  // PT 또는 그룹 횟수제 등록 시 횟수 검사
  if (registrationType.value === 'pt' || registrationType.value === 'group') {
    const totalSessions = newMember.value.totalSessions
    if (!Number.isInteger(totalSessions) || totalSessions < 1) {
      return true
    }
  }
  // 월 회원권 등록 시에만 기간 검사
  if (registrationType.value === 'membership' && !isMembershipPeriodValid.value) {
    return true
  }
  return false
})

// 회원명 입력 시 경고 초기화
function handleNameInput() {
  // 이전 이름 중복 검사 상태 초기화
  resetNameCheck()
  registerError.value = ''
}

// 연락처 입력 시 자동 하이픈 처리
function handlePhoneInput(event: Event) {
  const input = event.target as HTMLInputElement
  const formattedPhone = formatPhone(input.value)
  input.value = formattedPhone
  newMember.value.phone = formattedPhone
  // 기존 연락처 중복 검사 결과 초기화
  resetPhoneCheck()
  registerError.value = ''
  // 올바른 11자리 번호가 입력되면 자동 중복 검사
  const phone = normalizePhone(formattedPhone)
  if (isValidPhone(phone)) {
    void checkPhoneDuplicate()
  }
}

// 회원 등록 방식 변경
function handleRegistrationTypeChange() {
  registerError.value = ''
}

// 월 회원권 시작일 변경 시 종료일을 30일째로 자동 설정
function handleMembershipStartDateChange() {
  newMember.value.endsOn = minimumEndsOn.value
  registerError.value = ''
}

// 월 회원권 기간 변경
function handleMembershipPeriodChange() {
  registerError.value = ''
}

// 회원 등록 모달 열기
function openRegisterDialog() {
  if (registerDialog.value?.open) return

  registerError.value = ''
  selectedCompanyId.value = ''
  isDialogOpen.value = true
  registerDialog.value?.showModal()
}

// 모달 종료 시 근무처 조회 중단 및 폼 초기화
function handleDialogClose() {
  isDialogOpen.value = false
  resetForm()
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
  // 회원 기본 정보 초기화
  newMember.value = {
    name: '',
    phone: '',
    memo: '',
    totalSessions: 1,
    startsOn: '',
    endsOn: '',
  }

  // 등록 방식 및 근무처 선택 초기화
  registrationType.value = 'pt'
  selectedCompanyId.value = ''
  registerError.value = ''

  // 이름 및 연락처 중복 검사 상태 초기화
  resetDuplicateCheck()
}

// 신규 회원 등록
async function submitMember() {
  if (isSubmitDisabled.value) return
  if (await blockDemoWrite()) return

  const name = newMember.value.name.trim()
  const phone = normalizePhone(newMember.value.phone)
  const memo = newMember.value.memo.trim()
  const totalSessions = newMember.value.totalSessions
  const startsOn = newMember.value.startsOn
  const endsOn = newMember.value.endsOn
  const selectedRegistrationType = registrationType.value
  const companyId = selectedCompanyId.value

  // 활성 근무처를 선택하지 않은 경우 등록 중단
  if (!activeCompanies.value.some((company) => company.id === companyId)) return
  // 회원명 필수
  if (!name) return
  // PT 또는 그룹 횟수제 등록 시 횟수 검사
  if (
    (selectedRegistrationType === 'pt' || selectedRegistrationType === 'group') &&
    (!Number.isInteger(totalSessions) || totalSessions < 1)
  ) {
    return
  }
  // 월 회원권 등록 시에만 기간 검사
  if (selectedRegistrationType === 'membership' && !isMembershipPeriodValid.value) {
    return
  }
  registerError.value = ''
  isCheckingDuplicates.value = true
  let isSuccess = false
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
    if (
      nameCheckError.value ||
      phoneCheckError.value ||
      isNameDuplicate === null ||
      !isPhoneAvailable
    ) {
      return
    }
    // 중복 이름을 사용자가 확인하지 않았다면 등록 중단
    if (isNameDuplicate && !isNameDuplicateConfirmed.value) {
      return
    }

    // PT 이용권과 함께 회원 등록
    if (selectedRegistrationType === 'pt') {
      await registerMember({
        registrationType: 'pt',
        companyId,
        name,
        phone,
        memo,
        totalSessions,
      })
    }
    // 그룹 횟수제 이용권과 함께 회원 등록
    else if (selectedRegistrationType === 'group') {
      await registerMember({
        registrationType: 'group',
        companyId,
        name,
        phone,
        memo,
        totalSessions,
      })
    }
    // 월 회원권과 함께 회원 등록
    else if (selectedRegistrationType === 'membership') {
      await registerMember({
        registrationType: 'membership',
        companyId,
        name,
        phone,
        memo,
        startsOn,
        endsOn,
      })
    }
    // 이용권 없이 회원만 등록
    else {
      await registerMember({
        registrationType: 'none',
        companyId,
        name,
        phone,
        memo,
      })
    }

    isSuccess = true
  } catch (error) {
    console.error('회원 등록 오류:', error)
    // DB UNIQUE 제약조건으로 중복 차단된 경우
    if (typeof error === 'object' && error !== null && 'code' in error && error.code === '23505') {
      phoneError.value = '이미 등록된 연락처입니다. 기존 회원을 확인해 주세요.'
    } else {
      registerError.value = error instanceof Error ? error.message : '회원 등록에 실패했습니다.'
    }
  } finally {
    isCheckingDuplicates.value = false
  }
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
    @close="handleDialogClose"
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

      <!-- 회원 메모 -->
      <div>
        <label for="member-memo" class="mb-2 block text-sm font-medium text-slate-700">
          회원 메모
          <span class="font-normal text-slate-400">(선택)</span>
        </label>

        <textarea
          id="member-memo"
          v-model="newMember.memo"
          rows="4"
          :disabled="isBusy"
          placeholder="회원에 대해 참고할 사항을 입력해 주세요."
          class="w-full resize-y rounded-lg border border-slate-200 px-4 py-3 text-sm leading-relaxed outline-none focus:border-blue-500 disabled:opacity-50"
        ></textarea>

        <p class="mt-2 text-xs text-slate-400">
          등록한 메모는 회원 상세 및 수업 관리 화면에서 확인할 수 있습니다.
        </p>
      </div>

      <!-- 회원 등록 근무처 선택 -->
      <div>
        <label for="member-company" class="mb-2 block text-sm font-medium text-slate-700">
          근무처
        </label>

        <!-- 근무처 목록 조회 중 -->
        <p v-if="isCompaniesLoading" class="text-sm text-slate-500">근무처 목록을 불러오는 중...</p>

        <!-- 근무처 목록 조회 오류 -->
        <div v-else-if="companiesQueryError" class="space-y-2">
          <p role="alert" class="text-sm text-red-600">근무처 목록을 불러오지 못했습니다.</p>
          <button
            type="button"
            :disabled="isBusy"
            class="text-sm font-medium text-blue-600 underline disabled:opacity-50"
            @click="refetchCompanies()"
          >
            다시 시도
          </button>
        </div>

        <!-- 선택 가능한 근무처 없음 -->
        <p v-else-if="!activeCompanies.length" role="alert" class="text-sm text-amber-700">
          활성 근무처가 없습니다. 근무처 관리에서 확인해 주세요.
        </p>

        <!-- 활성 근무처 중 선택 -->
        <select
          v-else
          id="member-company"
          v-model="selectedCompanyId"
          required
          :disabled="isBusy"
          class="w-full rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        >
          <option value="" disabled>근무처를 선택해 주세요</option>
          <option v-for="company in activeCompanies" :key="company.id" :value="company.id">
            {{ company.name }}{{ company.company_type === 'personal' ? ' (기본)' : '' }}
          </option>
        </select>

        <!-- 회원 등록 시 선택한 근무처에 회원과 이용권 연결 -->
        <p class="mt-2 text-xs text-slate-500">선택한 근무처에 회원과 이용권이 연결됩니다.</p>
      </div>
      <!-- 회원 등록 방식 선택 -->
      <fieldset :disabled="isBusy">
        <legend class="mb-3 text-sm font-medium text-slate-700">이용권 등록</legend>
        <div class="grid grid-cols-1 gap-3">
          <!-- PT 이용권 등록 -->
          <label
            class="flex cursor-pointer items-center gap-3 rounded-lg border p-4 transition"
            :class="
              registrationType === 'pt'
                ? 'border-blue-500 bg-blue-50'
                : 'border-slate-200 hover:bg-slate-50'
            "
          >
            <input
              v-model="registrationType"
              type="radio"
              value="pt"
              name="registration-type"
              class="h-4 w-4 accent-blue-600"
              @change="handleRegistrationTypeChange"
            />
            <span class="text-sm font-medium text-slate-700"> PT 이용권 </span>
          </label>
          <!-- 그룹 횟수제 이용권 등록 -->
          <label
            class="flex cursor-pointer items-center gap-3 rounded-lg border p-4 transition"
            :class="
              registrationType === 'group'
                ? 'border-blue-500 bg-blue-50'
                : 'border-slate-200 hover:bg-slate-50'
            "
          >
            <input
              v-model="registrationType"
              type="radio"
              value="group"
              name="registration-type"
              class="h-4 w-4 accent-blue-600"
              @change="handleRegistrationTypeChange"
            />
            <span class="text-sm font-medium text-slate-700"> 그룹 횟수제 </span>
          </label>
          <!-- 월 회원권 등록 -->
          <label
            class="flex cursor-pointer items-center gap-3 rounded-lg border p-4 transition"
            :class="
              registrationType === 'membership'
                ? 'border-blue-500 bg-blue-50'
                : 'border-slate-200 hover:bg-slate-50'
            "
          >
            <input
              v-model="registrationType"
              type="radio"
              value="membership"
              name="registration-type"
              class="h-4 w-4 accent-blue-600"
              @change="handleRegistrationTypeChange"
            />
            <span class="text-sm font-medium text-slate-700"> 월 회원권 </span>
          </label>
          <!-- 이용권 없이 회원만 등록 -->
          <label
            class="flex cursor-pointer items-center gap-3 rounded-lg border p-4 transition"
            :class="
              registrationType === 'none'
                ? 'border-blue-500 bg-blue-50'
                : 'border-slate-200 hover:bg-slate-50'
            "
          >
            <input
              v-model="registrationType"
              type="radio"
              value="none"
              name="registration-type"
              class="h-4 w-4 accent-blue-600"
              @change="handleRegistrationTypeChange"
            />
            <span class="text-sm font-medium text-slate-700"> 회원만 등록 </span>
          </label>
        </div>
      </fieldset>
      <!-- PT 및 그룹 횟수제 이용권 횟수 -->
      <div v-if="registrationType === 'pt' || registrationType === 'group'">
        <label for="member-sessions" class="mb-2 block text-sm font-medium text-slate-700">
          {{ registrationType === 'pt' ? '총 PT 횟수' : '총 그룹 수업 횟수' }}
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
      <!-- 월 회원권 기간 -->
      <div v-if="registrationType === 'membership'" class="space-y-4">
        <!-- 이용권 시작일 -->
        <div>
          <label for="membership-starts-on" class="mb-2 block text-sm font-medium text-slate-700">
            이용 시작일
          </label>
          <input
            id="membership-starts-on"
            v-model="newMember.startsOn"
            type="date"
            required
            :disabled="isBusy"
            class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
            @change="handleMembershipStartDateChange"
          />
        </div>
        <!-- 이용권 종료일 -->
        <div>
          <label for="membership-ends-on" class="mb-2 block text-sm font-medium text-slate-700">
            이용 종료일
          </label>
          <input
            id="membership-ends-on"
            v-model="newMember.endsOn"
            type="date"
            required
            :min="minimumEndsOn || undefined"
            :disabled="isBusy || !newMember.startsOn"
            class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
            @change="handleMembershipPeriodChange"
          />
        </div>
        <!-- 월 회원권 최소 이용 기간 안내 -->
        <p v-if="minimumEndsOn" class="mt-2 text-xs text-slate-500">
          최소 종료일: {{ minimumEndsOn.replaceAll('-', '.') }}
          (시작일 포함 30일)
        </p>
        <!-- 이용권 기간 유효성 검사 -->
        <p v-if="membershipPeriodError" role="alert" class="text-sm text-red-600">
          {{ membershipPeriodError }}
        </p>
        <!-- 월 회원권 등록 안내 -->
        <p class="rounded-lg bg-slate-50 px-4 py-3 text-sm text-slate-600">
          월 회원권은 시작일과 종료일을 포함하여 최소 30일 이상 등록해야 합니다.
        </p>
      </div>
      <!-- 이용권 없이 등록하는 경우 안내 -->
      <p
        v-if="registrationType === 'none'"
        class="rounded-lg bg-slate-50 px-4 py-3 text-sm text-slate-600"
      >
        회원 정보만 등록합니다. 이용권은 회원 상세 페이지에서 나중에 추가할 수 있습니다.
      </p>
      <!-- 회원 등록 오류 메시지 -->
      <p v-if="formError" role="alert" class="text-sm text-red-600">
        {{ formError }}
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
