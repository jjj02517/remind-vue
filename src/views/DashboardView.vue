<script setup lang="ts">
import DashboardMonthlySessions from '@/components/dashboard/DashboardMonthlySessions.vue'
import DashboardOverviewCards from '@/components/dashboard/DashboardOverviewCards.vue'
import DashboardTodaySessions from '@/components/dashboard/DashboardTodaySessions.vue'
import DashboardPackageAlerts from '@/components/dashboard/DashboardPackageAlerts.vue'
</script>

<template>
  <div class="space-y-6">
    <!-- 회원·근무처·이용권 운영 현황-->
    <DashboardOverviewCards />

    <!-- 월별 수업 통계 -->
    <DashboardMonthlySessions />

    <!-- 오늘 수업 통계 -->
    <DashboardTodaySessions />

    <!-- 이용권 알림 -->
    <DashboardPackageAlerts />
  </div>
</template>
