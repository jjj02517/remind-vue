import { createRouter, createWebHistory } from 'vue-router'
import MainLayout from '@/layouts/MainLayout.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      component: MainLayout,
      children: [
        {
          path: '',
          name: 'dashboard',
          component: () => import('@/views/DashboardView.vue'),
          meta: { title: '대시보드' },
        },
        {
          path: 'members',
          name: 'members',
          component: () => import('@/views/MembersView.vue'),
          meta: { title: '회원 관리' },
        },
        // 회원 상세 페이지
        {
          path: 'members/:id',
          name: 'member-detail',
          component: () => import('@/views/MemberDetailView.vue'),
          meta: { title: '회원 상세' },
        },
        {
          path: 'sessions',
          name: 'sessions',
          component: () => import('@/views/SessionsView.vue'),
          meta: { title: '수업 관리' },
        },
      ],
    },
  ],
})

export default router
