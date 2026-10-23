<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useQuery } from '@tanstack/vue-query'

import MemberSearch from '@/components/members/MemberSearch.vue'
import MemberList from '@/components/members/MemberList.vue'
import MemberRegisterDialog from '@/components/members/dialogs/MemberRegisterDialog.vue'

import { normalizePhone } from '@/utils/phone'
import { getMembers } from '@/api/members'
import { supabase } from '@/lib/supabase'

// 회원 상태 필터 타입
type MemberStatusFilter = 'all' | 'active' | 'inactive'

// 로그인한 트레이너 ID
const trainerId = ref<string | null>(null)

// 사용자 정보 조회 오류
const authError = ref('')

// TanStack Query로 Supabase 회원 목록 조회
const {
  data: dbMembers,
  isPending: isLoading,
  error: queryError,
} = useQuery({
  // 트레이너별로 회원 목록 캐시 구분
  queryKey: computed(() => ['members', trainerId.value]),

  // Supabase 회원 목록 조회
  queryFn: getMembers,

  // 로그인한 트레이너 ID가 있을 때만 조회
  enabled: computed(() => !!trainerId.value),

  // 5분 동안 데이터를 최신 상태로 간주
  staleTime: 1000 * 60 * 5,

  // 디버깅을 위해 오류 발생 시 자동 재시도 끄기
  retry: false,

  // 디버깅을 위해 브라우저 포커스 시 자동 재조회 끄기
  refetchOnWindowFocus: false,
})

// 회원 목록 조회 오류 메시지
const fetchError = computed(() => {
  if (authError.value) return authError.value
  if (queryError.value) return '회원 목록을 불러오지 못했습니다.'

  return ''
})

// 회원 검색어
const searchKeyword = ref('')

// 회원 상태 필터
const statusFilter = ref<MemberStatusFilter>('all')

// 회원 상태 필터 옵션
const statusFilterOptions: {
  value: MemberStatusFilter
  label: string
}[] = [
  { value: 'all', label: '전체' },
  { value: 'active', label: '활동 중' },
  { value: 'inactive', label: '비활성' },
]

// 회원 상태 필터 변경
function changeStatusFilter(status: MemberStatusFilter) {
  statusFilter.value = status
}

// 검색어 및 상태에 따라 필터링된 회원 목록
const filteredMembers = computed(() => {
  const keyword = searchKeyword.value.trim().toLowerCase()
  const phoneKeyword = normalizePhone(keyword)

  return (dbMembers.value ?? []).filter((member) => {
    // 보관 회원은 기본 목록에서 제외
    if (member.status === 'archived') {
      return false
    }

    // 선택한 회원 상태와 일치하는지 확인
    const matchesStatus = statusFilter.value === 'all' || member.status === statusFilter.value

    if (!matchesStatus) return false

    // 검색어가 없는 경우 상태 필터만 적용
    if (!keyword) return true

    // 회원명 검색
    const matchesName = member.name.toLowerCase().includes(keyword)

    // 연락처 검색
    const matchesPhone = phoneKeyword !== '' && normalizePhone(member.phone).includes(phoneKeyword)

    return matchesName || matchesPhone
  })
})

// 회원 등록 모달 컴포넌트 참조
const registerDialog = ref<InstanceType<typeof MemberRegisterDialog> | null>(null)

// 회원 등록 모달 열기
function openRegisterDialog() {
  registerDialog.value?.open()
}

// 회원 관리 페이지 진입 시 로그인한 사용자 확인
onMounted(async () => {
  try {
    const { data, error } = await supabase.auth.getSession()

    if (error) {
      throw error
    }

    trainerId.value = data.session?.user.id ?? null

    // 로그인 정보가 없는 경우
    if (!trainerId.value) {
      authError.value = '로그인 정보를 확인하지 못했습니다.'
    }
  } catch (error) {
    console.error('사용자 정보 조회 오류:', error)

    authError.value = '사용자 정보를 확인하지 못했습니다.'
  }
})
</script>

<template>
  <div>
    <!-- 페이지 제목 -->
    <h1 class="text-3xl font-bold text-slate-900">회원 관리</h1>

    <!-- 페이지 설명 -->
    <p class="mt-2 text-slate-500">회원 정보와 이용권을 관리합니다.</p>

    <!-- 회원 등록 -->
    <div class="mt-6 flex justify-end">
      <button
        type="button"
        class="w-full rounded-lg bg-blue-600 px-5 py-3 text-sm font-semibold text-white transition hover:bg-blue-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600 sm:w-auto"
        @click="openRegisterDialog"
      >
        회원 등록
      </button>
    </div>

    <!-- 회원 검색 -->
    <MemberSearch v-model="searchKeyword" />

    <!-- 회원 상태 필터 -->
    <div class="mt-4">
      <div
        role="group"
        aria-label="회원 상태 필터"
        class="inline-flex w-full rounded-xl bg-slate-100 p-1 sm:w-auto"
      >
        <button
          v-for="option in statusFilterOptions"
          :key="option.value"
          type="button"
          :aria-pressed="statusFilter === option.value"
          class="flex-1 rounded-lg px-4 py-2.5 text-sm font-medium transition-colors sm:min-w-24 sm:flex-none"
          :class="
            statusFilter === option.value
              ? 'bg-white text-blue-600 shadow-sm'
              : 'text-slate-500 hover:text-slate-800'
          "
          @click="changeStatusFilter(option.value)"
        >
          {{ option.label }}
        </button>
      </div>
    </div>

    <!-- Supabase 회원 조회 상태 확인 (임시) -->
    <div class="mt-4 rounded-lg border border-slate-200 bg-white p-4 text-sm">
      <!-- 회원 목록 조회 오류 -->
      <p v-if="fetchError" role="alert" class="text-red-600">
        {{ fetchError }}
      </p>

      <!-- 회원 목록 조회 중 -->
      <p v-else-if="isLoading" class="text-slate-500">Supabase 회원 목록 불러오는 중...</p>

      <!-- 검색 및 필터 적용 결과 -->
      <p v-else class="text-slate-600">
        표시 중인 회원: {{ filteredMembers.length }}명
        <span class="text-slate-400">
          / 전체 {{ (dbMembers ?? []).filter((member) => member.status !== 'archived').length }}명
        </span>
      </p>
    </div>

    <!-- 회원 목록 -->
    <MemberList v-if="!isLoading && !fetchError" :members="filteredMembers" />

    <!-- 회원 등록 모달 -->
    <MemberRegisterDialog ref="registerDialog" />
  </div>
</template>
