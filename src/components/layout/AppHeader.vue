<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { Menu, LogOut } from 'lucide-vue-next'

import { supabase } from '@/lib/supabase'

defineProps<{
  title: string
  menuOpen: boolean
}>()

// 모바일 메뉴 버튼 클릭 이벤트
const emit = defineEmits<{
  (e: 'toggle-menu'): void
  (e: 'logout'): void
}>()

// 로그인한 트레이너 정보
const trainerEmail = ref('')

// 프로필 메뉴 상태
const isProfileOpen = ref(false)
const profileRef = ref<HTMLElement | null>(null)

// 이메일 첫 글자
const profileInitial = computed(() => {
  return trainerEmail.value.charAt(0).toUpperCase() || '?'
})

// 로그인한 트레이너 정보 가져오기
async function fetchTrainer() {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()

  if (error) {
    console.error('트레이너 정보 조회 오류:', error.message)
    return
  }

  trainerEmail.value = user?.email ?? ''
}

// 프로필 메뉴 열기 / 닫기
function toggleProfile() {
  isProfileOpen.value = !isProfileOpen.value
}

// 프로필 메뉴 바깥 클릭 시 닫기
function handleOutsideClick(event: PointerEvent) {
  if (!profileRef.value?.contains(event.target as Node)) {
    isProfileOpen.value = false
  }
}

// 프로필 메뉴 로그아웃
function handleProfileLogout() {
  isProfileOpen.value = false
  emit('logout')
}

// 컴포넌트가 화면에 표시될 때
onMounted(() => {
  fetchTrainer()
  document.addEventListener('pointerdown', handleOutsideClick)
})

// 컴포넌트가 사라질 때
onUnmounted(() => {
  document.removeEventListener('pointerdown', handleOutsideClick)
})
</script>

<template>
  <header
    class="flex h-16 items-center justify-between border-b border-slate-200 bg-white px-4 sm:px-6 lg:h-20 lg:px-8"
  >
    <!-- 왼쪽: 페이지 제목 -->
    <div class="flex min-w-0 items-center gap-3">
      <!-- 모바일 메뉴 버튼 -->
      <button
        type="button"
        class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-slate-600 hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-blue-600 lg:hidden"
        aria-label="메뉴 열기"
        aria-controls="mobile-navigation"
        :aria-expanded="menuOpen"
        @click="emit('toggle-menu')"
      >
        <Menu :size="24" aria-hidden="true" />
      </button>

      <h2 class="truncate text-lg font-semibold text-slate-800 lg:text-xl">
        {{ title }}
      </h2>
    </div>

    <!-- 오른쪽: 트레이너 정보 -->
    <div ref="profileRef" class="relative flex shrink-0 items-center gap-3">
      <div class="hidden text-right sm:block">
        <p class="text-sm font-semibold text-slate-800">트레이너</p>
        <p class="max-w-48 truncate text-xs text-slate-400">
          {{ trainerEmail || '계정 정보 확인 중' }}
        </p>
      </div>

      <!-- 프로필 아이콘 -->
      <button
        type="button"
        aria-label="계정 메뉴"
        aria-haspopup="true"
        :aria-expanded="isProfileOpen"
        class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-blue-100 text-sm font-bold text-blue-600 hover:bg-blue-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600 lg:h-10 lg:w-10"
        @click="toggleProfile"
        @keydown.esc="isProfileOpen = false"
      >
        {{ profileInitial }}
      </button>

      <!-- 프로필 드롭다운 메뉴 -->
      <div
        v-if="isProfileOpen"
        class="absolute top-full right-0 z-50 mt-3 w-64 rounded-xl border border-slate-200 bg-white p-3 shadow-lg"
        @keydown.esc="isProfileOpen = false"
      >
        <!-- 계정 정보 -->
        <div class="flex items-center gap-3 px-2 py-2">
          <div
            class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-blue-100 font-bold text-blue-600"
          >
            {{ profileInitial }}
          </div>

          <div class="min-w-0">
            <p class="text-sm font-semibold text-slate-800">트레이너</p>
            <p class="truncate text-xs text-slate-500" :title="trainerEmail">
              {{ trainerEmail }}
            </p>
          </div>
        </div>

        <!-- 로그아웃 -->
        <div class="mt-2 border-t border-slate-200 pt-2">
          <button
            type="button"
            class="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm text-slate-600 hover:bg-red-50 hover:text-red-600"
            @click="handleProfileLogout"
          >
            <LogOut :size="18" aria-hidden="true" />
            로그아웃
          </button>
        </div>
      </div>
    </div>
  </header>
</template>
