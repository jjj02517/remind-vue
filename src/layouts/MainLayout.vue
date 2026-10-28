<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { Info, X } from 'lucide-vue-next'

import { getTrainerContext } from '@/api/trainerContext'
import AppSidebar from '@/components/layout/AppSidebar.vue'
import AppHeader from '@/components/layout/AppHeader.vue'

const route = useRoute()
const router = useRouter()

// 데모 사용자 여부
const isDemo = ref(false)

// 공통 레이아웃 진입 시 데모 모드 확인
onMounted(async () => {
  try {
    const context = await getTrainerContext()
    isDemo.value = context.isDemo
  } catch (error) {
    console.error('데모 모드 확인 오류:', error)
  }
})

// 모바일 메뉴 열림 상태
const isSidebarOpen = ref(false)
const mobileMenuRef = ref<HTMLElement | null>(null)
const closeButtonRef = ref<HTMLButtonElement | null>(null)

// 현재 페이지 제목
const pageTitle = computed(() => {
  return String(route.meta.title ?? '대시보드')
})

// 모바일 메뉴 열기
async function openSidebar() {
  isSidebarOpen.value = true
  await nextTick()
  closeButtonRef.value?.focus()
}

// 모바일 메뉴 닫기
function closeSidebar() {
  if (!isSidebarOpen.value) return
  isSidebarOpen.value = false

  nextTick(() => {
    document.querySelector<HTMLButtonElement>('[aria-controls="mobile-navigation"]')?.focus()
  })
}

// 키보드 접근성
function handleMenuKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    closeSidebar()
    return
  }

  if (event.key !== 'Tab' || !mobileMenuRef.value) return

  const focusableElements = Array.from(
    mobileMenuRef.value.querySelectorAll<HTMLElement>(
      'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])',
    ),
  )

  const firstElement = focusableElements[0]
  const lastElement = focusableElements[focusableElements.length - 1]

  if (!firstElement || !lastElement) return

  if (event.shiftKey && document.activeElement === firstElement) {
    event.preventDefault()
    lastElement.focus()
  } else if (!event.shiftKey && document.activeElement === lastElement) {
    event.preventDefault()
    firstElement.focus()
  }
}

// 트레이너 로그아웃
async function handleLogout() {
  // Supabase 로그인 세션 종료
  const { error } = await supabase.auth.signOut()

  if (error) {
    console.error('로그아웃 오류:', error.message)
    alert('로그아웃에 실패했습니다. 다시 시도해 주세요.')
    return
  }

  // 모바일 메뉴 닫기
  isSidebarOpen.value = false

  // 로그인 페이지로 이동
  await router.replace('/login')
}

// 페이지 이동 시 모바일 메뉴 닫기
watch(
  () => route.fullPath,
  () => {
    closeSidebar()
  },
)
</script>

<template>
  <div class="min-h-screen bg-slate-50 lg:flex">
    <!-- 왼쪽 사이드바 -->
    <div class="hidden lg:block">
      <AppSidebar @logout="handleLogout" />
    </div>

    <!-- 모바일 사이드바 배경 -->
    <div
      v-if="isSidebarOpen"
      class="fixed inset-0 z-40 bg-black/40 lg:hidden"
      aria-hidden="true"
      @click="closeSidebar"
    ></div>

    <!-- 모바일 사이드바 -->
    <div
      v-show="isSidebarOpen"
      id="mobile-navigation"
      ref="mobileMenuRef"
      role="dialog"
      aria-modal="true"
      aria-label="모바일 메뉴"
      class="fixed inset-y-0 left-0 z-50 lg:hidden"
      @keydown="handleMenuKeydown"
    >
      <!-- 모바일 메뉴 닫기 버튼 -->
      <button
        ref="closeButtonRef"
        type="button"
        aria-label="메뉴 닫기"
        class="absolute top-5 right-3 z-10 flex h-10 w-10 items-center justify-center rounded-lg text-slate-600 hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-blue-600"
        @click="closeSidebar"
      >
        <X :size="22" aria-hidden="true" />
      </button>

      <AppSidebar @navigate="closeSidebar" @logout="handleLogout" />
    </div>

    <!-- 오른쪽 영역 -->
    <div class="flex min-w-0 flex-1 flex-col">
      <!-- 상단 헤더 -->
      <AppHeader
        :title="pageTitle"
        :menu-open="isSidebarOpen"
        @toggle-menu="isSidebarOpen ? closeSidebar() : openSidebar()"
        @logout="handleLogout"
      />

      <!-- 데모 모드 안내 -->
      <div
        v-if="isDemo"
        role="note"
        class="mx-4 mt-4 flex items-start gap-3 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-800 sm:mx-6 lg:mx-8"
      >
        <Info :size="18" class="mt-0.5 shrink-0 text-blue-600" aria-hidden="true" />

        <p class="leading-relaxed">
          <span class="font-semibold">데모 체험 모드입니다.</span>
          샘플 데이터를 조회할 수 있으며, 등록·수정·삭제 기능은 제한됩니다.
        </p>
      </div>

      <!-- 페이지 콘텐츠 -->
      <main class="min-w-0 flex-1 p-4 sm:p-6 lg:p-8">
        <RouterView />
      </main>
    </div>
  </div>
</template>
