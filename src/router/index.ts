import { createRouter, createWebHistory } from 'vue-router'
import MainLayout from '@/layouts/MainLayout.vue'
import { supabase } from '@/lib/supabase'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    // 로그인 페이지 (공통 레이아웃 사용 안 함)
    {
      path: '/login',
      name: 'login',
      component: () => import('@/views/LoginView.vue'),
      meta: { title: '로그인' },
    },

    // 비밀번호 재설정 페이지
    {
      path: '/reset-password',
      name: 'reset-password',
      component: () => import('@/views/ResetPasswordView.vue'),
      meta: { title: '비밀번호 재설정' },
    },

    // 비밀번호 찾기 페이지
    {
      path: '/forgot-password',
      name: 'forgot-password',
      component: () => import('@/views/ForgotPasswordView.vue'),
      meta: { title: '비밀번호 찾기' },
    },

    // 기존 MainLayout 라우트
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

        // 근무처 관리 페이지
        {
          path: 'companies',
          name: 'companies',
          component: () => import('@/views/CompaniesView.vue'),
          meta: { title: '근무처 관리' },
        },
        {
          path: 'sessions',
          name: 'sessions',
          component: () => import('@/views/SessionsView.vue'),
          meta: { title: '수업 관리' },
        },

        // 정산 관리 페이지
        {
          path: 'settlements',
          name: 'settlements',
          component: () => import('@/views/SettlementsView.vue'),
          meta: { title: '정산 관리' },
        },
      ],
    },
  ],
})

// 로그인 없이 접근할 수 있는 페이지
const publicPages = ['/login', '/forgot-password', '/reset-password']

// 페이지 이동 전 로그인 상태 확인
router.beforeEach(async (to) => {
  // 공개 페이지는 로그인 여부와 관계없이 접근 허용
  if (publicPages.includes(to.path)) {
    return true
  }

  // Supabase에서 현재 로그인한 사용자 확인
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()

  // 로그인하지 않은 경우 로그인 페이지로 이동
  if (error || !user) {
    return {
      path: '/login',
      query: { redirect: to.fullPath },
    }
  }

  // 로그인한 경우 페이지 이동 허용
  return true
})

export default router
