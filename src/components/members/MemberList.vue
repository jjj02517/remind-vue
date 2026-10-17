<script setup lang="ts">
import type { Member } from '@/types/member'
import { formatPhone } from '@/utils/phone'
// 부모 컴포넌트에서 회원 목록 전달받기
defineProps<{
  members: Member[]
}>()
</script>

<template>
  <!-- 회원 목록 -->
  <div class="mt-4">
    <!-- 검색 결과 없음 -->
    <div
      v-if="members.length === 0"
      class="rounded-xl border border-slate-200 bg-white px-6 py-12 text-center text-sm text-slate-400"
    >
      검색 결과가 없습니다.
    </div>

    <template v-else>
      <!-- 모바일 회원 카드 -->
      <div class="space-y-3 md:hidden">
        <div
          v-for="member in members"
          :key="member.id"
          class="rounded-xl border border-slate-200 bg-white p-5"
        >
          <!-- 회원명 -->
          <h3 class="text-lg font-semibold text-slate-900">
            <RouterLink
              :to="{ name: 'member-detail', params: { id: member.id } }"
              class="hover:text-blue-600 hover:underline"
            >
              {{ member.name }}
            </RouterLink>
          </h3>

          <!-- PT 횟수 및 연락처 -->
          <div class="mt-4 space-y-3">
            <!-- 총 PT -->
            <div class="flex items-center justify-between">
              <span class="text-sm text-slate-500">총 PT</span>
              <span class="text-sm font-medium text-slate-800"> {{ member.totalSessions }}회 </span>
            </div>

            <!-- 잔여 PT -->
            <div class="flex items-center justify-between">
              <span class="text-sm text-slate-500">잔여 PT</span>
              <span class="text-sm font-semibold text-blue-600">
                {{ member.remainingSessions }}회
              </span>
            </div>

            <!-- 연락처 -->
            <div>
              <p class="text-sm text-slate-500">
                {{ formatPhone(member.phone) }}
              </p>
            </div>
          </div>
        </div>
      </div>

      <!-- 태블릿 / PC 회원 테이블 -->
      <div class="hidden overflow-x-auto rounded-xl border border-slate-200 bg-white md:block">
        <table class="w-full min-w-[600px] text-left">
          <thead class="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th scope="col" class="px-6 py-4 font-medium">회원명</th>
              <th scope="col" class="px-6 py-4 font-medium">총 PT</th>
              <th scope="col" class="px-6 py-4 font-medium">잔여 PT</th>
              <th scope="col" class="px-6 py-4 font-medium">연락처</th>
            </tr>
          </thead>

          <tbody class="divide-y divide-slate-100">
            <tr v-for="member in members" :key="member.id" class="hover:bg-slate-50">
              <td class="px-6 py-4 font-medium text-slate-900">
                <RouterLink
                  :to="{ name: 'member-detail', params: { id: member.id } }"
                  class="hover:text-blue-600 hover:underline focus-visible:rounded-sm focus-visible:outline-2 focus-visible:outline-blue-600"
                >
                  {{ member.name }}
                </RouterLink>
              </td>
              <td class="px-6 py-4 text-slate-600">{{ member.totalSessions }}회</td>
              <td class="px-6 py-4 font-semibold text-blue-600">
                {{ member.remainingSessions }}회
              </td>
              <td class="px-6 py-4 text-slate-600">
                {{ formatPhone(member.phone) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
