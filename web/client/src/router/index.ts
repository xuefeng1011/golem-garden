import { createRouter, createWebHashHistory } from 'vue-router'

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/',
      redirect: '/hermes/overview',
    },
    {
      path: '/hermes/overview',
      name: 'hermes.overview',
      component: () => import('@/views/hermes/OverviewView.vue'),
    },
    {
      path: '/hermes/chat',
      name: 'hermes.chat',
      component: () => import('@/views/hermes/ChatView.vue'),
    },
    {
      path: '/hermes/models',
      name: 'hermes.models',
      component: () => import('@/views/hermes/ModelsView.vue'),
    },
    {
      path: '/hermes/profiles',
      name: 'hermes.profiles',
      component: () => import('@/views/hermes/ProfilesView.vue'),
    },
    {
      path: '/hermes/usage',
      name: 'hermes.usage',
      component: () => import('@/views/hermes/UsageView.vue'),
    },
    {
      path: '/hermes/skills',
      name: 'hermes.skills',
      component: () => import('@/views/hermes/SkillsView.vue'),
    },
    {
      path: '/hermes/settings',
      name: 'hermes.settings',
      component: () => import('@/views/hermes/SettingsView.vue'),
    },
    {
      path: '/hermes/souls',
      name: 'hermes.souls',
      component: () => import('@/views/hermes/SoulsView.vue'),
    },
    {
      path: '/hermes/activity',
      name: 'hermes.activity',
      component: () => import('@/views/hermes/ActivityView.vue'),
    },
    {
      path: '/hermes/team',
      name: 'hermes.team',
      component: () => import('@/views/hermes/TeamView.vue'),
    },
    {
      path: '/hermes/forge',
      name: 'hermes.forge',
      component: () => import('@/views/hermes/ForgeView.vue'),
    },
    {
      path: '/hermes/meta',
      name: 'hermes.meta',
      component: () => import('@/views/hermes/MetaView.vue'),
    },
    {
      path: '/hermes/console',
      name: 'hermes.console',
      component: () => import('@/views/hermes/ConsoleView.vue'),
    },
    {
      path: '/hermes/canvas',
      name: 'hermes.canvas',
      component: () => import('@/views/hermes/CanvasView.vue'),
    },
  ],
})

export default router
