<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { FunctionsHttpError } from '@supabase/supabase-js'
import { Eye, EyeOff, Trash2, X } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'

// Vue Router
const router = useRouter()

// 회원 탈퇴 확인 모달
const deleteDialog = ref<HTMLDialogElement | null>(null)

// 탈퇴 확인 입력값
const password = ref('')
const confirmationText = ref('')

// 비밀번호 표시 여부
const showPassword = ref(false)

// 탈퇴 처리 상태
const isDeleting = ref(false)
const isDeleted = ref(false)
const deleteError = ref('')
const openError = ref('')

// 탈퇴 확인 문구
const REQUIRED_CONFIRMATION = '탈퇴합니다'

// 최종 탈퇴 버튼 활성화 조건
const canDelete = computed(
  () =>
    !isDeleting.value &&
    !isDeleted.value &&
    password.value.length > 0 &&
    confirmationText.value.trim() === REQUIRED_CONFIRMATION,
)

// 탈퇴 입력값 초기화
function resetForm() {
  password.value = ''
  confirmationText.value = ''
  showPassword.value = false
  deleteError.value = ''
}

// 회원 탈퇴 모달 열기
async function openDeleteDialog() {
  if (isDeleting.value || isDeleted.value) return

  openError.value = ''
  resetForm()

  try {
    // 현재 로그인한 사용자 확인
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser()

    if (error || !user) {
      openError.value = '로그인 정보를 확인할 수 없습니다.'
      return
    }

    // 데모 계정은 탈퇴 기능 사용 불가
    if (user.is_anonymous) {
      openError.value = '데모 계정은 회원 탈퇴를 할 수 없습니다.'
      return
    }

    deleteDialog.value?.showModal()
  } catch (error) {
    console.error('탈퇴 사용자 확인 오류:', error)
    openError.value = '로그인 정보를 확인하지 못했습니다.'
  }
}

// 회원 탈퇴 모달 닫기
function closeDeleteDialog() {
  if (isDeleting.value) return

  deleteDialog.value?.close()
  resetForm()
}

// ESC 키로 모달 닫기
function handleCancel() {
  closeDeleteDialog()
}

// 회원 탈퇴 요청
async function handleDeleteAccount() {
  if (!canDelete.value) return

  isDeleting.value = true
  deleteError.value = ''

  try {
    // Supabase Edge Function 호출
    // 서버에서 본인 인증, 데이터 정리, 계정 삭제 처리
    const { error } = await supabase.functions.invoke('delete-account', {
      body: {
        confirm: 'DELETE_MY_ACCOUNT',
        password: password.value,
      },
    })

    if (error) {
      let message = '회원 탈퇴에 실패했습니다.'

      // Edge Function에서 반환한 오류 메시지 확인
      if (error instanceof FunctionsHttpError) {
        try {
          const response = (await error.context.json()) as {
            message?: string
          }

          if (response.message) {
            message = response.message
          }
        } catch {
          message = error.message
        }
      } else {
        message = error.message
      }

      throw new Error(message)
    }

    // 서버에서 탈퇴가 완료된 상태
    isDeleted.value = true
    password.value = ''

    // 브라우저의 로그인 세션 정리
    const { error: signOutError } = await supabase.auth.signOut({
      scope: 'local',
    })

    if (signOutError) {
      console.error('탈퇴 후 로그아웃 오류:', signOutError)

      deleteError.value =
        '계정 삭제는 완료됐지만 로그아웃 처리에 실패했습니다. 관리자에게 문의해 주세요.'
      return
    }

    // 탈퇴 완료 후 로그인 페이지로 이동
    await router.replace('/login')
  } catch (error) {
    console.error('회원 탈퇴 오류:', error)

    deleteError.value = isDeleted.value
      ? '계정 삭제는 완료됐지만 화면 이동 중 문제가 발생했습니다.'
      : error instanceof Error
        ? error.message
        : '회원 탈퇴 중 문제가 발생했습니다.'
  } finally {
    isDeleting.value = false
  }
}
</script>

<template>
  <div>
    <!-- 회원 탈퇴 버튼 -->
    <button
      type="button"
      class="inline-flex items-center gap-1.5 rounded px-0 py-1 text-xs font-normal text-slate-400 transition hover:text-red-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
      @click="openDeleteDialog"
    >
      <Trash2 :size="14" aria-hidden="true" />
      회원 탈퇴
    </button>

    <!-- 탈퇴 모달 열기 오류 -->
    <p v-if="openError" role="alert" class="mt-2 text-sm text-red-600">
      {{ openError }}
    </p>

    <!-- 회원 탈퇴 확인 모달 -->
    <dialog
      ref="deleteDialog"
      aria-labelledby="delete-account-title"
      aria-describedby="delete-account-description"
      class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
      @cancel.prevent="handleCancel"
    >
      <!-- 모달 제목 및 닫기 -->
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 id="delete-account-title" class="text-xl font-bold text-slate-900">회원 탈퇴</h2>

          <p
            id="delete-account-description"
            class="mt-2 text-sm leading-relaxed text-slate-500 break-keep"
          >
            Remind PT 계정과 연결된 데이터를 영구적으로 삭제합니다.
          </p>
        </div>

        <button
          type="button"
          aria-label="닫기"
          :disabled="isDeleting"
          class="text-slate-400 hover:text-slate-600 disabled:opacity-50"
          @click="closeDeleteDialog"
        >
          <X :size="20" aria-hidden="true" />
        </button>
      </div>

      <!-- 탈퇴 시 삭제되는 데이터 안내 -->
      <div class="mt-6 rounded-xl border border-red-200 bg-red-50 p-4">
        <p class="text-sm font-semibold text-red-700">탈퇴 전 반드시 확인해 주세요.</p>

        <p class="mt-2 text-sm leading-relaxed text-red-700 break-keep">
          탈퇴하면 트레이너 계정과 등록된 근무처, 회원 정보, 이용권, 수업 기록 및 출석 이력이
          삭제됩니다. 삭제된 데이터는 복구할 수 없습니다.
        </p>
      </div>

      <!-- 탈퇴 확인 폼 -->
      <form class="mt-6 space-y-5" @submit.prevent="handleDeleteAccount">
        <!-- 현재 비밀번호 확인 -->
        <div>
          <label for="delete-password" class="mb-2 block text-sm font-medium text-slate-700">
            현재 비밀번호
          </label>

          <div class="relative">
            <input
              id="delete-password"
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              autocomplete="current-password"
              required
              :disabled="isDeleting || isDeleted"
              placeholder="현재 비밀번호를 입력하세요"
              class="w-full rounded-lg border border-slate-200 px-4 py-3 pr-12 text-sm outline-none focus:border-red-500 disabled:opacity-50"
            />

            <!-- 비밀번호 표시 및 숨기기 -->
            <button
              type="button"
              :disabled="isDeleting || isDeleted"
              :aria-label="showPassword ? '비밀번호 숨기기' : '비밀번호 보기'"
              class="absolute top-1/2 right-3 -translate-y-1/2 text-slate-400 hover:text-slate-600 disabled:opacity-50"
              @click="showPassword = !showPassword"
            >
              <EyeOff v-if="showPassword" :size="18" aria-hidden="true" />
              <Eye v-else :size="18" aria-hidden="true" />
            </button>
          </div>
        </div>

        <!-- 탈퇴 확인 문구 -->
        <div>
          <label for="delete-confirmation" class="mb-2 block text-sm font-medium text-slate-700">
            탈퇴 확인
          </label>

          <p class="mb-2 text-xs text-slate-500">
            아래 문구를 정확히 입력해 주세요.
            <strong class="text-red-600">탈퇴합니다</strong>
          </p>

          <input
            id="delete-confirmation"
            v-model="confirmationText"
            type="text"
            autocomplete="off"
            required
            :disabled="isDeleting || isDeleted"
            placeholder="탈퇴합니다"
            class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-red-500 disabled:opacity-50"
          />
        </div>

        <!-- 탈퇴 처리 오류 -->
        <p v-if="deleteError" role="alert" class="text-sm text-red-600">
          {{ deleteError }}
        </p>

        <!-- 탈퇴 및 취소 버튼 -->
        <div class="flex justify-end gap-3">
          <button
            type="button"
            :disabled="isDeleting"
            class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 transition hover:bg-slate-50 disabled:opacity-50"
            @click="closeDeleteDialog"
          >
            취소
          </button>

          <button
            type="submit"
            :disabled="!canDelete"
            class="rounded-lg bg-red-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-slate-300"
          >
            {{ isDeleting ? '탈퇴 처리 중...' : '회원 탈퇴' }}
          </button>
        </div>
      </form>
    </dialog>
  </div>
</template>
