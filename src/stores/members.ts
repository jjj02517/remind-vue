import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Member } from '@/types/member'

// 회원 데이터 전역 관리
export const useMemberStore = defineStore('members', () => {
  // 임시 회원 데이터 (Mock Data)
  const members = ref<Member[]>([
    {
      id: 1,
      name: '김민수',
      phone: '01012345678',
      totalSessions: 20,
      remainingSessions: 12,
    },
    {
      id: 2,
      name: '이지은',
      phone: '01023456789',
      totalSessions: 30,
      remainingSessions: 18,
    },
    {
      id: 3,
      name: '박서준',
      phone: '01034567890',
      totalSessions: 10,
      remainingSessions: 3,
    },
  ])

  // 신규 회원 등록
  function registerMember(member: Pick<Member, 'name' | 'phone' | 'totalSessions'>) {
    const nextId = Math.max(0, ...members.value.map((item) => item.id)) + 1

    members.value.push({
      id: nextId,
      name: member.name,
      phone: member.phone,
      totalSessions: member.totalSessions,
      remainingSessions: member.totalSessions,
    })
  }

  // 회원 ID로 조회
  function getMemberById(id: number) {
    return members.value.find((member) => member.id === id)
  }

  return {
    members,
    registerMember,
    getMemberById,
  }
})
