import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { VueQueryPlugin } from '@tanstack/vue-query'

import App from './App.vue'
import router from './router'

import './assets/main.css'

// Vue 앱 생성
const app = createApp(App)

// Pinia 등록
app.use(createPinia())

// Vue Router 등록
app.use(router)

// TanStack Query 등록
app.use(VueQueryPlugin)

// 앱 마운트
app.mount('#app')
