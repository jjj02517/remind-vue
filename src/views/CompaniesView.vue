<script setup lang="ts">
import { computed, ref } from 'vue'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'

import {
  archiveCompany,
  createCompany,
  getCompanies,
  restoreCompany,
  updateCompany,
} from '@/api/companies'
import type { Company } from '@/api/companies'

// TanStack Query 캐시 관리
const queryClient = useQueryClient()

// 근무처 등록 폼 표시 여부
const isFormOpen = ref(false)

// 새 근무처 이름
const companyName = ref('')

// 근무처 등록 오류
const createError = ref('')

// 근무처 등록 및 변경 성공 메시지
const successMessage = ref('')

// 근무처 수정 중인 ID
const editingCompanyId = ref<string | null>(null)

// 수정할 근무처 이름
const editingCompanyName = ref('')

// 현재 변경 처리 중인 근무처 ID
const pendingCompanyId = ref<string | null>(null)

// 근무처 수정 및 보관 처리 오류
const actionError = ref<{
  companyId: string
  message: string
} | null>(null)

// 보관된 근무처 목록 표시 여부
const showArchived = ref(false)

// 내 근무처 목록 조회
const {
  data: companies,
  isPending: isLoading,
  error: queryError,
  refetch,
} = useQuery({
  queryKey: ['companies'],
  queryFn: getCompanies,
  staleTime: 1000 * 60 * 5,
})

// 활성 근무처 목록
const activeCompanies = computed(() =>
  (companies.value ?? []).filter((company) => company.is_active),
)

// 기본 개인 고객 근무처
const personalCompany = computed(() =>
  activeCompanies.value.find((company) => company.company_type === 'personal'),
)

// 일반 근무처 목록
const workplaces = computed(() =>
  activeCompanies.value.filter((company) => company.company_type === 'workplace'),
)

// 보관된 일반 근무처 목록
const archivedWorkplaces = computed(() =>
  (companies.value ?? []).filter(
    (company) => company.company_type === 'workplace' && !company.is_active,
  ),
)

// 근무처 등록 Mutation
const { mutateAsync: registerCompany, isPending: isCreating } = useMutation({
  mutationFn: createCompany,

  // 등록 성공 시 근무처 목록 갱신
  onSuccess: async () => {
    await queryClient.invalidateQueries({
      queryKey: ['companies'],
    })
  },
})

// 근무처 변경 작업 종류
type CompanyAction =
  | { type: 'rename'; companyId: string; name: string }
  | { type: 'archive'; companyId: string }
  | { type: 'restore'; companyId: string }

// 근무처 이름 수정, 보관 및 복구 Mutation
const { mutateAsync: changeCompany, isPending: isUpdating } = useMutation({
  mutationFn: async (action: CompanyAction) => {
    // 일반 근무처 이름 수정
    if (action.type === 'rename') {
      return updateCompany(action.companyId, action.name)
    }

    // 일반 근무처 보관
    if (action.type === 'archive') {
      return archiveCompany(action.companyId)
    }

    // 보관된 근무처 복구
    return restoreCompany(action.companyId)
  },

  // 변경 성공 시 근무처 목록 갱신
  onSuccess: async () => {
    await queryClient.invalidateQueries({
      queryKey: ['companies'],
    })
  },
})

// 근무처 등록 버튼 비활성화 조건
const isSubmitDisabled = computed(() => isCreating.value || !companyName.value.trim())

// 근무처 이름 저장 버튼 비활성화 조건
const isEditSubmitDisabled = computed(() => isUpdating.value || !editingCompanyName.value.trim())

// 근무처 등록 폼 열기
function openCreateForm() {
  companyName.value = ''
  createError.value = ''
  successMessage.value = ''
  isFormOpen.value = true
}

// 근무처 등록 폼 닫기
function closeCreateForm() {
  if (isCreating.value) return

  isFormOpen.value = false
  companyName.value = ''
  createError.value = ''
}

// 새 근무처 등록
async function submitCompany() {
  if (isSubmitDisabled.value) return

  createError.value = ''
  successMessage.value = ''

  try {
    const company = await registerCompany(companyName.value)

    // 등록 완료 후 폼 초기화
    isFormOpen.value = false
    companyName.value = ''

    successMessage.value = `${company.name} 근무처를 등록했습니다.`
  } catch (error) {
    console.error('근무처 등록 오류:', error)

    createError.value = error instanceof Error ? error.message : '근무처 등록에 실패했습니다.'
  }
}

// 근무처 이름 수정 시작
function startEditing(company: Company) {
  // 기본 개인 고객은 수정할 수 없음
  if (company.company_type !== 'workplace') return
  if (isUpdating.value) return

  editingCompanyId.value = company.id
  editingCompanyName.value = company.name
  actionError.value = null
  successMessage.value = ''
}

// 근무처 이름 수정 취소
function cancelEditing() {
  if (isUpdating.value) return

  editingCompanyId.value = null
  editingCompanyName.value = ''
  actionError.value = null
}

// 근무처 이름 수정 저장
async function submitEdit(company: Company) {
  if (isEditSubmitDisabled.value) return
  if (editingCompanyId.value !== company.id) return
  if (company.company_type !== 'workplace') return

  actionError.value = null
  successMessage.value = ''
  pendingCompanyId.value = company.id

  try {
    const updated = await changeCompany({
      type: 'rename',
      companyId: company.id,
      name: editingCompanyName.value,
    })

    // 수정 완료 후 입력 폼 닫기
    editingCompanyId.value = null
    editingCompanyName.value = ''

    successMessage.value = `${updated.name} 근무처 이름을 수정했습니다.`
  } catch (error) {
    console.error('근무처 이름 수정 오류:', error)

    actionError.value = {
      companyId: company.id,
      message: error instanceof Error ? error.message : '근무처 이름 수정에 실패했습니다.',
    }
  } finally {
    pendingCompanyId.value = null
  }
}

// 근무처 보관 또는 보관 해제
async function changeCompanyStatus(company: Company, action: 'archive' | 'restore') {
  // 기본 개인 고객은 보관할 수 없음
  if (company.company_type !== 'workplace') return
  if (isUpdating.value) return

  // 처리 전 확인
  const confirmMessage =
    action === 'archive'
      ? `${company.name} 근무처를 보관하시겠습니까?\n\n기존 회원 연결 및 이력은 유지됩니다.`
      : `${company.name} 근무처를 다시 활성화하시겠습니까?`

  if (!window.confirm(confirmMessage)) return

  actionError.value = null
  successMessage.value = ''
  pendingCompanyId.value = company.id

  try {
    await changeCompany({
      type: action,
      companyId: company.id,
    })

    // 보관 또는 복구 완료 메시지
    successMessage.value =
      action === 'archive'
        ? `${company.name} 근무처를 보관했습니다.`
        : `${company.name} 근무처를 다시 활성화했습니다.`
  } catch (error) {
    console.error('근무처 상태 변경 오류:', error)

    actionError.value = {
      companyId: company.id,
      message: error instanceof Error ? error.message : '근무처 상태 변경에 실패했습니다.',
    }
  } finally {
    pendingCompanyId.value = null
  }
}

// 해당 근무처의 변경 작업 진행 여부
function isPendingCompany(companyId: string) {
  return isUpdating.value && pendingCompanyId.value === companyId
}
</script>

<template>
  <!-- 근무처 관리 페이지 -->
  <div class="space-y-6">
    <!-- 페이지 제목 및 근무처 추가 버튼 -->
    <div class="flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">근무처 관리</h1>

        <p class="mt-2 text-sm text-slate-500">여러 근무처의 회원과 수업을 한곳에서 관리하세요.</p>
      </div>

      <button
        type="button"
        :disabled="isFormOpen"
        class="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        @click="openCreateForm"
      >
        + 근무처 추가
      </button>
    </div>

    <!-- 근무처 등록 및 변경 성공 메시지 -->
    <p
      v-if="successMessage"
      role="status"
      class="rounded-lg bg-green-50 px-4 py-3 text-sm text-green-700"
    >
      {{ successMessage }}
    </p>

    <!-- 근무처 추가 폼 -->
    <form
      v-if="isFormOpen"
      class="rounded-xl border border-blue-100 bg-blue-50/40 p-5"
      @submit.prevent="submitCompany"
    >
      <h2 class="text-base font-semibold text-slate-900">새 근무처 등록</h2>

      <p class="mt-1 text-sm text-slate-500">
        현재 근무하거나 회원을 관리하는 장소를 등록해 주세요.
      </p>

      <!-- 근무처 이름 입력 -->
      <div class="mt-5">
        <label for="company-name" class="mb-2 block text-sm font-medium text-slate-700">
          근무처 이름
        </label>

        <input
          id="company-name"
          v-model="companyName"
          type="text"
          required
          maxlength="100"
          placeholder="예: A피트니스, B스튜디오"
          :disabled="isCreating"
          class="w-full rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
        />
      </div>

      <!-- 근무처 등록 오류 -->
      <p v-if="createError" role="alert" class="mt-3 text-sm text-red-600">
        {{ createError }}
      </p>

      <!-- 등록 폼 버튼 -->
      <div class="mt-5 flex justify-end gap-3">
        <button
          type="button"
          :disabled="isCreating"
          class="rounded-lg border border-slate-200 bg-white px-4 py-2.5 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50"
          @click="closeCreateForm"
        >
          취소
        </button>

        <button
          type="submit"
          :disabled="isSubmitDisabled"
          class="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300"
        >
          {{ isCreating ? '등록 중...' : '근무처 등록' }}
        </button>
      </div>
    </form>

    <!-- 근무처 목록 조회 중 -->
    <p
      v-if="isLoading"
      class="rounded-xl border border-slate-200 bg-white p-6 text-sm text-slate-500"
    >
      근무처 목록을 불러오는 중...
    </p>

    <!-- 근무처 목록 조회 오류 -->
    <div v-else-if="queryError" class="rounded-xl border border-red-100 bg-red-50 p-5">
      <p role="alert" class="text-sm text-red-600">근무처 목록을 불러오지 못했습니다.</p>

      <button
        type="button"
        class="mt-3 text-sm font-medium text-red-700 underline"
        @click="refetch()"
      >
        다시 시도
      </button>
    </div>

    <!-- 근무처 목록 없음 -->
    <p
      v-else-if="!activeCompanies.length && !archivedWorkplaces.length"
      class="rounded-xl border border-slate-200 bg-white p-6 text-sm text-slate-500"
    >
      등록된 근무처가 없습니다.
    </p>

    <!-- 근무처 목록 -->
    <div v-else class="space-y-4">
      <!-- 기본 개인 고객 근무처 -->
      <div v-if="personalCompany" class="rounded-xl border border-blue-100 bg-blue-50/40 p-5">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex items-center gap-3">
            <div
              class="flex h-11 w-11 items-center justify-center rounded-lg bg-blue-100 text-blue-700"
            >
              <span class="text-lg">👤</span>
            </div>

            <div>
              <h2 class="font-semibold text-slate-900">
                {{ personalCompany.name }}
              </h2>

              <p class="mt-1 text-xs text-slate-500">회사에 소속되지 않은 개인 회원 관리</p>
            </div>
          </div>

          <span class="rounded-full bg-blue-100 px-3 py-1 text-xs font-medium text-blue-700">
            기본 근무처
          </span>
        </div>
      </div>

      <!-- 일반 근무처 목록 제목 -->
      <div class="flex items-center justify-between">
        <h2 class="text-base font-semibold text-slate-800">등록한 근무처</h2>

        <span class="text-sm text-slate-500"> {{ workplaces.length }}곳 </span>
      </div>

      <!-- 일반 근무처 없음 -->
      <p
        v-if="!workplaces.length"
        class="rounded-xl border border-dashed border-slate-200 bg-white p-6 text-sm text-slate-400"
      >
        아직 등록한 근무처가 없습니다.
      </p>

      <!-- 일반 근무처 카드 -->
      <div class="grid gap-4 md:grid-cols-2">
        <div
          v-for="company in workplaces"
          :key="company.id"
          class="rounded-xl border border-slate-200 bg-white p-5"
        >
          <!-- 근무처 기본 정보 -->
          <div class="flex items-center gap-3">
            <div
              class="flex h-11 w-11 items-center justify-center rounded-lg bg-slate-100 text-slate-600"
            >
              <span class="text-lg">🏢</span>
            </div>

            <div class="min-w-0 flex-1">
              <h3 class="truncate font-semibold text-slate-900">
                {{ company.name }}
              </h3>

              <p class="mt-1 text-xs text-slate-500">근무처</p>
            </div>
          </div>

          <!-- 근무처 이름 수정 폼 -->
          <form
            v-if="editingCompanyId === company.id"
            class="mt-4 space-y-3 border-t border-slate-100 pt-4"
            @submit.prevent="submitEdit(company)"
          >
            <label
              :for="`edit-company-${company.id}`"
              class="block text-sm font-medium text-slate-700"
            >
              근무처 이름 수정
            </label>

            <input
              :id="`edit-company-${company.id}`"
              v-model="editingCompanyName"
              type="text"
              required
              maxlength="100"
              :disabled="isUpdating"
              class="w-full rounded-lg border border-slate-200 px-4 py-2.5 text-sm outline-none focus:border-blue-500 disabled:opacity-50"
            />

            <div class="flex justify-end gap-2">
              <button
                type="button"
                :disabled="isUpdating"
                class="rounded-lg border border-slate-200 px-3 py-2 text-sm text-slate-600 hover:bg-slate-50 disabled:opacity-50"
                @click="cancelEditing"
              >
                취소
              </button>

              <button
                type="submit"
                :disabled="isEditSubmitDisabled"
                class="rounded-lg bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:bg-slate-300"
              >
                {{ isPendingCompany(company.id) ? '저장 중...' : '저장' }}
              </button>
            </div>
          </form>

          <!-- 일반 근무처 관리 버튼 -->
          <div v-else class="mt-4 flex justify-end gap-2 border-t border-slate-100 pt-4">
            <button
              type="button"
              :disabled="isUpdating"
              class="rounded-lg border border-slate-200 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50"
              @click="startEditing(company)"
            >
              이름 수정
            </button>

            <button
              type="button"
              :disabled="isUpdating"
              class="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm font-medium text-amber-700 hover:bg-amber-100 disabled:opacity-50"
              @click="changeCompanyStatus(company, 'archive')"
            >
              {{ isPendingCompany(company.id) ? '보관 중...' : '보관' }}
            </button>
          </div>

          <!-- 근무처 수정 및 보관 오류 -->
          <p
            v-if="actionError?.companyId === company.id"
            role="alert"
            class="mt-3 text-xs text-red-600"
          >
            {{ actionError.message }}
          </p>
        </div>
      </div>

      <!-- 보관된 근무처 목록 -->
      <div v-if="archivedWorkplaces.length" class="border-t border-slate-200 pt-5">
        <!-- 보관된 근무처 펼치기 -->
        <button
          type="button"
          :aria-expanded="showArchived"
          class="text-sm font-medium text-slate-600 hover:text-blue-600"
          @click="showArchived = !showArchived"
        >
          {{ showArchived ? '▾' : '▸' }}
          보관된 근무처 ({{ archivedWorkplaces.length }})
        </button>

        <!-- 보관된 근무처 카드 -->
        <div v-if="showArchived" class="mt-4 grid gap-4 md:grid-cols-2">
          <div
            v-for="company in archivedWorkplaces"
            :key="company.id"
            class="rounded-xl border border-slate-200 bg-slate-50 p-5"
          >
            <div class="flex items-center gap-3">
              <div
                class="flex h-11 w-11 items-center justify-center rounded-lg bg-slate-200 text-slate-500"
              >
                <span class="text-lg">🏢</span>
              </div>

              <div class="min-w-0 flex-1">
                <h3 class="truncate font-semibold text-slate-700">
                  {{ company.name }}
                </h3>

                <p class="mt-1 text-xs text-slate-400">보관된 근무처</p>
              </div>
            </div>

            <!-- 근무처 보관 해제 버튼 -->
            <div class="mt-4 flex justify-end border-t border-slate-200 pt-4">
              <button
                type="button"
                :disabled="isUpdating"
                class="rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-sm font-medium text-green-700 hover:bg-green-100 disabled:opacity-50"
                @click="changeCompanyStatus(company, 'restore')"
              >
                {{ isPendingCompany(company.id) ? '복구 중...' : '보관 해제' }}
              </button>
            </div>

            <!-- 보관 해제 오류 -->
            <p
              v-if="actionError?.companyId === company.id"
              role="alert"
              class="mt-3 text-xs text-red-600"
            >
              {{ actionError.message }}
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
