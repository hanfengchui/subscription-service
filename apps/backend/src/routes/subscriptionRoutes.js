/**
 * 订阅路由 - 安全的动态订阅链接
 */

const express = require('express')
const router = express.Router()
const subscriptionService = require('../services/subscriptionService')
const subUserService = require('../services/subUserService')
const { authenticateAdminApiKey } = require('../middleware/adminApiKey')
const logger = require('../utils/logger')

/**
 * 获取客户端真实 IP
 */
function getClientIP(req) {
  return (
    req.headers['cf-connecting-ip'] ||
    req.headers['x-real-ip'] ||
    req.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
    req.connection?.remoteAddress ||
    req.ip
  )
}

/**
 * 获取对外访问的 Base URL
 * 优先使用环境变量 SUB_PUBLIC_BASE_URL，否则根据请求头自动推断
 */
function getPublicBaseUrl(req) {
  const envBase = process.env.SUB_PUBLIC_BASE_URL
  if (envBase && envBase.trim()) {
    return envBase.replace(/\/$/, '')
  }

  const forwardedProto = req.headers['x-forwarded-proto']
  const proto = (Array.isArray(forwardedProto) ? forwardedProto[0] : forwardedProto) || req.protocol
  const forwardedHost = req.headers['x-forwarded-host']
  const host = (Array.isArray(forwardedHost) ? forwardedHost[0] : forwardedHost) || req.headers.host

  if (!host) return ''
  return `${proto}://${host}`
}

function buildPublicUrl(req, path) {
  const baseUrl = getPublicBaseUrl(req)
  const normalizedPath = path.startsWith('/') ? path : `/${path}`
  return baseUrl ? `${baseUrl}${normalizedPath}` : normalizedPath
}

/**
 * 订阅用户认证中间件
 */
async function authenticateSubUser(req, res, next) {
  const token = req.headers['authorization']?.replace('Bearer ', '') || req.headers['x-session-token']

  if (!token) {
    return res.status(401).json({ error: '未登录' })
  }

  const validation = await subUserService.validateSession(token)
  if (!validation.valid) {
    return res.status(401).json({ error: validation.error })
  }

  req.subUser = validation.user
  next()
}

/**
 * 订阅管理员认证中间件（验证订阅用户是否为管理员角色）
 * 重要：只允许顶级管理员（没有 parentId 的管理员）创建和管理下级用户
 */
async function authenticateSubAdmin(req, res, next) {
  const token = req.headers['authorization']?.replace('Bearer ', '') || req.headers['x-session-token']

  if (!token) {
    return res.status(401).json({ error: '未登录' })
  }

  const validation = await subUserService.validateSession(token)
  if (!validation.valid) {
    return res.status(401).json({ error: validation.error })
  }

  // 必须是管理员角色
  if (validation.user.role !== 'admin') {
    return res.status(403).json({ error: '需要管理员权限' })
  }

  // 必须是顶级管理员（没有父级用户）
  if (validation.user.parentId) {
    return res.status(403).json({ error: '只有顶级管理员才能管理下级用户' })
  }

  req.subUser = validation.user
  next()
}

/**
 * 健康检查
 * GET /sub/health
 */
router.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'subscription-service',
    timestamp: new Date().toISOString()
  })
})

// ==================== 用户认证端点 ====================

/**
 * 用户登录
 * POST /sub/auth/login
 */
router.post('/auth/login', async (req, res) => {
  try {
    const { username, password } = req.body

    if (!username || !password) {
      return res.status(400).json({ error: '请输入用户名和密码' })
    }

    const result = await subUserService.login(username, password)

    if (!result.success) {
      logger.warn(`🚫 Subscription login failed: ${username} - ${result.error}`)
      return res.status(401).json({ error: result.error })
    }

    logger.info(`✅ Subscription user logged in: ${username}`)

    res.json({
      success: true,
      token: result.token,
      user: result.user
    })
  } catch (error) {
    logger.error('❌ Login error:', error)
    res.status(500).json({ error: '登录失败' })
  }
})

/**
 * 验证会话
 * GET /sub/auth/verify
 */
router.get('/auth/verify', authenticateSubUser, async (req, res) => {
  res.json({
    success: true,
    user: req.subUser
  })
})

/**
 * 用户登出
 * POST /sub/auth/logout
 */
router.post('/auth/logout', async (req, res) => {
  try {
    const token = req.headers['authorization']?.replace('Bearer ', '') || req.headers['x-session-token']
    await subUserService.logout(token)
    res.json({ success: true })
  } catch (error) {
    res.status(500).json({ error: '登出失败' })
  }
})

/**
 * 修改密码
 * POST /sub/auth/change-password
 */
router.post('/auth/change-password', authenticateSubUser, async (req, res) => {
  try {
    const { oldPassword, newPassword } = req.body

    if (!oldPassword || !newPassword) {
      return res.status(400).json({ error: '请输入原密码和新密码' })
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ error: '新密码至少6位' })
    }

    const result = await subUserService.changePassword(req.subUser.id, oldPassword, newPassword)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    res.json({ success: true, message: '密码修改成功' })
  } catch (error) {
    logger.error('❌ Change password error:', error)
    res.status(500).json({ error: '修改密码失败' })
  }
})

/**
 * 获取管理员设置
 * GET /sub/auth/settings
 */
router.get('/auth/settings', authenticateSubAdmin, async (req, res) => {
  try {
    const user = req.subUser
    res.json({
      success: true,
      data: {
        tokenMode: user.tokenMode || 'strict'
      }
    })
  } catch (error) {
    logger.error('❌ Get settings error:', error)
    res.status(500).json({ error: '获取设置失败' })
  }
})

/**
 * 更新管理员设置
 * PUT /sub/auth/settings
 */
router.put('/auth/settings', authenticateSubAdmin, async (req, res) => {
  try {
    const { tokenMode } = req.body

    if (tokenMode && !['strict', 'loose'].includes(tokenMode)) {
      return res.status(400).json({ error: '无效的订阅链接模式' })
    }

    const updates = {}
    if (tokenMode) updates.tokenMode = tokenMode

    await subUserService.updateUser(req.subUser.id, updates)

    logger.info(`⚙️ Admin ${req.subUser.username} updated settings: tokenMode=${tokenMode}`)

    res.json({
      success: true,
      message: '设置已更新'
    })
  } catch (error) {
    logger.error('❌ Update settings error:', error)
    res.status(500).json({ error: '更新设置失败' })
  }
})

/**
 * 获取用户订阅信息
 * GET /sub/auth/subscription
 */
router.get('/auth/subscription', authenticateSubUser, async (req, res) => {
  try {
    const user = req.subUser

    // 获取节点列表
    const nodes = subscriptionService.getNodes()

    // 如果用户有关联的订阅 Token，获取订阅链接和状态
    let subscriptionUrl = null
    let tokenStatus = null
    if (user.subscriptionToken) {
      subscriptionUrl = buildPublicUrl(req, `/sub/${user.subscriptionToken}`)
      // 获取 Token 状态
      const tokenData = await subscriptionService.getToken(user.subscriptionToken)
      if (tokenData) {
        tokenStatus = {
          oneTimeUse: tokenData.oneTimeUse,
          isConsumed: tokenData.isConsumed,
          accessCount: tokenData.accessCount,
          expiresAt: tokenData.expiresAt
        }
      }
    }

    res.json({
      success: true,
      data: {
        user: {
          username: user.username,
          name: user.name,
          role: user.role
        },
        subscriptionUrl,
        tokenStatus,
        nodes: nodes.map(node => ({
          id: node.id,
          name: node.name,
          type: node.type
        }))
      }
    })
  } catch (error) {
    logger.error('❌ Get subscription error:', error)
    res.status(500).json({ error: '获取订阅信息失败' })
  }
})

/**
 * 重新生成订阅链接（用户自助）
 * POST /sub/auth/regenerate-token
 */
router.post('/auth/regenerate-token', authenticateSubUser, async (req, res) => {
  try {
    const user = req.subUser

    if (!user.subscriptionToken) {
      return res.status(400).json({ error: '没有关联的订阅链接' })
    }

    // 获取用户的 token_mode 配置（默认严格模式）
    const tokenMode = user.tokenMode || 'strict'
    const result = await subscriptionService.regenerateToken(user.subscriptionToken, tokenMode)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    // 更新用户的订阅 Token
    await subUserService.updateUser(user.id, {
      subscriptionToken: result.token
    })

    logger.info(`🔄 User regenerated subscription token: ${user.username} (mode: ${tokenMode})`)

    res.json({
      success: true,
      data: {
        subscriptionUrl: buildPublicUrl(req, result.subscribeUrl),
        token: result.token
      },
      message: '订阅链接已重新生成'
    })
  } catch (error) {
    logger.error('❌ Regenerate token error:', error)
    res.status(500).json({ error: '重新生成订阅链接失败' })
  }
})

/**
 * 获取节点详情（需登录）
 * GET /sub/auth/nodes
 */
router.get('/auth/nodes', authenticateSubUser, async (req, res) => {
  try {
    const nodes = subscriptionService.getNodes()

    // 返回完整节点信息
    const nodeDetails = subscriptionService.nodes.map(node => ({
      id: node.id,
      name: node.name,
      type: node.type,
      url: subscriptionService._generateNodeLink(node)
    }))

    res.json({
      success: true,
      data: nodeDetails
    })
  } catch (error) {
    logger.error('❌ Get nodes error:', error)
    res.status(500).json({ error: '获取节点失败' })
  }
})

/**
 * 获取用户统计信息
 * GET /sub/auth/stats
 */
router.get('/auth/stats', authenticateSubUser, async (req, res) => {
  try {
    const user = req.subUser
    const stats = await subscriptionService.getUserStats(user.id)

    // 获取订阅 Token 的访问统计
    let tokenStats = null
    if (user.subscriptionToken) {
      const tokenData = await subscriptionService.getToken(user.subscriptionToken)
      if (tokenData) {
        tokenStats = {
          accessCount: tokenData.accessCount,
          lastAccessAt: tokenData.lastAccessAt,
          lastAccessIP: tokenData.lastAccessIP,
          expiresAt: tokenData.expiresAt
        }
      }
    }

    res.json({
      success: true,
      data: {
        user: stats,
        token: tokenStats
      }
    })
  } catch (error) {
    logger.error('❌ Get stats error:', error)
    res.status(500).json({ error: '获取统计失败' })
  }
})

/**
 * 获取当前用户流量信息
 * GET /sub/auth/user-traffic
 */
router.get('/auth/user-traffic', authenticateSubUser, async (req, res) => {
  try {
    const userId = req.subUser.id
    const user = await subUserService.getUserById(userId)

    if (!user) {
      return res.status(404).json({ error: '用户不存在' })
    }

    const trafficUsed = user.trafficUsed || 0
    const trafficLimit = user.trafficLimit || 500 * 1024 * 1024 * 1024
    const remaining = Math.max(0, trafficLimit - trafficUsed)
    const usedPercent = trafficLimit > 0 ? ((trafficUsed / trafficLimit) * 100).toFixed(2) : 0

    res.json({
      success: true,
      data: {
        trafficUsed,
        trafficLimit,
        remaining,
        usedPercent: parseFloat(usedPercent),
        trafficResetAt: user.trafficResetAt,
        expiresAt: user.expiresAt
      }
    })
  } catch (error) {
    logger.error('❌ Get user traffic error:', error)
    res.status(500).json({ error: '获取流量信息失败' })
  }
})

/**
 * 获取系统概览（管理员）
 * GET /sub/auth/overview
 */
router.get('/auth/overview', authenticateSubUser, async (req, res) => {
  try {
    const systemStats = await subscriptionService.getSystemStats()

    res.json({
      success: true,
      data: systemStats
    })
  } catch (error) {
    logger.error('❌ Get overview error:', error)
    res.status(500).json({ error: '获取概览失败' })
  }
})

/**
 * 获取流量统计
 * GET /sub/auth/traffic
 */
router.get('/auth/traffic', authenticateSubUser, async (req, res) => {
  try {
    const trafficStatsService = require('../services/trafficStatsService')
    const stats = await trafficStatsService.getFormattedStats()

    res.json({
      success: true,
      data: stats
    })
  } catch (error) {
    logger.error('❌ Get traffic error:', error)
    res.status(500).json({ error: '获取流量统计失败' })
  }
})

// ==================== 订阅管理员端点（管理下级用户） ====================

/**
 * 获取管理员统计信息（下级用户数量、流量使用等）
 * GET /sub/auth/admin-stats
 */
router.get('/auth/admin-stats', authenticateSubAdmin, async (req, res) => {
  try {
    const stats = await subUserService.getSubUserStats(req.subUser.id)
    res.json({
      success: true,
      data: stats
    })
  } catch (error) {
    logger.error('❌ Failed to get admin stats:', error)
    res.status(500).json({ error: '获取统计信息失败' })
  }
})

/**
 * 获取下级用户列表（订阅管理员）
 * GET /sub/auth/sub-users
 */
router.get('/auth/sub-users', authenticateSubAdmin, async (req, res) => {
  try {
    const users = await subUserService.getSubUsers(req.subUser.id)
    const stats = await subUserService.getSubUserStats(req.subUser.id)
    res.json({
      success: true,
      data: users,
      total: users.length,
      stats: stats
    })
  } catch (error) {
    logger.error('❌ Failed to list sub users:', error)
    res.status(500).json({ error: '获取下级用户列表失败' })
  }
})

/**
 * 创建下级用户（订阅管理员）
 * POST /sub/auth/sub-users
 */
router.post('/auth/sub-users', authenticateSubAdmin, async (req, res) => {
  try {
    const { username, password, name, expiresAt, oneTimeUse = true, trafficLimit } = req.body

    if (!username || !password) {
      return res.status(400).json({ error: '用户名和密码必填' })
    }

    if (password.length < 6) {
      return res.status(400).json({ error: '密码至少6位' })
    }

    // 创建下级用户，支持自定义流量限制
    const result = await subUserService.createSubUser(req.subUser.id, username, password, {
      name,
      expiresAt,
      trafficLimit
    })

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    // 自动创建一次性订阅链接
    const tokenResult = await subscriptionService.createSubscriptionToken({
      name: `${username}的订阅`,
      expiryDays: 30,
      oneTimeUse,
      userId: result.user.id,
      createdBy: req.subUser.username
    })

    // 更新用户的订阅 Token
    await subUserService.updateUser(result.user.id, {
      subscriptionToken: tokenResult.token
    })

    result.user.subscriptionToken = tokenResult.token
    result.user.subscriptionUrl = buildPublicUrl(req, tokenResult.subscribeUrl)
    result.user.oneTimeUse = oneTimeUse

    logger.info(`📋 Sub admin ${req.subUser.username} created sub user: ${username}`)

    res.json({
      success: true,
      data: result.user,
      message: '下级用户创建成功'
    })
  } catch (error) {
    logger.error('❌ Failed to create sub user:', error)
    res.status(500).json({ error: '创建下级用户失败' })
  }
})

/**
 * 更新下级用户（订阅管理员）
 * PUT /sub/auth/sub-users/:userId
 */
router.put('/auth/sub-users/:userId', authenticateSubAdmin, async (req, res) => {
  try {
    const { userId } = req.params
    const { name, expiresAt, isActive, trafficLimit } = req.body

    // 验证是否为自己的下级用户
    const user = await subUserService.getUserById(userId)
    if (!user || user.parentId !== req.subUser.id) {
      return res.status(403).json({ error: '无权限操作此用户' })
    }

    // 验证流量限制（如果提供）
    if (trafficLimit !== undefined) {
      if (typeof trafficLimit !== 'number' || trafficLimit < 0) {
        return res.status(400).json({ error: '流量限制必须是非负数' })
      }
    }

    const result = await subUserService.updateUser(userId, {
      name,
      expiresAt,
      isActive,
      trafficLimit
    })

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    res.json({ success: true, message: '用户更新成功' })
  } catch (error) {
    logger.error('❌ Failed to update sub user:', error)
    res.status(500).json({ error: '更新用户失败' })
  }
})

/**
 * 重置下级用户密码（订阅管理员）
 * POST /sub/auth/sub-users/:userId/reset-password
 */
router.post('/auth/sub-users/:userId/reset-password', authenticateSubAdmin, async (req, res) => {
  try {
    const { userId } = req.params
    const { newPassword } = req.body

    if (!newPassword || newPassword.length < 6) {
      return res.status(400).json({ error: '新密码至少6位' })
    }

    // 验证是否为自己的下级用户
    const user = await subUserService.getUserById(userId)
    if (!user || user.parentId !== req.subUser.id) {
      return res.status(403).json({ error: '无权限操作此用户' })
    }

    const result = await subUserService.resetPassword(userId, newPassword)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    logger.info(`🔑 Sub admin ${req.subUser.username} reset password for: ${user.username}`)

    res.json({ success: true, message: '密码重置成功' })
  } catch (error) {
    logger.error('❌ Failed to reset password:', error)
    res.status(500).json({ error: '重置密码失败' })
  }
})

/**
 * 为下级用户重新生成订阅链接（订阅管理员）
 * POST /sub/auth/sub-users/:userId/regenerate-token
 */
router.post('/auth/sub-users/:userId/regenerate-token', authenticateSubAdmin, async (req, res) => {
  try {
    const { userId } = req.params

    // 验证是否为自己的下级用户
    const user = await subUserService.getUserById(userId)
    if (!user || user.parentId !== req.subUser.id) {
      return res.status(403).json({ error: '无权限操作此用户' })
    }

    if (!user.subscriptionToken) {
      return res.status(400).json({ error: '用户没有关联的订阅链接' })
    }

    // 使用管理员的 token_mode 配置
    const tokenMode = req.subUser.tokenMode || 'strict'
    const result = await subscriptionService.regenerateToken(user.subscriptionToken, tokenMode)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    // 更新用户的订阅 Token
    await subUserService.updateUser(userId, {
      subscriptionToken: result.token
    })

    logger.info(`🔄 Sub admin ${req.subUser.username} regenerated token for: ${user.username} (mode: ${tokenMode})`)

    res.json({
      success: true,
      data: {
        subscriptionUrl: buildPublicUrl(req, result.subscribeUrl),
        token: result.token
      },
      message: '订阅链接已重新生成'
    })
  } catch (error) {
    logger.error('❌ Failed to regenerate token:', error)
    res.status(500).json({ error: '重新生成订阅链接失败' })
  }
})

/**
 * 重置下级用户流量（订阅管理员）
 * POST /sub/auth/sub-users/:userId/reset-traffic
 */
router.post('/auth/sub-users/:userId/reset-traffic', authenticateSubAdmin, async (req, res) => {
  try {
    const { userId } = req.params

    // 验证是否为自己的下级用户
    const user = await subUserService.getUserById(userId)
    if (!user || user.parentId !== req.subUser.id) {
      return res.status(403).json({ error: '无权限操作此用户' })
    }

    const result = await subUserService.resetTraffic(userId)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    logger.info(`🔄 Sub admin ${req.subUser.username} reset traffic for: ${user.username}`)

    res.json({ success: true, message: '流量已重置' })
  } catch (error) {
    logger.error('❌ Failed to reset traffic:', error)
    res.status(500).json({ error: '重置流量失败' })
  }
})

/**
 * 删除下级用户（订阅管理员）
 * DELETE /sub/auth/sub-users/:userId
 */
router.delete('/auth/sub-users/:userId', authenticateSubAdmin, async (req, res) => {
  try {
    const { userId } = req.params

    // 验证是否为自己的下级用户
    const user = await subUserService.getUserById(userId)
    if (!user || user.parentId !== req.subUser.id) {
      return res.status(403).json({ error: '无权限操作此用户' })
    }

    // 删除用户关联的订阅 Token
    if (user.subscriptionToken) {
      await subscriptionService.deleteToken(user.subscriptionToken)
    }

    const result = await subUserService.deleteUser(userId)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    logger.info(`🗑️ Sub admin ${req.subUser.username} deleted sub user: ${user.username}`)

    res.json({ success: true, message: '用户删除成功' })
  } catch (error) {
    logger.error('❌ Failed to delete sub user:', error)
    res.status(500).json({ error: '删除用户失败' })
  }
})

// ==================== Hysteria2 认证端点 ====================

/**
 * Hysteria2 HTTP 认证端点
 * POST /sub/auth/hysteria
 * Hysteria2 服务器会调用此端点验证用户
 */
router.post('/auth/hysteria', async (req, res) => {
  try {
    const { addr, auth, tx } = req.body

    // auth 字段是客户端发送的密码（订阅Token）
    const password = auth || ''

    if (!password) {
      logger.warn(`Hysteria2 auth: Empty password from ${addr}`)
      return res.json({ ok: false })
    }

    // 尝试用 password 作为订阅Token查找用户
    const tokenData = await subscriptionService.getToken(password)

    if (!tokenData) {
      // 兼容旧的全局密码模式
      const globalPassword = process.env.SUB_HY2_PASSWORD || 'CHANGE_ME'
      if (password === globalPassword) {
        logger.info(`Hysteria2 auth: Global password used from ${addr}`)
        return res.json({ ok: true, id: 'default' })
      }
      logger.warn(`Hysteria2 auth: Invalid token from ${addr}`)
      return res.json({ ok: false })
    }

    // 检查Token状态
    if (tokenData.status !== 'active') {
      logger.warn(`Hysteria2 auth: Inactive token from ${addr}`)
      return res.json({ ok: false })
    }

    // 检查Token是否过期
    if (tokenData.expiresAt) {
      const expiresAt = new Date(tokenData.expiresAt)
      if (expiresAt < new Date()) {
        logger.warn(`Hysteria2 auth: Expired token from ${addr}`)
        return res.json({ ok: false })
      }
    }

    // 注意：Hysteria2 连接认证时，不检查 isConsumed 状态
    // 因为一次性订阅链接只限制订阅内容的获取次数，不影响节点连接
    // 只有在获取订阅内容时才检查 isConsumed

    // 获取关联用户
    if (!tokenData.userId) {
      logger.warn(`Hysteria2 auth: Token has no associated user from ${addr}`)
      return res.json({ ok: false })
    }

    const user = await subUserService.getUserById(tokenData.userId)
    if (!user) {
      logger.warn(`Hysteria2 auth: User not found for token from ${addr}`)
      return res.json({ ok: false })
    }

    // 检查用户状态
    if (user.isActive !== 'true') {
      logger.warn(`Hysteria2 auth: Inactive user ${user.username} from ${addr}`)
      return res.json({ ok: false })
    }

    // 检查用户流量是否用尽
    if (user.trafficUsed >= user.trafficLimit) {
      logger.warn(`Hysteria2 auth: Traffic limit exceeded for ${user.username} from ${addr}`)
      return res.json({ ok: false })
    }

    logger.info(`Hysteria2 auth: User ${user.username} (${user.id}) authenticated from ${addr}`)

    // 返回用户ID作为标识，Hysteria2 会用这个ID来统计流量
    res.json({
      ok: true,
      id: user.id
    })
  } catch (error) {
    logger.error('Hysteria2 auth error:', error)
    res.json({ ok: false })
  }
})

// ==================== 订阅内容端点 ====================

/**
 * 订阅内容获取 - 通过 Token 访问
 * GET /sub/:token
 */
router.get('/:token', async (req, res) => {
  try {
    const { token } = req.params

    // 排除 auth 和 admin 路径
    if (token === 'auth' || token === 'admin') {
      return res.status(404).json({ error: 'Not found' })
    }

    const clientIP = getClientIP(req)
    const userAgent = req.headers['user-agent']

    // 验证 token 格式
    if (!token || token.length < 32) {
      logger.warn(`🚫 Invalid subscription token format from IP: ${clientIP}`)
      return res.status(400).json({ error: 'Invalid token format' })
    }

    // 先验证 token 获取用户ID，然后获取流量信息
    const tokenData = await subscriptionService.getToken(token)

    // 获取用户流量信息（如果有关联用户）
    let trafficUsed = 0
    let trafficLimit = 500 * 1024 * 1024 * 1024 // 默认500GB
    let expireTime = Date.now() + 30 * 24 * 60 * 60 * 1000

    if (tokenData && tokenData.userId) {
      const user = await subUserService.getUserById(tokenData.userId)
      if (user) {
        trafficUsed = user.trafficUsed || 0
        trafficLimit = user.trafficLimit || trafficLimit
        if (user.expiresAt) {
          expireTime = new Date(user.expiresAt).getTime()
        }
      }
    }

    // 构建流量信息对象，传递给订阅生成
    const trafficInfo = {
      used: trafficUsed,
      limit: trafficLimit,
      expiresAt: new Date(expireTime)
    }

    const result = await subscriptionService.generateSubscription(token, clientIP, userAgent, trafficInfo)

    if (!result.success) {
      logger.warn(`🚫 Subscription access denied: ${result.error}, IP: ${clientIP}`)
      return res.status(403).json({ error: result.error })
    }

    // 设置响应头
    res.setHeader('Content-Type', 'text/plain; charset=utf-8')
    res.setHeader('Content-Disposition', 'attachment; filename="subscription.txt"')
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate')
    // 标准机场订阅格式：upload=上传流量; download=下载流量; total=总流量; expire=过期时间戳(秒)
    res.setHeader('Subscription-Userinfo', `upload=0; download=${trafficUsed}; total=${trafficLimit}; expire=${Math.floor(expireTime / 1000)}`)

    logger.info(`✅ Subscription accessed: token=${token.substring(0, 8)}..., IP=${clientIP}, nodes=${result.nodeCount}`)

    res.send(result.content)
  } catch (error) {
    logger.error('❌ Subscription error:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

// ==================== 管理端点 ====================

/**
 * 获取所有订阅用户列表
 * GET /sub/admin/users
 */
router.get('/admin/users', authenticateAdminApiKey, async (req, res) => {
  try {
    const users = await subUserService.listUsers()
    res.json({
      success: true,
      data: users,
      total: users.length
    })
  } catch (error) {
    logger.error('❌ Failed to list subscription users:', error)
    res.status(500).json({ error: 'Failed to list users' })
  }
})

/**
 * 创建订阅用户
 * POST /sub/admin/users
 */
router.post('/admin/users', authenticateAdminApiKey, async (req, res) => {
  try {
    const { username, password, name, role, subscriptionToken, expiresAt, isActive = true, oneTimeUse = false } = req.body

    if (!username || !password) {
      return res.status(400).json({ error: '用户名和密码必填' })
    }

    if (password.length < 6) {
      return res.status(400).json({ error: '密码至少6位' })
    }

    // 创建用户
    const result = await subUserService.createUser(username, password, {
      name,
      role: role || 'user',
      subscriptionToken,
      expiresAt,
      isActive
    })

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    // 如果没有提供订阅 Token，自动创建一个
    if (!subscriptionToken) {
      const tokenResult = await subscriptionService.createSubscriptionToken({
        name: `${username}的订阅`,
        expiryDays: 30,
        oneTimeUse,
        userId: result.user.id,
        createdBy: req.admin?.username || 'admin'
      })

      // 更新用户的订阅 Token
      await subUserService.updateUser(result.user.id, {
        subscriptionToken: tokenResult.token
      })

      result.user.subscriptionToken = tokenResult.token
      result.user.subscriptionUrl = buildPublicUrl(req, tokenResult.subscribeUrl)
    }

    res.json({
      success: true,
      data: result.user,
      message: '用户创建成功'
    })
  } catch (error) {
    logger.error('❌ Failed to create subscription user:', error)
    res.status(500).json({ error: 'Failed to create user' })
  }
})

/**
 * 更新订阅用户
 * PUT /sub/admin/users/:userId
 */
router.put('/admin/users/:userId', authenticateAdminApiKey, async (req, res) => {
  try {
    const { userId } = req.params
    const { name, role, subscriptionToken, expiresAt, isActive } = req.body

    const result = await subUserService.updateUser(userId, {
      name,
      role,
      subscriptionToken,
      expiresAt,
      isActive
    })

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    res.json({ success: true, message: '用户更新成功' })
  } catch (error) {
    logger.error('❌ Failed to update subscription user:', error)
    res.status(500).json({ error: 'Failed to update user' })
  }
})

/**
 * 设置用户角色
 * PUT /sub/admin/users/:userId/role
 */
router.put('/admin/users/:userId/role', authenticateAdminApiKey, async (req, res) => {
  try {
    const { userId } = req.params
    const { role } = req.body

    if (!role || !['admin', 'user'].includes(role)) {
      return res.status(400).json({ error: '无效的角色，只能是 admin 或 user' })
    }

    const result = await subUserService.setUserRole(userId, role)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    res.json({ success: true, message: `用户角色已设置为 ${role}` })
  } catch (error) {
    logger.error('❌ Failed to set user role:', error)
    res.status(500).json({ error: 'Failed to set user role' })
  }
})

/**
 * 管理员为用户重新生成订阅链接
 * POST /sub/admin/users/:userId/regenerate-token
 */
router.post('/admin/users/:userId/regenerate-token', authenticateAdminApiKey, async (req, res) => {
  try {
    const { userId } = req.params
    const { tokenMode = 'strict' } = req.body

    const user = await subUserService.getUserById(userId)
    if (!user) {
      return res.status(404).json({ error: '用户不存在' })
    }

    if (!user.subscriptionToken) {
      return res.status(400).json({ error: '用户没有关联的订阅链接' })
    }

    const result = await subscriptionService.regenerateToken(user.subscriptionToken, tokenMode)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    // 更新用户的订阅 Token
    await subUserService.updateUser(userId, {
      subscriptionToken: result.token
    })

    logger.info(`🔄 Admin regenerated token for user: ${user.username} (mode: ${tokenMode})`)

    res.json({
      success: true,
      data: {
        subscriptionUrl: buildPublicUrl(req, result.subscribeUrl),
        token: result.token
      },
      message: '订阅链接已重新生成'
    })
  } catch (error) {
    logger.error('❌ Failed to regenerate token:', error)
    res.status(500).json({ error: 'Failed to regenerate token' })
  }
})

/**
 * 重置用户密码
 * POST /sub/admin/users/:userId/reset-password
 */
router.post('/admin/users/:userId/reset-password', authenticateAdminApiKey, async (req, res) => {
  try {
    const { userId } = req.params
    const { newPassword } = req.body

    if (!newPassword || newPassword.length < 6) {
      return res.status(400).json({ error: '新密码至少6位' })
    }

    const result = await subUserService.resetPassword(userId, newPassword)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    res.json({ success: true, message: '密码重置成功' })
  } catch (error) {
    logger.error('❌ Failed to reset password:', error)
    res.status(500).json({ error: 'Failed to reset password' })
  }
})

/**
 * 删除订阅用户
 * DELETE /sub/admin/users/:userId
 */
router.delete('/admin/users/:userId', authenticateAdminApiKey, async (req, res) => {
  try {
    const { userId } = req.params
    const result = await subUserService.deleteUser(userId)

    if (!result.success) {
      return res.status(400).json({ error: result.error })
    }

    res.json({ success: true, message: '用户删除成功' })
  } catch (error) {
    logger.error('❌ Failed to delete subscription user:', error)
    res.status(500).json({ error: 'Failed to delete user' })
  }
})

/**
 * 获取所有订阅 Token 列表
 * GET /sub/admin/tokens
 */
router.get('/admin/tokens', authenticateAdminApiKey, async (req, res) => {
  try {
    const tokens = await subscriptionService.listTokens()
    res.json({
      success: true,
      data: tokens,
      total: tokens.length
    })
  } catch (error) {
    logger.error('❌ Failed to list subscription tokens:', error)
    res.status(500).json({ error: 'Failed to list tokens' })
  }
})

/**
 * 创建新的订阅 Token
 * POST /sub/admin/tokens
 */
router.post('/admin/tokens', authenticateAdminApiKey, async (req, res) => {
  try {
    const {
      name,
      expiryDays = 30,
      maxAccess = 0,
      allowedIPs = [],
      enabledNodes = [],
      oneTimeUse = false,
      userId = null
    } = req.body

    const result = await subscriptionService.createSubscriptionToken({
      name,
      expiryDays,
      maxAccess,
      allowedIPs,
      enabledNodes,
      oneTimeUse,
      userId,
      createdBy: req.admin?.username || 'admin'
    })

    res.json({
      success: true,
      data: result,
      message: '订阅 Token 创建成功'
    })
  } catch (error) {
    logger.error('❌ Failed to create subscription token:', error)
    res.status(500).json({ error: 'Failed to create token' })
  }
})

/**
 * 删除 Token
 * DELETE /sub/admin/tokens/:token
 */
router.delete('/admin/tokens/:token', authenticateAdminApiKey, async (req, res) => {
  try {
    const { token } = req.params
    const result = await subscriptionService.deleteToken(token)

    if (!result.success) {
      return res.status(404).json({ error: result.error })
    }

    res.json({
      success: true,
      message: 'Token 已删除'
    })
  } catch (error) {
    logger.error('❌ Failed to delete subscription token:', error)
    res.status(500).json({ error: 'Failed to delete token' })
  }
})

/**
 * 获取节点列表
 * GET /sub/admin/nodes
 */
router.get('/admin/nodes', authenticateAdminApiKey, async (req, res) => {
  try {
    const nodes = subscriptionService.getNodes()
    res.json({
      success: true,
      data: nodes
    })
  } catch (error) {
    logger.error('❌ Failed to get nodes:', error)
    res.status(500).json({ error: 'Failed to get nodes' })
  }
})

module.exports = router
