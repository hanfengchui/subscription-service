import { createRouter, createWebHistory } from 'vue-router'
import { useSubscriptionStore } from '@/stores/subscription'

const SubLoginView = () => import('@/views/SubLoginView.vue')
const SubDashboardView = () => import('@/views/SubDashboardView.vue')

const routes = [
  {
    path: '/',
    redirect: '/sub-login'
  },
  {
    path: '/sub-login',
    name: 'SubLogin',
    component: SubLoginView,
    meta: { requiresSubAuth: false }
  },
  {
    path: '/sub-dashboard',
    name: 'SubDashboard',
    component: SubDashboardView,
    meta: { requiresSubAuth: true }
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/sub-login'
  }
]

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes
})

router.beforeEach(async (to, from, next) => {
  const subStore = useSubscriptionStore()

  if (to.meta.requiresSubAuth) {
    if (!subStore.isLoggedIn) {
      try {
        const isValid = await subStore.verifySession()
        if (!isValid) {
          return next('/sub-login')
        }
      } catch {
        return next('/sub-login')
      }
    }
  }

  if (to.path === '/sub-login' && subStore.isLoggedIn) {
    return next('/sub-dashboard')
  }

  return next()
})

export default router
