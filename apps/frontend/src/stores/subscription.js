import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import axios from 'axios'
const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || ''

const api = axios.create({
  baseURL: apiBaseUrl
})

export const useSubscriptionStore = defineStore('subscription', () => {
  const token = ref(localStorage.getItem('sub_token') || '')
  const user = ref(JSON.parse(localStorage.getItem('sub_user') || 'null'))

  const isLoggedIn = computed(() => !!token.value && !!user.value)
  const isAdmin = computed(() => user.value?.role === 'admin')
  const userName = computed(() => user.value?.name || user.value?.username || '')

  // 设置请求头
  const getAuthHeaders = () => ({
    Authorization: `Bearer ${token.value}`
  })

  // 登录
  const login = async (credentials) => {
    const response = await api.post('/sub/auth/login', credentials)
    if (response.data.success) {
      token.value = response.data.token
      user.value = response.data.user
      localStorage.setItem('sub_token', response.data.token)
      localStorage.setItem('sub_user', JSON.stringify(response.data.user))
    }
    return response.data
  }

  // 登出
  const logout = async () => {
    try {
      await api.post('/sub/auth/logout', {}, { headers: getAuthHeaders() })
    } catch (e) {
      // 忽略错误
    }
    token.value = ''
    user.value = null
    localStorage.removeItem('sub_token')
    localStorage.removeItem('sub_user')
  }

  // 验证会话
  const verifySession = async () => {
    if (!token.value) return false
    try {
      const response = await api.get('/sub/auth/verify', { headers: getAuthHeaders() })
      if (response.data.success) {
        user.value = response.data.user
        localStorage.setItem('sub_user', JSON.stringify(response.data.user))
        return true
      }
    } catch (e) {
      logout()
    }
    return false
  }

  // 获取订阅信息
  const getSubscription = async () => {
    const response = await api.get('/sub/auth/subscription', { headers: getAuthHeaders() })
    return response.data.data
  }

  // 获取节点列表
  const getNodes = async () => {
    const response = await api.get('/sub/auth/nodes', { headers: getAuthHeaders() })
    return response.data.data
  }

  // 获取统计信息
  const getStats = async () => {
    const response = await api.get('/sub/auth/stats', { headers: getAuthHeaders() })
    return response.data.data
  }

  // 获取当前用户流量信息
  const getUserTraffic = async () => {
    const response = await api.get('/sub/auth/user-traffic', { headers: getAuthHeaders() })
    return response.data.data
  }

  // 修改密码
  const changePassword = async (oldPassword, newPassword) => {
    const response = await api.post(
      '/sub/auth/change-password',
      { oldPassword, newPassword },
      { headers: getAuthHeaders() }
    )
    return response.data
  }

  // 重新生成订阅链接
  const regenerateToken = async () => {
    const response = await api.post('/sub/auth/regenerate-token', {}, { headers: getAuthHeaders() })
    if (response.data.success) {
      // 更新本地用户信息
      user.value.subscriptionToken = response.data.data.token
      localStorage.setItem('sub_user', JSON.stringify(user.value))
    }
    return response.data
  }

  // ==================== 管理员功能 ====================

  // 获取下级用户列表（包含统计信息）
  const getSubUsers = async () => {
    const response = await api.get('/sub/auth/sub-users', { headers: getAuthHeaders() })
    return response.data // 返回完整响应，包含 data, total, stats
  }

  // 获取管理员统计信息
  const getAdminStats = async () => {
    const response = await api.get('/sub/auth/admin-stats', { headers: getAuthHeaders() })
    return response.data.data
  }

  // 重置下级用户流量
  const resetSubUserTraffic = async (userId) => {
    const response = await api.post(
      `/sub/auth/sub-users/${userId}/reset-traffic`,
      {},
      { headers: getAuthHeaders() }
    )
    return response.data
  }

  // 创建下级用户
  const createSubUser = async (userData) => {
    const response = await api.post('/sub/auth/sub-users', userData, { headers: getAuthHeaders() })
    return response.data
  }

  // 更新下级用户
  const updateSubUser = async (userId, userData) => {
    const response = await api.put(`/sub/auth/sub-users/${userId}`, userData, {
      headers: getAuthHeaders()
    })
    return response.data
  }

  // 删除下级用户
  const deleteSubUser = async (userId) => {
    const response = await api.delete(`/sub/auth/sub-users/${userId}`, {
      headers: getAuthHeaders()
    })
    return response.data
  }

  // 重置下级用户密码
  const resetSubUserPassword = async (userId, newPassword) => {
    const response = await api.post(
      `/sub/auth/sub-users/${userId}/reset-password`,
      { newPassword },
      { headers: getAuthHeaders() }
    )
    return response.data
  }

  // 为下级用户重新生成订阅链接
  const regenerateSubUserToken = async (userId) => {
    const response = await api.post(
      `/sub/auth/sub-users/${userId}/regenerate-token`,
      {},
      { headers: getAuthHeaders() }
    )
    return response.data
  }

  return {
    token,
    user,
    isLoggedIn,
    isAdmin,
    userName,
    login,
    logout,
    verifySession,
    getSubscription,
    getNodes,
    getStats,
    getUserTraffic,
    changePassword,
    regenerateToken,
    getSubUsers,
    getAdminStats,
    createSubUser,
    updateSubUser,
    deleteSubUser,
    resetSubUserPassword,
    regenerateSubUserToken,
    resetSubUserTraffic
  }
})
