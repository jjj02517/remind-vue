<script setup lang="ts">
import { storeToRefs } from 'pinia'
import { useMemberStore } from '@/stores/members'
import MemberSearch from '@/components/members/MemberSearch.vue'
import MemberList from '@/components/members/MemberList.vue'
import MemberRegisterDialog from '@/components/members/MemberRegisterDialog.vue'
import type { Member } from '@/types/member'
import { normalizePhone } from '@/utils/phone'
import { computed, ref } from 'vue'

// 회원 데이터 Store
const memberStore = useMemberStore()

// Store의 반응형 회원 데이터 가져오기
const { members } = storeToRefs(memberStore)

// 회원 검색어
const searchKeyword = ref('')

// 검색된 회원 목록
const filteredMembers = computed(() => {
  const keyword = searchKeyword.value.trim().toLowerCase()
  const phoneKeyword = normalizePhone(keyword)

  return members.value.filter((member) => {
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

    <!-- 회원 목록 -->
    <MemberList :members="filteredMembers" />

    <!-- 회원 등록 모달 -->
    <MemberRegisterDialog ref="registerDialog" @register="memberStore.registerMember" />
  </div>
</template>
