<script setup lang="ts">
import { Menu } from 'lucide-vue-next'

defineProps<{
  title: string
  menuOpen: boolean
}>()

// 모바일 메뉴 버튼 클릭 이벤트
const emit = defineEmits<{
  (e: 'toggle-menu'): void
}>()
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
    <div class="flex items-center gap-3">
      <div class="hidden text-right sm:block">
        <p class="text-sm font-semibold text-slate-800">트레이너</p>
        <p class="text-xs text-slate-400">관리자</p>
      </div>

      <div
        class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-blue-100 text-sm font-bold text-blue-600 lg:h-10 lg:w-10"
      >
        PT
      </div>
    </div>
  </header>
</template>
