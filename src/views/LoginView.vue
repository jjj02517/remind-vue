<script setup lang="ts">
import { computed, ref } from 'vue'
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
const isDemoLoading = ref(false)
const loginError = ref('')

// 로그인 또는 데모 연결 진행 중
const isBusy = computed(() => isLoading.value || isDemoLoading.value)

// 비밀번호 표시 여부
const showPassword = ref(false)

// 비밀번호 입력값 삭제
function clearPassword() {
  password.value = ''
  showPassword.value = false
}

// 트레이너 로그인
async function handleLogin() {
  if (isBusy.value) return

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

// 데모 둘러보기
async function handleDemo() {
  if (isBusy.value) return

  isDemoLoading.value = true
  loginError.value = ''

  try {
    // 기존 로그인 세션 확인
    const { data, error: sessionError } = await supabase.auth.getSession()

    if (sessionError) {
      throw sessionError
    }

    const session = data.session

    // 일반 로그인 계정이 유지 중이면 데모 계정으로 전환하지 않음
    if (session && !session.user.is_anonymous) {
      loginError.value = '데모를 이용하려면 먼저 로그아웃해 주세요.'
      return
    }

    // 기존 익명 세션이 없다면 새로운 익명 세션 생성
    if (!session) {
      const { error } = await supabase.auth.signInAnonymously()

      if (error) {
        throw error
      }
    }

    // 데모 인증 완료 후 대시보드로 이동
    await router.replace('/')
  } catch (error) {
    console.error('Supabase 데모 연결 오류:', error)

    loginError.value = '데모에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.'
  } finally {
    isDemoLoading.value = false
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
          :disabled="isBusy"
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

      <!-- 데모 둘러보기 구분선 -->
      <div class="my-6 flex items-center gap-3">
        <div class="h-px flex-1 bg-slate-200"></div>
        <span class="text-xs text-slate-400">또는</span>
        <div class="h-px flex-1 bg-slate-200"></div>
      </div>

      <!-- 데모 둘러보기 버튼 -->
      <button
        type="button"
        :disabled="isBusy"
        class="flex w-full items-center justify-center gap-2 rounded-lg border border-slate-200 bg-white px-5 py-3 text-sm font-semibold text-slate-700 transition hover:border-blue-300 hover:bg-blue-50 hover:text-blue-600 disabled:cursor-not-allowed disabled:opacity-50"
        @click="handleDemo"
      >
        <Eye :size="18" aria-hidden="true" />
        {{ isDemoLoading ? '데모 연결 중...' : '데모 둘러보기' }}
      </button>

      <!-- 데모 안내 -->
      <p class="mt-3 text-center text-xs leading-relaxed text-slate-400 break-keep">
        회원가입 없이 샘플 데이터로 Remind PT를 체험해 보세요.
        <span class="block">데모에서는 데이터 조회만 가능합니다.</span>
      </p>
    </div>
  </div>
</template>
