<script setup lang="ts">
import MemberSearch from '@/components/members/MemberSearch.vue'
import MemberList from '@/components/members/MemberList.vue'
import MemberRegisterDialog from '@/components/members/MemberRegisterDialog.vue'
import { normalizePhone } from '@/utils/phone'
import { computed, onMounted, ref } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import { getMembers } from '@/api/members'
import { supabase } from '@/lib/supabase'

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

// 검색된 회원 목록
const filteredMembers = computed(() => {
  const keyword = searchKeyword.value.trim().toLowerCase()
  const phoneKeyword = normalizePhone(keyword)

  return (dbMembers.value ?? []).filter((member) => {
    const matchesName = member.name.toLowerCase().includes(keyword)

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
  const { data, error } = await supabase.auth.getSession()

  if (error) {
    console.error('사용자 정보 조회 오류:', error.message)
    authError.value = '사용자 정보를 확인하지 못했습니다.'
    return
  }

  trainerId.value = data.session?.user.id ?? null
})
</script>

<template>
  <div>
    <!-- 페이지 제목 -->
    <h1 class="text-3xl font-bold text-slate-900">회원 관리</h1>

    <!-- 페이지 설명 -->
    <p class="mt-2 text-slate-500">회원 정보와 PT 이용권을 관리합니다.</p>

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

    <!-- Supabase 회원 조회 상태 확인 (임시) -->
    <div class="mt-4 rounded-lg border border-slate-200 bg-white p-4 text-sm">
      <p v-if="fetchError" class="text-red-600">
        {{ fetchError }}
      </p>

      <p v-else-if="isLoading" class="text-slate-500">Supabase 회원 목록 불러오는 중...</p>

      <p v-else class="text-slate-600">Supabase 등록 회원: {{ dbMembers?.length ?? 0 }}명</p>
    </div>

    <!-- 회원 목록 -->
    <MemberList :members="filteredMembers" />

    <!-- 회원 등록 모달 -->
    <MemberRegisterDialog ref="registerDialog" />
  </div>
</template>
