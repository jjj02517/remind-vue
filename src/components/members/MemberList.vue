<script setup lang="ts">
import { formatPhone } from '@/utils/phone'

// 회원 목록에 필요한 데이터 타입
interface MemberListItem {
  id: string | number
  name: string
  phone: string
  status?: string
  totalSessions?: number | null
  remainingSessions?: number | null
}

// 부모 컴포넌트에서 회원 목록 전달받기
defineProps<{
  members: MemberListItem[]
}>()

// 회원 상태 표시 이름
function getMemberStatusLabel(status?: string) {
  const statusLabels: Record<string, string> = {
    active: '활동 중',
    inactive: '비활성',
    archived: '보관',
  }

  return statusLabels[status ?? 'active'] ?? '상태 확인 필요'
}

// 회원 상태 배지 스타일
function getMemberStatusClass(status?: string) {
  switch (status) {
    case 'active':
      return 'bg-green-50 text-green-700'
    case 'inactive':
      return 'bg-slate-200 text-slate-600'
    case 'archived':
      return 'bg-slate-300 text-slate-600'
    default:
      return 'bg-slate-100 text-slate-600'
  }
}

// 모바일 회원 카드 스타일
function getMemberCardClass(status?: string) {
  switch (status) {
    case 'inactive':
      return 'border-slate-200 bg-slate-50'
    case 'archived':
      return 'border-slate-200 bg-slate-100'
    default:
      return 'border-slate-200 bg-white'
  }
}

// PC 회원 테이블 행 스타일
function getMemberRowClass(status?: string) {
  switch (status) {
    case 'inactive':
      return 'bg-slate-50 hover:bg-slate-100'
    case 'archived':
      return 'bg-slate-100 hover:bg-slate-200'
    default:
      return 'bg-white hover:bg-slate-50'
  }
}

// 비활성 및 보관 회원 여부
function isInactiveMember(status?: string) {
  return status === 'inactive' || status === 'archived'
}
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
          class="rounded-xl border p-5 transition-colors"
          :class="getMemberCardClass(member.status)"
        >
          <!-- 회원명 및 상태 -->
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h3
              class="text-lg font-semibold"
              :class="isInactiveMember(member.status) ? 'text-slate-500' : 'text-slate-900'"
            >
              <RouterLink
                :to="{ name: 'member-detail', params: { id: member.id } }"
                class="hover:text-blue-600 hover:underline"
              >
                {{ member.name }}
              </RouterLink>
            </h3>

            <!-- 회원 상태 -->
            <span
              class="rounded-full px-3 py-1 text-xs font-medium"
              :class="getMemberStatusClass(member.status)"
            >
              {{ getMemberStatusLabel(member.status) }}
            </span>
          </div>

          <!-- PT 횟수 및 연락처 -->
          <div class="mt-4 space-y-3">
            <!-- 총 PT -->
            <div class="flex items-center justify-between">
              <span class="text-sm text-slate-500">총 PT</span>
              <span
                class="text-sm font-medium"
                :class="isInactiveMember(member.status) ? 'text-slate-500' : 'text-slate-800'"
              >
                {{ member.totalSessions == null ? '—' : `${member.totalSessions}회` }}
              </span>
            </div>

            <!-- 잔여 PT -->
            <div class="flex items-center justify-between">
              <span class="text-sm text-slate-500">잔여 PT</span>
              <span
                class="text-sm font-semibold"
                :class="isInactiveMember(member.status) ? 'text-slate-500' : 'text-blue-600'"
              >
                {{ member.remainingSessions == null ? '—' : `${member.remainingSessions}회` }}
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
            <tr
              v-for="member in members"
              :key="member.id"
              class="transition-colors"
              :class="getMemberRowClass(member.status)"
            >
              <!-- 회원명 및 상태 -->
              <td class="px-6 py-4 font-medium">
                <div class="flex flex-wrap items-center gap-2">
                  <RouterLink
                    :to="{ name: 'member-detail', params: { id: member.id } }"
                    class="hover:text-blue-600 hover:underline focus-visible:rounded-sm focus-visible:outline-2 focus-visible:outline-blue-600"
                    :class="isInactiveMember(member.status) ? 'text-slate-500' : 'text-slate-900'"
                  >
                    {{ member.name }}
                  </RouterLink>

                  <!-- 회원 상태 -->
                  <span
                    class="rounded-full px-2.5 py-1 text-xs font-medium"
                    :class="getMemberStatusClass(member.status)"
                  >
                    {{ getMemberStatusLabel(member.status) }}
                  </span>
                </div>
              </td>

              <!-- 총 PT -->
              <td class="px-6 py-4 text-slate-600">
                {{ member.totalSessions == null ? '—' : `${member.totalSessions}회` }}
              </td>

              <!-- 잔여 PT -->
              <td
                class="px-6 py-4 font-semibold"
                :class="isInactiveMember(member.status) ? 'text-slate-500' : 'text-blue-600'"
              >
                {{ member.remainingSessions == null ? '—' : `${member.remainingSessions}회` }}
              </td>

              <!-- 연락처 -->
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
