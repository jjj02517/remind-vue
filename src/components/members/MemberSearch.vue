<script setup lang="ts">
// 부모 컴포넌트와 검색어 양방향 바인딩
const searchKeyword = defineModel<string>({ required: true })
</script>

<template>
  <!-- 회원 검색 -->
  <div class="mt-8">
    <input
      v-model="searchKeyword"
      type="search"
      placeholder="회원명 또는 연락처 검색"
      aria-label="회원 검색"
      class="w-full max-w-sm rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm outline-none focus:border-blue-500"
    />
  </div>
</template>
