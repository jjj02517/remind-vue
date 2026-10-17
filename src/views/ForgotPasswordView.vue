<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink } from 'vue-router'
import { Dumbbell, ArrowLeft } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'

// 이메일 입력 데이터
const email = ref('')

// 비밀번호 재설정 상태
const isLoading = ref(false)
const resetMessage = ref('')
const resetError = ref('')

// 비밀번호 재설정 이메일 요청
async function handleForgotPassword() {
  if (isLoading.value) return

  resetMessage.value = ''
  resetError.value = ''

  const userEmail = email.value.trim()

  // 이메일 입력 확인
  if (!userEmail) {
    resetError.value = '이메일을 입력해 주세요.'
    return
  }

  // 이메일 형식 검사
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

  if (!emailRegex.test(userEmail)) {
    resetError.value = '올바른 이메일 주소를 입력해 주세요.'
    return
  }

  isLoading.value = true

  try {
    // Supabase 비밀번호 재설정 이메일 발송
    const { error } = await supabase.auth.resetPasswordForEmail(userEmail, {
      redirectTo: `${window.location.origin}/reset-password`,
    })

    if (error) {
      // 개발 중 Supabase 오류 확인
      console.error('비밀번호 재설정 오류:', {
        code: error.code,
        message: error.message,
      })

      // 이메일 발송 횟수 제한
      if (error.code === 'over_email_send_rate_limit') {
        resetError.value = '이메일 발송 횟수를 초과했습니다. 잠시 후 다시 시도해 주세요.'
        return
      }

      resetError.value = '메일 발송에 실패했습니다. 잠시 후 다시 시도해 주세요.'
      return
    }

    // 비밀번호 재설정 안내
    resetMessage.value =
      '가입된 이메일이라면 비밀번호 재설정 링크가 발송됩니다. 받은편지함을 확인해 주세요.'
  } catch {
    resetError.value = '요청 중 문제가 발생했습니다. 다시 시도해 주세요.'
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

      <!-- 페이지 제목 -->
      <div class="mt-8 text-center">
        <h2 class="text-xl font-semibold text-slate-900">비밀번호 찾기</h2>
        <p class="mt-2 text-sm text-slate-500 break-keep">
          가입한 이메일을 입력하시면 비밀번호 재설정 링크를 보내드립니다.
        </p>
      </div>

      <!-- 비밀번호 재설정 폼 -->
      <form class="mt-8 space-y-5" @submit.prevent="handleForgotPassword">
        <!-- 이메일 -->
        <div>
          <label for="forgot-email" class="mb-2 block text-sm font-medium text-slate-700">
            이메일
          </label>
          <input
            id="forgot-email"
            v-model="email"
            type="email"
            autocomplete="email"
            required
            placeholder="example@email.com"
            class="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm outline-none focus:border-blue-500"
          />
        </div>

        <!-- 비밀번호 재설정 안내 메시지 -->
        <p v-if="resetMessage" role="status" class="text-sm text-green-600">
          {{ resetMessage }}
        </p>

        <!-- 비밀번호 재설정 오류 메시지 -->
        <p v-if="resetError" role="alert" class="text-sm text-red-600">
          {{ resetError }}
        </p>

        <!-- 재설정 이메일 발송 버튼 -->
        <button
          type="submit"
          :disabled="isLoading"
          class="w-full rounded-lg bg-blue-600 px-5 py-3 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {{ isLoading ? '메일 발송 중...' : '비밀번호 재설정 메일 보내기' }}
        </button>
      </form>

      <!-- 로그인으로 돌아가기 -->
      <div class="mt-6 text-center">
        <RouterLink
          to="/login"
          class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 hover:text-blue-600"
        >
          <ArrowLeft :size="16" aria-hidden="true" />
          로그인으로 돌아가기
        </RouterLink>
      </div>
    </div>
  </div>
</template>
