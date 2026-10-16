<script setup lang="ts">
import { Dumbbell, LayoutDashboard, Users, CalendarDays } from 'lucide-vue-next'

// 메뉴 선택 이벤트
const emit = defineEmits<{
  (e: 'navigate'): void
}>()

const menus = [
  { name: '대시보드', icon: LayoutDashboard, path: '/' },
  { name: '회원 관리', icon: Users, path: '/members' },
  { name: '수업 관리', icon: CalendarDays, path: '/sessions' },
]
</script>

<template>
  <aside class="flex h-screen w-64 flex-col border-r border-slate-200 bg-white">
    <!-- 로고 -->
    <div class="flex h-20 items-center gap-2 border-b border-slate-200 px-6">
      <Dumbbell :size="24" class="text-blue-600" />
      <h1 class="text-xl font-bold text-blue-600">Remind PT</h1>
    </div>

    <!-- 메뉴 -->
    <nav aria-label="주 메뉴" class="flex-1 space-y-2 p-4">
      <RouterLink
        v-for="menu in menus"
        :key="menu.path"
        :to="menu.path"
        class="flex items-center gap-3 rounded-lg px-4 py-3 text-slate-600 transition hover:bg-blue-50 hover:text-blue-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
        exact-active-class="bg-blue-50 text-blue-600"
        @click="emit('navigate')"
      >
        <component :is="menu.icon" :size="20" aria-hidden="true" />
        <span class="font-medium">{{ menu.name }}</span>
      </RouterLink>
    </nav>

    <!-- 하단 -->
    <div class="border-t border-slate-200 p-4">
      <p class="text-xs text-slate-400">© 2026 Remind PT</p>
    </div>
  </aside>
</template>
