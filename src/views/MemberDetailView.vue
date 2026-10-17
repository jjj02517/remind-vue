<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowLeft } from 'lucide-vue-next'

import { useMemberStore } from '@/stores/members'
import { formatPhone } from '@/utils/phone'

// 현재 페이지의 라우트 정보
const route = useRoute()

// 회원 데이터 Store
const memberStore = useMemberStore()

// 회원 ID로 회원 정보 조회
const member = computed(() => {
  return memberStore.getMemberById(Number(route.params.id))
})

// 사용한 PT 횟수
const usedSessions = computed(() => {
  if (!member.value) return 0

  return Math.max(0, member.value.totalSessions - member.value.remainingSessions)
})

// PT 사용 진행률 (%)
const usagePercent = computed(() => {
  if (!member.value || member.value.totalSessions <= 0) return 0

  const percent = (usedSessions.value / member.value.totalSessions) * 100

  return Math.min(100, Math.round(percent))
})
</script>

<template>
  <div>
    <!-- 회원 목록으로 돌아가기 -->
    <RouterLink
      to="/members"
      class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 hover:text-blue-600"
    >
      <ArrowLeft :size="18" aria-hidden="true" />
      회원 목록으로
    </RouterLink>

    <!-- 회원 정보가 있는 경우 -->
    <template v-if="member">
      <!-- 페이지 제목 -->
      <h1 class="mt-6 text-2xl font-bold text-slate-900 sm:text-3xl">
        {{ member.name }}
      </h1>

      <!-- 페이지 설명 -->
      <p class="mt-2 text-slate-500">회원 정보와 PT 이용 현황을 확인합니다.</p>

      <!-- 회원 정보 -->
      <div class="mt-8 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
        <h2 class="text-lg font-semibold text-slate-900">기본 정보</h2>

        <div class="mt-5 space-y-4">
          <!-- 회원명 -->
          <div class="flex items-center justify-between gap-4">
            <span class="text-sm text-slate-500">회원명</span>
            <span class="text-sm font-medium text-slate-900">
              {{ member.name }}
            </span>
          </div>

          <!-- 연락처 -->
          <div class="flex items-center justify-between gap-4">
            <span class="text-sm text-slate-500">연락처</span>
            <span class="text-sm font-medium text-slate-900">
              {{ formatPhone(member.phone) }}
            </span>
          </div>
        </div>
      </div>

      <!-- PT 이용 현황 -->
      <div class="mt-6 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
        <h2 class="text-lg font-semibold text-slate-900">PT 이용 현황</h2>

        <div class="mt-5 grid grid-cols-2 gap-4">
          <!-- 총 PT -->
          <div class="rounded-lg bg-slate-50 p-4">
            <p class="text-sm text-slate-500">총 PT</p>
            <p class="mt-2 text-2xl font-bold text-slate-900">{{ member.totalSessions }}회</p>
          </div>

          <!-- 잔여 PT -->
          <div class="rounded-lg bg-blue-50 p-4">
            <p class="text-sm text-blue-600">잔여 PT</p>
            <p class="mt-2 text-2xl font-bold text-blue-600">{{ member.remainingSessions }}회</p>
          </div>
        </div>
      </div>

      <!-- PT 사용 진행률 -->
      <div class="mt-6">
        <div class="mb-3 flex items-center justify-between">
          <h3 class="text-sm font-medium text-slate-700">PT 사용 진행률</h3>
          <span class="text-sm font-semibold text-blue-600"> {{ usagePercent }}% </span>
        </div>

        <!-- 진행률 바 -->
        <div
          role="progressbar"
          aria-label="PT 사용 진행률"
          :aria-valuenow="usagePercent"
          aria-valuemin="0"
          aria-valuemax="100"
          class="h-3 overflow-hidden rounded-full bg-slate-200"
        >
          <div
            class="h-full rounded-full bg-blue-600 transition-all duration-300"
            :style="{ width: `${usagePercent}%` }"
          ></div>
        </div>

        <!-- 사용 및 잔여 PT 안내 -->
        <div class="mt-3 flex items-center justify-between gap-3 text-xs sm:text-sm">
          <div class="flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-blue-600"></span>
            <span class="text-slate-600">사용 {{ usedSessions }}회</span>
          </div>

          <div class="flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full bg-slate-200"></span>
            <span class="text-slate-600">잔여 {{ member.remainingSessions }}회</span>
          </div>
        </div>
      </div>
    </template>

    <!-- 회원 정보가 없는 경우 -->
    <div v-else class="mt-8 rounded-xl border border-slate-200 bg-white px-6 py-12 text-center">
      <h1 class="text-xl font-semibold text-slate-900">회원을 찾을 수 없습니다.</h1>
      <p class="mt-2 text-sm text-slate-500">회원 정보가 없거나 잘못된 주소입니다.</p>
    </div>
  </div>
</template>
