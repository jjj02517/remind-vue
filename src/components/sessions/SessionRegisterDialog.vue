<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useMutation, useQuery } from '@tanstack/vue-query'
import { CalendarPlus2, X } from 'lucide-vue-next'

import { getCompanies } from '@/api/companies'
import { createSession, getSessionConflicts, getSessionMemberOptions } from '@/api/sessions'
import type { SessionMemberOption, SessionType } from '@/api/sessions'
import { blockDemoWrite } from '@/utils/demoGuard'

// 달력에서 선택한 날짜를 신규 수업 등록 폼의 기본 날짜로 사용
const props = defineProps<{ initialDate: string }>()
const emit = defineEmits<{ registered: [] }>()

// PT와 그룹 수업 선택 옵션
const sessionTypeOptions = [
  { value: 'pt', label: 'PT 수업' },
  { value: 'group', label: '그룹 수업' },
] as const

// 모달 및 수업 등록 폼 상태
const isOpen = ref(false)
const companyId = ref('')
const sessionType = ref<SessionType>('pt')
const date = ref('')
const startTime = ref('09:00')
// 수업은 정시에 시작해서 정확히 1시간 진행 (23시는 다음 날 00시 종료)
const startTimeOptions = Array.from(
  { length: 24 },
  (_, hour) => `${String(hour).padStart(2, '0')}:00`,
)
const endTime = computed(() => {
  const nextHour = (Number(startTime.value.slice(0, 2)) + 1) % 24
  return `${String(nextHour).padStart(2, '0')}:00`
})
const endsNextDay = computed(() => startTime.value === '23:00')
const notes = ref('')
const selectedMemberIds = ref<string[]>([])
const selectedPackageIds = ref<Record<string, string>>({})
const formError = ref('')

// 활성 근무처 조회 (기본 개인 고객 포함)
const {
  data: companies,
  isPending: isCompaniesLoading,
  error: companiesError,
} = useQuery({
  queryKey: ['companies'],
  queryFn: getCompanies,
  staleTime: 1000 * 60 * 5,
})
const activeCompanies = computed(() =>
  (companies.value ?? []).filter((company) => company.is_active),
)

// 첫 활성 근무처를 기본으로 선택
watch(
  activeCompanies,
  (items) => {
    if (!items.some((company) => company.id === companyId.value)) {
      companyId.value = items[0]?.id ?? ''
    }
  },
  { immediate: true },
)

// 근무처/수업 종류별로 등록 가능한 회원·횟수제 이용권 목록 조회
const {
  data: availableMembers,
  isPending: isMembersLoading,
  error: membersError,
} = useQuery({
  queryKey: computed(() => ['session-member-options', companyId.value, sessionType.value]),
  queryFn: () => getSessionMemberOptions(companyId.value, sessionType.value),
  enabled: computed(() => isOpen.value && !!companyId.value),
  staleTime: 1000 * 30,
})

// 날짜 또는 시작 시각을 선택하면 기존 예약과 겹치는 수업 확인
// 최종 중복 방지는 DB 등록 RPC에서 다시 검증
const {
  data: conflictingSessions,
  isFetching: isCheckingConflicts,
  error: conflictsError,
} = useQuery({
  queryKey: computed(() => ['session-conflicts', date.value, startTime.value]),
  queryFn: () => getSessionConflicts(date.value, startTime.value),
  enabled: computed(() => isOpen.value && !!date.value && !!startTime.value),
  staleTime: 0,
  retry: false,
})

// 근무처나 수업 종류가 바뀌면 회원 및 이용권 선택 초기화
watch([companyId, sessionType], () => {
  selectedMemberIds.value = []
  selectedPackageIds.value = {}
  formError.value = ''
})

const selectableMembers = computed<SessionMemberOption[]>(() =>
  (availableMembers.value ?? []).filter((member) =>
    member.packages.some(
      (pkg) =>
        (!pkg.startsOn || pkg.startsOn <= date.value) && (!pkg.endsOn || pkg.endsOn >= date.value),
    ),
  ),
)

// 선택 날짜에 실제 이용 가능한 이용권만 표시
function getValidPackages(member: SessionMemberOption) {
  return member.packages.filter(
    (pkg) =>
      (!pkg.startsOn || pkg.startsOn <= date.value) && (!pkg.endsOn || pkg.endsOn >= date.value),
  )
}

// 날짜 변경 시 유효하지 않은 회원/이용권 선택 제거
watch(date, () => {
  const eligibleIds = new Set(selectableMembers.value.map((member) => member.id))
  selectedMemberIds.value = selectedMemberIds.value.filter((id) => eligibleIds.has(id))
  const next: Record<string, string> = {}
  for (const member of selectableMembers.value) {
    if (!selectedMemberIds.value.includes(member.id)) continue
    const validPackages = getValidPackages(member)
    const previous = selectedPackageIds.value[member.id]
    next[member.id] =
      validPackages.find((pkg) => pkg.id === previous)?.id ?? validPackages[0]?.id ?? ''
  }
  selectedPackageIds.value = next
})

// PT는 회원 1명, 그룹은 여러 회원 선택
function selectPtMember(memberId: string) {
  selectedMemberIds.value = memberId ? [memberId] : []
  const member = selectableMembers.value.find((item) => item.id === memberId)
  selectedPackageIds.value = member ? { [memberId]: getValidPackages(member)[0]?.id ?? '' } : {}
}

function toggleGroupMember(memberId: string, checked: boolean) {
  if (checked) {
    if (selectedMemberIds.value.includes(memberId)) return
    selectedMemberIds.value = [...selectedMemberIds.value, memberId]
    const member = selectableMembers.value.find((item) => item.id === memberId)
    if (member) selectedPackageIds.value[memberId] = getValidPackages(member)[0]?.id ?? ''
  } else {
    selectedMemberIds.value = selectedMemberIds.value.filter((id) => id !== memberId)
    delete selectedPackageIds.value[memberId]
  }
}

// 이용권 잔여 횟수를 함께 표시
function packageLabel(pkg: SessionMemberOption['packages'][number]) {
  const validity = pkg.endsOn ? ` · ${pkg.endsOn}까지` : ''
  return `${pkg.remainingSessions}/${pkg.totalSessions}회${validity}`
}

// 등록 모달 열기·닫기 (부모 컴포넌트에서 호출)
function open() {
  date.value = props.initialDate
  startTime.value = '09:00'
  sessionType.value = 'pt'
  notes.value = ''
  selectedMemberIds.value = []
  selectedPackageIds.value = {}
  formError.value = ''
  isOpen.value = true
}

const { mutateAsync: registerSession, isPending: isSaving } = useMutation({
  mutationFn: createSession,
})

function close() {
  if (isSaving.value) return
  isOpen.value = false
}

defineExpose({ open })

// 수업과 회원별 이용권을 한 번에 저장 (예약 시 횟수 차감 없음)
async function submit() {
  if (isSaving.value) return
  formError.value = ''

  if (await blockDemoWrite()) return

  const participants = selectedMemberIds.value.map((memberId) => ({
    memberId,
    packageId: selectedPackageIds.value[memberId] ?? '',
  }))

  if (conflictingSessions.value?.length) {
    formError.value = '기존 수업과 시간이 겹칩니다. 다른 시작 시간을 선택해 주세요.'
    return
  }

  if (participants.some((person) => !person.packageId)) {
    formError.value = '모든 참여 회원의 이용권을 선택해 주세요.'
    return
  }

  try {
    await registerSession({
      companyId: companyId.value,
      sessionType: sessionType.value,
      date: date.value,
      startTime: startTime.value,
      participants,
      notes: notes.value,
    })
    isOpen.value = false
    emit('registered')
  } catch (error) {
    console.error('수업 등록 오류:', error)
    formError.value = error instanceof Error ? error.message : '수업을 등록하지 못했습니다.'
  }
}
</script>

<template>
  <!-- PT·그룹 수업 신규 등록 모달 -->
  <div
    v-if="isOpen"
    class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/55 px-4 py-5"
    @click.self="close"
  >
    <section
      role="dialog"
      aria-modal="true"
      aria-labelledby="session-register-title"
      class="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white p-5 shadow-xl sm:p-6 md:max-w-[720px] lg:max-w-[900px]"
    >
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <CalendarPlus2 :size="21" class="text-blue-600" aria-hidden="true" />
          <h2 id="session-register-title" class="text-lg font-bold text-slate-900">새 수업 등록</h2>
        </div>
        <button
          type="button"
          aria-label="수업 등록 닫기"
          class="rounded-lg p-2 text-slate-500 hover:bg-slate-100"
          :disabled="isSaving"
          @click="close"
        >
          <X :size="19" aria-hidden="true" />
        </button>
      </div>

      <form class="mt-5 space-y-5" @submit.prevent="submit">
        <!-- 수업 종류 선택 -->
        <fieldset>
          <legend class="mb-2 text-sm font-semibold text-slate-700">수업 종류</legend>
          <div class="grid grid-cols-2 gap-2">
            <label
              v-for="option in sessionTypeOptions"
              :key="option.value"
              class="cursor-pointer rounded-lg border px-3 py-2.5 text-center text-sm font-medium"
              :class="
                sessionType === option.value
                  ? 'border-blue-500 bg-blue-50 text-blue-700'
                  : 'border-slate-200 text-slate-600'
              "
            >
              <input
                v-model="sessionType"
                class="sr-only"
                type="radio"
                name="session-type"
                :value="option.value"
              />
              {{ option.label }}
            </label>
          </div>
        </fieldset>

        <!-- 근무처 선택 -->
        <div>
          <label for="session-company" class="mb-2 block text-sm font-semibold text-slate-700"
            >근무처</label
          >
          <select
            id="session-company"
            v-model="companyId"
            required
            class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm focus:border-blue-500"
          >
            <option value="" disabled>근무처 선택</option>
            <option v-for="company in activeCompanies" :key="company.id" :value="company.id">
              {{ company.name }}
            </option>
          </select>
          <p v-if="isCompaniesLoading" class="mt-2 text-xs text-slate-500">
            근무처를 불러오는 중...
          </p>
          <p v-else-if="companiesError" role="alert" class="mt-2 text-xs text-red-600">
            근무처 목록을 불러오지 못했습니다.
          </p>
        </div>

        <!-- 수업 날짜와 시간 -->
        <div class="grid gap-3 sm:grid-cols-3">
          <div>
            <label for="session-date" class="mb-2 block text-sm font-semibold text-slate-700"
              >수업 날짜</label
            >
            <input
              id="session-date"
              v-model="date"
              type="date"
              required
              class="w-full rounded-lg border border-slate-200 px-3 py-2.5 text-sm"
            />
          </div>
          <div>
            <label for="session-start" class="mb-2 block text-sm font-semibold text-slate-700"
              >시작 시간</label
            >
            <select
              id="session-start"
              v-model="startTime"
              required
              class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm"
            >
              <option v-for="time in startTimeOptions" :key="time" :value="time">{{ time }}</option>
            </select>
          </div>
          <div>
            <label for="session-end" class="mb-2 block text-sm font-semibold text-slate-700"
              >종료 시간</label
            >
            <div
              id="session-end"
              class="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2.5 text-sm text-slate-700"
              aria-live="polite"
            >
              {{ endTime }} <span v-if="endsNextDay" class="text-xs text-blue-700">(+1일)</span>
            </div>
          </div>
        </div>

        <!-- 수업은 정시에 시작하며 종료 시간은 자동으로 1시간 뒤로 설정 -->
        <p class="text-xs text-slate-500">
          수업은 정시 시작, 1시간 고정입니다. 종료 시간은 자동으로 설정됩니다.
        </p>

        <!-- 기존 수업과 시간 중복 여부 확인 -->
        <p v-if="isCheckingConflicts" class="text-xs text-slate-500">
          기존 수업과 시간이 겹치는지 확인 중...
        </p>
        <p
          v-else-if="conflictsError"
          role="alert"
          class="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700"
        >
          기존 수업을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.
        </p>
        <div
          v-else-if="conflictingSessions?.length"
          role="alert"
          class="rounded-lg border border-red-200 bg-red-50 px-3 py-3 text-sm text-red-700"
        >
          <p class="font-semibold">이미 등록된 수업과 시간이 겹칩니다.</p>
          <p v-for="conflict in conflictingSessions" :key="conflict.id" class="mt-1 text-xs">
            {{ conflict.startTime }}~{{ conflict.endTime }} · {{ conflict.companyName }} ·
            {{ conflict.type === 'pt' ? 'PT' : '그룹' }}
          </p>
          <p class="mt-1 text-xs">다른 시작 시간을 선택해 주세요.</p>
        </div>

        <!-- 소속 근무처의 횟수제 이용권을 가진 회원만 선택 -->
        <div class="space-y-3">
          <div>
            <h3 class="text-sm font-semibold text-slate-700">
              {{ sessionType === 'pt' ? '회원 선택' : '참여 회원 선택' }}
            </h3>
            <p class="mt-1 text-xs text-slate-500">
              선택한 근무처에 연결된 {{ sessionType === 'pt' ? 'PT' : '그룹' }} 횟수제 이용권만
              표시합니다.
            </p>
          </div>
          <p v-if="isMembersLoading" class="rounded-lg bg-slate-50 p-3 text-sm text-slate-500">
            회원과 이용권을 불러오는 중...
          </p>
          <p
            v-else-if="membersError"
            role="alert"
            class="rounded-lg bg-red-50 p-3 text-sm text-red-600"
          >
            회원·이용권 정보를 불러오지 못했습니다.
          </p>
          <p
            v-else-if="!selectableMembers.length"
            class="rounded-lg border border-dashed border-slate-200 p-4 text-sm text-slate-500"
          >
            해당 날짜에 사용 가능한 이용권을 가진 회원이 없습니다.
          </p>
          <template v-else-if="sessionType === 'pt'">
            <label for="session-pt-member" class="sr-only">PT 회원</label>
            <select
              id="session-pt-member"
              :value="selectedMemberIds[0] ?? ''"
              class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm"
              @change="selectPtMember(($event.target as HTMLSelectElement).value)"
            >
              <option value="">회원 선택</option>
              <option v-for="member in selectableMembers" :key="member.id" :value="member.id">
                {{ member.name }}
              </option>
            </select>
            <div
              v-for="member in selectableMembers.filter((item) =>
                selectedMemberIds.includes(item.id),
              )"
              :key="member.id"
            >
              <label :for="`session-package-${member.id}`" class="mb-2 block text-xs text-slate-600"
                >{{ member.name }}님의 이용권</label
              >
              <select
                :id="`session-package-${member.id}`"
                v-model="selectedPackageIds[member.id]"
                required
                class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm"
              >
                <option v-for="pkg in getValidPackages(member)" :key="pkg.id" :value="pkg.id">
                  {{ packageLabel(pkg) }}
                </option>
              </select>
            </div>
          </template>
          <div
            v-else
            class="max-h-72 space-y-2 overflow-y-auto rounded-lg border border-slate-200 p-3"
          >
            <div
              v-for="member in selectableMembers"
              :key="member.id"
              class="border-b border-slate-100 pb-3 last:border-0 last:pb-0"
            >
              <label
                class="flex cursor-pointer items-center gap-2 text-sm font-medium text-slate-800"
              >
                <input
                  type="checkbox"
                  :checked="selectedMemberIds.includes(member.id)"
                  class="h-4 w-4 rounded border-slate-300 accent-blue-600"
                  @change="
                    toggleGroupMember(member.id, ($event.target as HTMLInputElement).checked)
                  "
                />
                {{ member.name }}
              </label>
              <div v-if="selectedMemberIds.includes(member.id)" class="mt-2 pl-6">
                <label :for="`session-package-${member.id}`" class="sr-only"
                  >{{ member.name }}님의 그룹 이용권</label
                >
                <select
                  :id="`session-package-${member.id}`"
                  v-model="selectedPackageIds[member.id]"
                  required
                  class="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-xs"
                >
                  <option v-for="pkg in getValidPackages(member)" :key="pkg.id" :value="pkg.id">
                    {{ packageLabel(pkg) }}
                  </option>
                </select>
              </div>
            </div>
          </div>
          <p v-if="sessionType === 'group'" class="text-xs text-slate-500">
            선택 회원 {{ selectedMemberIds.length }}명 · 그룹 정산은 추후 실제 출석 인원 기준으로
            계산합니다.
          </p>
        </div>

        <!-- 선택 메모 -->
        <div>
          <label for="session-notes" class="mb-2 block text-sm font-semibold text-slate-700"
            >메모 (선택)</label
          >
          <textarea
            id="session-notes"
            v-model="notes"
            rows="2"
            maxlength="1000"
            class="w-full rounded-lg border border-slate-200 px-3 py-2.5 text-sm"
            placeholder="수업 관련 메모"
          />
        </div>

        <p class="text-xs text-slate-500">
          수업 예약 시 이용권 횟수는 차감되지 않습니다. 출석 처리 기능에서 차감할 예정입니다.
        </p>
        <p
          v-if="formError"
          role="alert"
          class="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600"
        >
          {{ formError }}
        </p>
        <div class="flex justify-end gap-2 border-t border-slate-100 pt-4">
          <button
            type="button"
            class="rounded-lg border border-slate-200 px-4 py-2.5 text-sm text-slate-600 hover:bg-slate-50"
            :disabled="isSaving"
            @click="close"
          >
            취소
          </button>
          <button
            type="submit"
            :disabled="
              isSaving ||
              isMembersLoading ||
              !!membersError ||
              isCheckingConflicts ||
              !!conflictsError ||
              !!conflictingSessions?.length ||
              !companyId ||
              !selectedMemberIds.length ||
              (sessionType === 'group' && selectedMemberIds.length > 30)
            "
            class="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-slate-300"
          >
            {{ isSaving ? '등록 중...' : '수업 등록' }}
          </button>
        </div>
      </form>
    </section>
  </div>
</template>
