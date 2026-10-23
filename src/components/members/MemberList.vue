<script setup lang="ts">
import { formatPhone } from '@/utils/phone'

import type { MemberListData, MemberListPackage } from '@/api/members'
import type { MemberStatus } from '@/utils/memberStatus'

// 부모 컴포넌트에서 회원 목록 전달받기
defineProps<{
  members: MemberListData[]
}>()

// 회원 상태 표시 이름
function getMemberStatusLabel(status: MemberStatus) {
  const statusLabels: Record<MemberStatus, string> = {
    active: '활동 중',
    inactive: '비활성',
    archived: '보관',
  }

  return statusLabels[status]
}

// 회원 상태 배지 스타일
function getMemberStatusClass(status: MemberStatus) {
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
function getMemberCardClass(status: MemberStatus) {
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
function getMemberRowClass(status: MemberStatus) {
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
function isInactiveMember(status: MemberStatus) {
  return status === 'inactive' || status === 'archived'
}

// 날짜 표시 형식
function formatDate(date: string | null) {
  if (!date) return '미설정'

  return date.slice(0, 10).replaceAll('-', '.')
}

// 이용권 종류에 따른 표시 이름
function getPackageLabel(pkg: MemberListPackage): string {
  // PT 횟수제 이용권
  if (pkg.packageType === 'pt' && pkg.usageType === 'count') {
    return `PT ${pkg.remainingSessions ?? 0}/${pkg.totalSessions ?? 0}회`
  }

  // 그룹 횟수제 이용권
  if (pkg.packageType === 'group' && pkg.usageType === 'count') {
    return `그룹 ${pkg.remainingSessions ?? 0}/${pkg.totalSessions ?? 0}회`
  }

  // 월 회원권
  if (pkg.packageType === 'membership' && pkg.usageType === 'period') {
    return `월 회원권 · ${formatDate(pkg.endsOn)} 만료`
  }

  // 그룹 기간제 이용권
  if (pkg.packageType === 'group' && pkg.usageType === 'period') {
    return `그룹 기간권 · ${formatDate(pkg.endsOn)} 만료`
  }

  return '기타 이용권'
}

// 이용권 종류별 배지 스타일
function getPackageClass(pkg: MemberListPackage) {
  switch (pkg.packageType) {
    case 'pt':
      return 'bg-blue-50 text-blue-700'
    case 'group':
      return 'bg-violet-50 text-violet-700'
    case 'membership':
      return 'bg-emerald-50 text-emerald-700'
    default:
      return 'bg-slate-100 text-slate-600'
  }
}

// 일시정지 및 이용 예정 상태 표시
function getPackageStateLabel(pkg: MemberListPackage): string {
  if (pkg.isPaused) return '일시정지 중'
  if (pkg.isScheduled) return '이용 예정'

  return ''
}

// 일시정지 및 이용 예정 배지 스타일
function getPackageStateClass(pkg: MemberListPackage) {
  if (pkg.isPaused) {
    return 'bg-amber-100 text-amber-700'
  }

  if (pkg.isScheduled) {
    return 'bg-sky-100 text-sky-700'
  }

  return ''
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

          <!-- 연락처 -->
          <p class="mt-2 text-sm text-slate-500">
            {{ formatPhone(member.phone) }}
          </p>

          <!-- 보유 이용권 -->
          <div class="mt-4 border-t border-slate-200 pt-4">
            <p class="mb-3 text-xs font-medium text-slate-500">보유 이용권</p>

            <!-- 현재 및 예정 이용권이 있는 경우 -->
            <div v-if="member.packages.length > 0" class="flex flex-wrap gap-2">
              <div
                v-for="pkg in member.packages"
                :key="pkg.id"
                class="flex flex-wrap items-center gap-1.5"
              >
                <!-- 이용권 종류 및 잔여 정보 -->
                <span
                  class="inline-flex rounded-lg px-3 py-1.5 text-xs font-medium"
                  :class="getPackageClass(pkg)"
                >
                  {{ getPackageLabel(pkg) }}
                </span>

                <!-- 일시정지 또는 이용 예정 상태 -->
                <span
                  v-if="getPackageStateLabel(pkg)"
                  class="inline-flex rounded-full px-2 py-1 text-xs font-medium"
                  :class="getPackageStateClass(pkg)"
                >
                  {{ getPackageStateLabel(pkg) }}
                </span>
              </div>
            </div>

            <!-- 현재 또는 예정 이용권이 없는 경우 -->
            <p v-else class="text-sm text-slate-400">현재 보유한 유효 이용권이 없습니다.</p>
          </div>
        </div>
      </div>

      <!-- 태블릿 / PC 회원 테이블 -->
      <div class="hidden overflow-x-auto rounded-xl border border-slate-200 bg-white md:block">
        <table class="w-full min-w-[700px] text-left">
          <thead class="bg-slate-50 text-sm text-slate-500">
            <tr>
              <th scope="col" class="w-[28%] px-6 py-4 font-medium">회원명</th>
              <th scope="col" class="px-6 py-4 font-medium">보유 이용권</th>
              <th scope="col" class="w-[23%] px-6 py-4 font-medium">연락처</th>
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
              <td class="px-6 py-4 align-top font-medium">
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

              <!-- 보유 이용권 -->
              <td class="px-6 py-4 align-top">
                <!-- 현재 및 예정 이용권이 있는 경우 -->
                <div v-if="member.packages.length > 0" class="flex flex-wrap gap-2">
                  <div
                    v-for="pkg in member.packages"
                    :key="pkg.id"
                    class="flex flex-wrap items-center gap-1.5"
                  >
                    <!-- 이용권 종류 및 잔여 정보 -->
                    <span
                      class="inline-flex rounded-lg px-3 py-1.5 text-xs font-medium"
                      :class="getPackageClass(pkg)"
                    >
                      {{ getPackageLabel(pkg) }}
                    </span>

                    <!-- 일시정지 또는 이용 예정 상태 -->
                    <span
                      v-if="getPackageStateLabel(pkg)"
                      class="inline-flex rounded-full px-2 py-1 text-xs font-medium"
                      :class="getPackageStateClass(pkg)"
                    >
                      {{ getPackageStateLabel(pkg) }}
                    </span>
                  </div>
                </div>

                <!-- 현재 또는 예정 이용권이 없는 경우 -->
                <span v-else class="text-sm text-slate-400">
                  현재 보유한 유효 이용권이 없습니다.
                </span>
              </td>

              <!-- 연락처 -->
              <td class="px-6 py-4 align-top text-sm text-slate-600">
                {{ formatPhone(member.phone) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
