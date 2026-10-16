<script setup lang="ts">
import { useRoute } from 'vue-router'

// 현재 페이지의 라우트 정보
const route = useRoute()

// URL에서 회원 ID 가져오기
const memberId = route.params.id
</script>

<template>
  <div>
    <!-- 페이지 제목 -->
    <h1 class="text-3xl font-bold text-slate-900">회원 상세</h1>

    <!-- 페이지 설명 -->
    <p class="mt-2 text-slate-500">회원 정보와 PT 이용 현황을 확인합니다.</p>

    <!-- 회원 정보 -->
    <div class="mt-8 rounded-xl border border-slate-200 bg-white p-5 sm:p-6">
      <p class="text-sm text-slate-500">선택한 회원 ID</p>
      <p class="mt-2 text-2xl font-bold text-blue-600">
        {{ memberId }}
      </p>
    </div>
  </div>
</template>
