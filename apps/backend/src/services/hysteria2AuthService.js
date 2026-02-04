/**
 * Hysteria2 HTTP 认证服务
 * 为 Hysteria2 提供用户认证，支持按用户统计流量
 */

const express = require('express')
const subscriptionMysql = require('../models/subscriptionMysql')
const logger = require('../utils/logger')

// 认证服务配置
const AUTH_PORT = parseInt(process.env.HY2_AUTH_PORT) || 9998
const AUTH_HOST = process.env.HY2_AUTH_HOST || '0.0.0.0'  // 默认监听所有接口，以便宿主机访问
const AUTH_SECRET = process.env.HY2_AUTH_SECRET || 'CHANGE_ME'

class Hysteria2AuthService {
  constructor() {
    this.app = null
    this.server = null
    this.isRunning = false
  }

  /**
   * 启动认证服务
   */
  async start() {
    if (this.isRunning) {
      logger.warn('Hysteria2 auth service is already running')
      return
    }

    this.app = express()
    this.app.use(express.json())

    // 认证端点 - Hysteria2 会调用这个接口验证用户
    this.app.post('/auth', async (req, res) => {
      try {
        const { addr, auth, tx } = req.body

        // auth 字段是客户端发送的密码
        // 格式: userId:password 或者直接是 password（兼容旧格式）
        const authStr = auth || ''

        // 尝试解析 userId:password 格式
        let userId = null
        let password = authStr

        if (authStr.includes(':')) {
          const parts = authStr.split(':')
          userId = parts[0]
          password = parts.slice(1).join(':')
        }

        // 验证用户
        const result = await this.validateUser(userId, password)

        if (result.valid) {
          logger.info(`Hysteria2 auth: User ${result.userId} authenticated from ${addr}`)
          // 返回用户ID作为标识，Hysteria2 会用这个ID来统计流量
          res.json({
            ok: true,
            id: result.userId
          })
        } else {
          logger.warn(`Hysteria2 auth: Failed for ${authStr.substring(0, 8)}... from ${addr}`)
          res.json({ ok: false })
        }
      } catch (error) {
        logger.error('Hysteria2 auth error:', error)
        res.json({ ok: false })
      }
    })

    // 健康检查
    this.app.get('/health', (req, res) => {
      res.json({ status: 'ok', service: 'hysteria2-auth' })
    })

    return new Promise((resolve, reject) => {
      this.server = this.app.listen(AUTH_PORT, AUTH_HOST, () => {
        this.isRunning = true
        logger.info(`✅ Hysteria2 auth service started on ${AUTH_HOST}:${AUTH_PORT}`)
        resolve()
      })

      this.server.on('error', (error) => {
        logger.error('Hysteria2 auth service error:', error)
        reject(error)
      })
    })
  }

  /**
   * 验证用户
   * 支持多种认证方式：
   * 1. userId:password - 用户ID和密码
   * 2. subscriptionToken - 订阅Token
   * 3. password - 全局密码（兼容旧配置）
   */
  async validateUser(userId, password) {
    try {
      await subscriptionMysql.connect()

      // 1. 如果提供了 userId，验证用户密码
      if (userId) {
        const user = await subscriptionMysql.getUserById(userId)
        if (user && user.isActive === 'true') {
          // 这里简化处理，实际应该验证密码
          // 但为了兼容性，我们允许使用订阅Token作为密码
          if (user.subscriptionToken === password) {
            return { valid: true, userId: user.id }
          }
        }
      }

      // 2. 尝试用 password 作为 subscription_token 直接查找用户
      const userByToken = await subscriptionMysql.getUserBySubscriptionToken(password)
      if (userByToken && userByToken.isActive === 'true') {
        // 检查用户是否过期
        if (userByToken.expiresAt) {
          const expiresAt = new Date(userByToken.expiresAt)
          if (expiresAt < new Date()) {
            return { valid: false, error: 'User expired' }
          }
        }
        // 检查用户流量是否用尽
        if (userByToken.trafficUsed >= userByToken.trafficLimit) {
          return { valid: false, error: 'Traffic limit exceeded' }
        }
        return { valid: true, userId: userByToken.id }
      }

      // 3. 尝试用 password 作为订阅Token查找用户（sub_tokens表）
      const tokenData = await subscriptionMysql.getToken(password)
      if (tokenData && tokenData.status === 'active') {
        // 检查Token是否过期
        if (tokenData.expiresAt) {
          const expiresAt = new Date(tokenData.expiresAt)
          if (expiresAt < new Date()) {
            return { valid: false, error: 'Token expired' }
          }
        }

        // 注意：不检查一次性Token是否已消费
        // oneTimeUse 是针对订阅链接访问的限制（防止分享链接）
        // 对于代理认证，已消费的Token仍应有效（用户已获得代理配置）

        // 如果有关联用户，验证用户状态和流量
        if (tokenData.userId) {
          const user = await subscriptionMysql.getUserById(tokenData.userId)
          if (user && user.isActive === 'true') {
            // 检查用户流量是否用尽
            if (user.trafficUsed >= user.trafficLimit) {
              return { valid: false, error: 'Traffic limit exceeded' }
            }
            return { valid: true, userId: user.id }
          }
        } else {
          // 无关联用户的 token，使用 token id 作为用户标识
          // 这样可以在流量统计中追踪这个 token 的使用情况
          logger.warn(`Hysteria2 auth: Token ${password.substring(0, 8)}... has no associated user, using token id`)
          return { valid: true, userId: `token_${tokenData.id}` }
        }
      }

      // 3. 兼容旧的全局密码模式
      const globalPassword = process.env.SUB_HY2_PASSWORD || 'CHANGE_ME'
      if (password === globalPassword) {
        // 使用默认用户ID
        return { valid: true, userId: 'default' }
      }

      return { valid: false, error: 'Invalid credentials' }
    } catch (error) {
      logger.error('Hysteria2 validateUser error:', error)
      return { valid: false, error: error.message }
    }
  }

  /**
   * 停止认证服务
   */
  async stop() {
    if (this.server) {
      return new Promise((resolve) => {
        this.server.close(() => {
          this.isRunning = false
          logger.info('Hysteria2 auth service stopped')
          resolve()
        })
      })
    }
  }
}

module.exports = new Hysteria2AuthService()
