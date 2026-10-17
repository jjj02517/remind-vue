<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Dumbbell, X, Eye, EyeOff } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'

// Vue Router
const route = useRoute()
const router = useRouter()

// 로그인 입력 데이터
const email = ref('')
const password = ref('')

// 로그인 상태
const isLoading = ref(false)
const loginError = ref('')

// 비밀번호 표시 여부
const showPassword = ref(false)

// 비밀번호 입력값 삭제
function clearPassword() {
  password.value = ''
  showPassword.value = false
}

// 트레이너 로그인
async function handleLogin() {
  if (isLoading.value) return

  isLoading.value = true
  loginError.value = ''

  try {
    // Supabase 이메일 / 비밀번호 인증
    const { error } = await supabase.auth.signInWithPassword({
      email: email.value.trim(),
      password: password.value,
    })

    if (error) {
      // 개발 중 Supabase 인증 오류 확인
      console.error('Supabase 로그인 오류:', {
        code: error.code,
        message: error.message,
        status: error.status,
      })

      loginError.value = '이메일 또는 비밀번호를 확인해 주세요.'
      return
    }

    // 로그인 성공 시 원래 접근하려던 페이지로 이동
    const redirect = route.query.redirect

    // 안전한 내부 경로인지 확인
    const targetPath =
      typeof redirect === 'string' &&
      redirect.startsWith('/') &&
      !redirect.startsWith('//') &&
      !redirect.includes('\\')
        ? redirect
        : '/'

    await router.replace(targetPath)
  } catch {
    loginError.value = '로그인 중 문제가 발생했습니다. 다시 시도해 주세요.'
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
        <h2 class="text-xl font-semibold text-slate-900">트레이너 로그인</h2>
        <p class="mt-2 text-sm text-slate-500 break-keep">
          계정에 로그인하여 회원과 수업을 관리하세요.
        </p>
      </div>

      <!-- 로그인 폼 -->
      <form class="mt-8 space-y-5" @submit.prevent="handleLogin">
        <!-- 이메일 -->
        <div>
          <label for="email" class="mb-2 block text-sm font-medium text-slate-700"> 이메일 </label>

          <div class="relative">
            <input
              id="email"
              v-model="email"
              type="email"
              autocomplete="username"
              required
              placeholder="example@email.com"
              class="w-full rounded-lg border border-slate-200 px-4 py-3 pr-10 text-sm outline-none focus:border-blue-500"
            />

            <!-- 이메일 입력값 삭제 버튼 -->
            <button
              v-if="email"
              type="button"
              aria-label="이메일 지우기"
              class="absolute top-1/2 right-3 -translate-y-1/2 text-slate-400 hover:text-slate-600"
              @click="email = ''"
            >
              <X :size="18" aria-hidden="true" />
            </button>
          </div>
        </div>

        <!-- 비밀번호 -->
        <div>
          <label for="password" class="mb-2 block text-sm font-medium text-slate-700">
            비밀번호
          </label>

          <div class="relative">
            <input
              id="password"
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              autocomplete="current-password"
              required
              placeholder="비밀번호를 입력하세요"
              class="w-full rounded-lg border border-slate-200 px-4 py-3 pr-20 text-sm outline-none focus:border-blue-500"
            />

            <!-- 비밀번호 입력값 삭제 버튼 -->
            <button
              v-if="password"
              type="button"
              aria-label="비밀번호 지우기"
              class="absolute top-1/2 right-11 -translate-y-1/2 text-slate-400 hover:text-slate-600"
              @click="clearPassword"
            >
              <X :size="18" aria-hidden="true" />
            </button>

            <!-- 비밀번호 보기 / 숨기기 버튼 -->
            <button
              type="button"
              :aria-label="showPassword ? '비밀번호 숨기기' : '비밀번호 보기'"
              :aria-pressed="showPassword"
              class="absolute top-1/2 right-3 -translate-y-1/2 text-slate-400 hover:text-slate-600"
              @click="showPassword = !showPassword"
            >
              <EyeOff v-if="showPassword" :size="18" aria-hidden="true" />
              <Eye v-else :size="18" aria-hidden="true" />
            </button>
          </div>
        </div>

        <!-- 로그인 오류 메시지 -->
        <p v-if="loginError" role="alert" class="text-sm text-red-600">
          {{ loginError }}
        </p>

        <!-- 로그인 버튼 -->
        <button
          type="submit"
          :disabled="isLoading"
          class="w-full rounded-lg bg-blue-600 px-5 py-3 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {{ isLoading ? '로그인 중...' : '로그인' }}
        </button>

        <!-- 비밀번호 재설정 -->
        <div class="text-center">
          <RouterLink
            to="/forgot-password"
            class="text-sm font-medium text-blue-600 hover:underline"
          >
            비밀번호를 잊으셨나요?
          </RouterLink>
        </div>
      </form>
    </div>
  </div>
</template>
