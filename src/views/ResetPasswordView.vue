<script setup lang="ts">
import { ref, onUnmounted } from 'vue'
import { RouterLink } from 'vue-router'
import { Dumbbell } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'

// 비밀번호 입력 데이터
const password = ref('')
const confirmPassword = ref('')

// 비밀번호 변경 상태
const isLoading = ref(false)
const resetError = ref('')
const isSuccess = ref(false)

// 비밀번호 재설정 링크 인증 상태
const isCheckingLink = ref(true)
const isRecoverySession = ref(false)

// Supabase 비밀번호 복구 인증 이벤트 확인
const {
  data: { subscription },
} = supabase.auth.onAuthStateChange((event, session) => {
  // 정상적인 비밀번호 재설정 링크로 인증된 경우
  if (event === 'PASSWORD_RECOVERY' && session) {
    isRecoverySession.value = true
    isCheckingLink.value = false
  }

  // 초기 인증 상태 확인 완료
  if (event === 'INITIAL_SESSION') {
    isCheckingLink.value = false
  }

  // 로그아웃 시 복구 인증 상태 해제
  if (event === 'SIGNED_OUT') {
    isRecoverySession.value = false
  }
})

// 컴포넌트가 사라지면 인증 이벤트 구독 해제
onUnmounted(() => {
  subscription.unsubscribe()
})

// 비밀번호 재설정
async function handleResetPassword() {
  if (isLoading.value) return

  resetError.value = ''

  // 복구 링크 인증 여부 확인
  if (!isRecoverySession.value) {
    resetError.value = '유효한 비밀번호 재설정 링크가 필요합니다.'
    return
  }

  // 비밀번호 길이 검사
  if (password.value.length < 8) {
    resetError.value = '비밀번호는 8자 이상 입력해 주세요.'
    return
  }

  // 비밀번호 일치 검사
  if (password.value !== confirmPassword.value) {
    resetError.value = '비밀번호가 일치하지 않습니다.'
    return
  }

  isLoading.value = true

  try {
    // Supabase 비밀번호 변경
    const { error } = await supabase.auth.updateUser({
      password: password.value,
    })

    if (error) {
      resetError.value = '비밀번호를 변경할 수 없습니다. 재설정 링크를 다시 확인해 주세요.'
      console.error('비밀번호 재설정 오류:', error.message)
      return
    }

    // 비밀번호 변경 완료
    isSuccess.value = true
    password.value = ''
    confirmPassword.value = ''

    // 재설정 후 로그아웃
    await supabase.auth.signOut()
  } catch {
    resetError.value = '비밀번호 변경 중 문제가 발생했습니다.'
  } finally {
    isLoading.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-slate-50 px-4 py-8">
    <div class="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-6 shadow-sm sm:p-8">
      <!-- 로고 -->
      <div class="flex items-center justify-center gap-2">
        <Dumbbell :size="28" class="text-blue-600" aria-hidden="true" />
        <h1 class="text-2xl font-bold text-blue-600">Remind PT</h1>
      </div>

      <!-- 비밀번호 재설정 링크 확인 중 -->
      <div v-if="isCheckingLink" class="mt-8 text-center">
        <p class="text-sm text-slate-500">비밀번호 재설정 링크를 확인하고 있습니다...</p>
      </div>

      <!-- 비밀번호 변경 완료 -->
      <div v-else-if="isSuccess" class="mt-8 text-center">
        <h2 class="text-xl font-semibold text-slate-900">비밀번호 변경 완료</h2>
        <p class="mt-3 text-sm text-slate-500">새로운 비밀번호로 다시 로그인해 주세요.</p>

        <RouterLink
          to="/login"
          class="mt-6 inline-flex w-full justify-center rounded-lg bg-blue-600 px-5 py-3 text-sm font-semibold text-white hover:bg-blue-700"
        >
          로그인 페이지로 이동
        </RouterLink>
      </div>

      <!-- 유효하지 않은 비밀번호 재설정 링크 -->
      <div v-else-if="!isRecoverySession" class="mt-8 text-center">
        <h2 class="text-xl font-semibold text-slate-900">유효하지 않은 링크입니다</h2>

        <p class="mt-3 text-sm text-slate-500 break-keep">
          비밀번호 재설정 링크가 없거나 만료되었습니다. 새로운 재설정 이메일을 요청해 주세요.
        </p>

        <RouterLink
          to="/forgot-password"
          class="mt-6 inline-flex w-full justify-center rounded-lg bg-blue-600 px-5 py-3 text-sm font-semibold text-white hover:bg-blue-700"
        >
          비밀번호 찾기로 이동
        </RouterLink>
      </div>

      <!-- 비밀번호 재설정 폼 -->
      <template v-else>
        <!-- 페이지 제목 -->
        <div class="mt-8 text-center">
          <h2 class="text-xl font-semibold text-slate-900">비밀번호 재설정</h2>
          <p class="mt-2 text-sm text-slate-500">새롭게 사용할 비밀번호를 입력해 주세요.</p>
        </div>

        <form class="mt-8 space-y-5" @submit.prevent="handleResetPassword">
          <!-- 새 비밀번호 -->
          <div>
            <label for="new-password" class="mb-2 block text-sm font-medium text-slate-700">
              새 비밀번호
            </label>
            <input
              id="new-password"
              v-model="password"
              type="password"
              autocomplete="new-password"
              minlength="8"
              required
              placeholder="8자 이상 입력"
              class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500"
            />
          </div>

          <!-- 비밀번호 확인 -->
          <div>
            <label for="confirm-password" class="mb-2 block text-sm font-medium text-slate-700">
              새 비밀번호 확인
            </label>
            <input
              id="confirm-password"
              v-model="confirmPassword"
              type="password"
              autocomplete="new-password"
              required
              placeholder="비밀번호를 다시 입력하세요"
              class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500"
            />
          </div>

          <!-- 오류 메시지 -->
          <p v-if="resetError" role="alert" class="text-sm text-red-600">
            {{ resetError }}
          </p>

          <!-- 비밀번호 변경 버튼 -->
          <button
            type="submit"
            :disabled="isLoading"
            class="w-full rounded-lg bg-blue-600 px-5 py-3 text-sm font-semibold text-white hover:bg-blue-700 disabled:opacity-50"
          >
            {{ isLoading ? '변경 중...' : '비밀번호 변경' }}
          </button>
        </form>

        <!-- 로그인으로 돌아가기 -->
        <div class="mt-6 text-center">
          <RouterLink to="/login" class="text-sm text-slate-500 hover:text-blue-600">
            로그인으로 돌아가기
          </RouterLink>
        </div>
      </template>
    </div>
  </div>
</template>
