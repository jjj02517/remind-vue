<script setup lang="ts">
import {
  Dumbbell,
  LayoutDashboard,
  Users,
  Building2,
  CalendarDays,
  LogOut,
  Banknote,
} from 'lucide-vue-next'

import DeleteAccountDialog from '@/components/settings/DeleteAccountDialog.vue'

// PC 사이드바 접힘 상태
const props = withDefaults(
  defineProps<{
    collapsed?: boolean
  }>(),
  {
    collapsed: false,
  },
)

// 메뉴 선택 및 로그아웃 이벤트
const emit = defineEmits<{
  (e: 'navigate'): void
  (e: 'logout'): void
}>()

const menus = [
  { name: '대시보드', icon: LayoutDashboard, path: '/' },
  { name: '회원 관리', icon: Users, path: '/members' },
  { name: '근무처 관리', icon: Building2, path: '/companies' },
  { name: '수업 관리', icon: CalendarDays, path: '/sessions' },
  { name: '정산 관리', icon: Banknote, path: '/settlements' },
]
</script>

<template>
  <aside
    class="flex h-full flex-col border-r border-slate-200 bg-white"
    :class="props.collapsed ? 'w-20' : 'w-64'"
  >
    <!-- 로고 -->
    <div
      class="flex h-20 shrink-0 items-center border-b border-slate-200"
      :class="props.collapsed ? 'justify-center px-2' : 'gap-2 px-6'"
    >
      <Dumbbell :size="24" class="shrink-0 text-blue-600" aria-hidden="true" />

      <h1 v-if="!props.collapsed" class="whitespace-nowrap text-xl font-bold text-blue-600">
        Remind PT
      </h1>
    </div>

    <!-- 메뉴 -->
    <nav aria-label="주 메뉴" class="flex-1 space-y-2" :class="props.collapsed ? 'p-2' : 'p-4'">
      <RouterLink
        v-for="menu in menus"
        :key="menu.path"
        :to="menu.path"
        class="flex items-center rounded-lg py-3 text-slate-600 transition hover:bg-blue-50 hover:text-blue-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
        :class="props.collapsed ? 'justify-center px-2' : 'gap-3 px-4'"
        :aria-label="props.collapsed ? menu.name : undefined"
        :title="props.collapsed ? menu.name : undefined"
        exact-active-class="bg-blue-50 text-blue-600"
        @click="emit('navigate')"
      >
        <component :is="menu.icon" :size="20" class="shrink-0" aria-hidden="true" />

        <span v-if="!props.collapsed" class="whitespace-nowrap font-medium">
          {{ menu.name }}
        </span>
      </RouterLink>
    </nav>

    <!-- 하단 -->
    <div class="border-t border-slate-200" :class="props.collapsed ? 'p-2' : 'p-4'">
      <!-- 로그아웃 버튼 -->
      <button
        type="button"
        class="flex w-full items-center rounded-lg py-3 text-slate-600 transition hover:bg-red-50 hover:text-red-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
        :class="props.collapsed ? 'justify-center px-2' : 'gap-3 px-4'"
        :aria-label="props.collapsed ? '로그아웃' : undefined"
        :title="props.collapsed ? '로그아웃' : undefined"
        @click="emit('logout')"
      >
        <LogOut :size="20" class="shrink-0" aria-hidden="true" />

        <span v-if="!props.collapsed" class="whitespace-nowrap font-medium"> 로그아웃 </span>
      </button>

      <!-- 회원 탈퇴 -->
      <div v-if="!props.collapsed" class="mt-1 pl-4">
        <DeleteAccountDialog />
      </div>

      <!-- 저작권 -->
      <p v-if="!props.collapsed" class="mt-4 px-4 text-xs text-slate-400">© 2026 Remind PT</p>
    </div>
  </aside>
</template>
