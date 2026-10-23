<script setup lang="ts">
import { ref } from 'vue'
import { CalendarDays, ChevronRight, Dumbbell, Users } from 'lucide-vue-next'

import AddPtPackageDialog from '@/components/members/dialogs/AddPtPackageDialog.vue'
import AddGroupPackageDialog from '@/components/members/dialogs/AddGroupPackageDialog.vue'
import AddMembershipPackageDialog from '@/components/members/dialogs/AddMembershipPackageDialog.vue'

// 부모 컴포넌트에서 회원 ID 전달받기
defineProps<{
  memberId: string
}>()

// 공통 이용권 선택 모달
const packageDialog = ref<HTMLDialogElement | null>(null)

// PT 이용권 추가 모달 컴포넌트 참조
const ptPackageDialog = ref<InstanceType<typeof AddPtPackageDialog> | null>(null)

// 그룹 횟수제 이용권 추가 모달 컴포넌트 참조
const groupPackageDialog = ref<InstanceType<typeof AddGroupPackageDialog> | null>(null)

// 월 회원권 추가 모달 컴포넌트 참조
const membershipPackageDialog = ref<InstanceType<typeof AddMembershipPackageDialog> | null>(null)

// 추가 가능한 이용권 종류
type PackageType = 'pt' | 'group' | 'membership'

// 공통 이용권 선택 모달 열기
function openPackageDialog() {
  packageDialog.value?.showModal()
}

// 공통 이용권 선택 모달 닫기
function closePackageDialog() {
  packageDialog.value?.close()
}

// 선택한 이용권의 등록 모달 열기
function selectPackageType(type: PackageType) {
  // 이용권 선택 모달 닫기
  closePackageDialog()

  // PT 이용권 추가 모달 열기
  if (type === 'pt') {
    ptPackageDialog.value?.open()
    return
  }

  // 그룹 횟수제 이용권 추가 모달 열기
  if (type === 'group') {
    groupPackageDialog.value?.open()
    return
  }

  // 월 회원권 추가 모달 열기
  if (type === 'membership') {
    membershipPackageDialog.value?.open()
  }
}

// 부모 컴포넌트에서 공통 이용권 선택 모달 열기
defineExpose({
  open: openPackageDialog,
})
</script>

<template>
  <!-- 공통 이용권 종류 선택 모달 -->
  <dialog
    ref="packageDialog"
    aria-labelledby="add-package-dialog-title"
    aria-describedby="add-package-dialog-description"
    class="fixed inset-0 m-auto w-[calc(100%-2rem)] max-w-md rounded-2xl border border-slate-200 bg-white p-6 text-slate-900 shadow-xl backdrop:bg-black/40 sm:p-8"
  >
    <!-- 모달 제목 -->
    <h2 id="add-package-dialog-title" class="text-xl font-bold text-slate-900">이용권 추가</h2>

    <!-- 모달 설명 -->
    <p id="add-package-dialog-description" class="mt-2 text-sm text-slate-500">
      추가할 이용권의 종류를 선택해 주세요.
    </p>

    <!-- 이용권 종류 선택 -->
    <div class="mt-6 space-y-3">
      <!-- PT 횟수제 -->
      <button
        type="button"
        class="flex w-full items-center gap-3 rounded-xl border border-slate-200 p-4 text-left transition hover:border-blue-400 hover:bg-blue-50 focus-visible:outline-2 focus-visible:outline-blue-600"
        @click="selectPackageType('pt')"
      >
        <span class="rounded-lg bg-blue-50 p-3 text-blue-600">
          <Dumbbell :size="20" aria-hidden="true" />
        </span>

        <span class="min-w-0 flex-1">
          <span class="block text-sm font-semibold text-slate-900"> PT 횟수제 </span>
          <span class="mt-1 block text-xs text-slate-500"> 개인 PT 수업 횟수로 관리 </span>
        </span>

        <ChevronRight :size="18" class="shrink-0 text-slate-400" aria-hidden="true" />
      </button>

      <!-- 그룹 횟수제 -->
      <button
        type="button"
        class="flex w-full items-center gap-3 rounded-xl border border-slate-200 p-4 text-left transition hover:border-blue-400 hover:bg-blue-50 focus-visible:outline-2 focus-visible:outline-blue-600"
        @click="selectPackageType('group')"
      >
        <span class="rounded-lg bg-violet-50 p-3 text-violet-600">
          <Users :size="20" aria-hidden="true" />
        </span>

        <span class="min-w-0 flex-1">
          <span class="block text-sm font-semibold text-slate-900"> 그룹 횟수제 </span>
          <span class="mt-1 block text-xs text-slate-500"> 그룹 수업 횟수로 관리 </span>
        </span>

        <ChevronRight :size="18" class="shrink-0 text-slate-400" aria-hidden="true" />
      </button>

      <!-- 월 회원권 -->
      <button
        type="button"
        class="flex w-full items-center gap-3 rounded-xl border border-slate-200 p-4 text-left transition hover:border-blue-400 hover:bg-blue-50 focus-visible:outline-2 focus-visible:outline-blue-600"
        @click="selectPackageType('membership')"
      >
        <span class="rounded-lg bg-emerald-50 p-3 text-emerald-600">
          <CalendarDays :size="20" aria-hidden="true" />
        </span>

        <span class="min-w-0 flex-1">
          <span class="block text-sm font-semibold text-slate-900"> 월 회원권 </span>
          <span class="mt-1 block text-xs text-slate-500"> 시작일과 종료일로 관리 </span>
        </span>

        <ChevronRight :size="18" class="shrink-0 text-slate-400" aria-hidden="true" />
      </button>
    </div>

    <!-- 모달 닫기 -->
    <div class="mt-6 flex justify-end">
      <button
        type="button"
        class="rounded-lg border border-slate-200 px-5 py-2.5 text-sm font-medium text-slate-700 transition hover:bg-slate-50"
        @click="closePackageDialog"
      >
        취소
      </button>
    </div>
  </dialog>

  <!-- 기존 PT 이용권 추가 모달 -->
  <AddPtPackageDialog ref="ptPackageDialog" :member-id="memberId" />

  <!-- 기존 그룹 횟수제 이용권 추가 모달 -->
  <AddGroupPackageDialog ref="groupPackageDialog" :member-id="memberId" />

  <!-- 월 회원권 추가 모달 -->
  <AddMembershipPackageDialog ref="membershipPackageDialog" :member-id="memberId" />
</template>
