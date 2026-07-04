/**
 * 机场面板专用 MySQL 模型
 * 用于存储订阅用户和订阅 Token 数据
 */

const mysql = require('mysql2/promise')
const logger = require('../utils/logger')

// 默认配置
const DEFAULT_CONFIG = {
  host: process.env.SUB_MYSQL_HOST || process.env.MYSQL_HOST || '127.0.0.1',
  port: parseInt(process.env.SUB_MYSQL_PORT || process.env.MYSQL_PORT) || 3306,
  user: process.env.SUB_MYSQL_USER || process.env.MYSQL_USER || 'subscription',
  password: process.env.SUB_MYSQL_PASSWORD || process.env.MYSQL_PASSWORD || '',
  database: process.env.SUB_MYSQL_DATABASE || process.env.MYSQL_DATABASE || 'subscription',
  connectionLimit: 5
}

class SubscriptionMySQLClient {
  constructor() {
    this.pool = null
    this.isConnected = false
  }

  async connect() {
    if (this.isConnected) return this.pool

    try {
      this.pool = mysql.createPool({
        ...DEFAULT_CONFIG,
        waitForConnections: true,
        queueLimit: 0,
        enableKeepAlive: true,
        keepAliveInitialDelay: 0
      })

      // 测试连接
      const connection = await this.pool.getConnection()
      await connection.ping()
      connection.release()

      this.isConnected = true
      logger.info('🔗 Subscription MySQL connected successfully')

      // 初始化数据库表
      await this.initTables()

      return this.pool
    } catch (error) {
      logger.error('💥 Failed to connect to Subscription MySQL:', error)
      throw error
    }
  }

  async disconnect() {
    if (this.pool) {
      await this.pool.end()
      this.isConnected = false
      logger.info('👋 Subscription MySQL disconnected')
    }
  }

  getPool() {
    return this.pool
  }

  // 初始化数据库表
  async initTables() {
    if (!this.pool) return

    // 订阅用户表
    await this.pool.execute(`
      CREATE TABLE IF NOT EXISTS sub_users (
        id VARCHAR(64) PRIMARY KEY,
        username VARCHAR(255) NOT NULL UNIQUE,
        password_hash VARCHAR(255) NOT NULL,
        name VARCHAR(255),
        role VARCHAR(20) DEFAULT 'user',
        parent_id VARCHAR(64) DEFAULT NULL,
        subscription_token VARCHAR(255),
        expires_at DATETIME,
        is_active BOOLEAN DEFAULT TRUE,
        last_login_at DATETIME,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_username (username),
        INDEX idx_is_active (is_active),
        INDEX idx_subscription_token (subscription_token),
        INDEX idx_role (role),
        INDEX idx_parent_id (parent_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `)

    // 添加新字段（如果表已存在）
    await this._addColumnIfNotExists('sub_users', 'role', "VARCHAR(20) DEFAULT 'user'")
    await this._addColumnIfNotExists('sub_users', 'parent_id', 'VARCHAR(64) DEFAULT NULL')
    // 流量限制相关字段
    await this._addColumnIfNotExists('sub_users', 'traffic_limit', 'BIGINT DEFAULT 536870912000') // 默认500GB
    await this._addColumnIfNotExists('sub_users', 'traffic_used', 'BIGINT DEFAULT 0')
    await this._addColumnIfNotExists('sub_users', 'traffic_reset_at', 'DATETIME DEFAULT NULL')
    // 管理员配置：订阅链接模式 strict=严格模式（新链接生成后旧链接失效），loose=宽松模式（多链接并存）
    await this._addColumnIfNotExists('sub_users', 'token_mode', "VARCHAR(20) DEFAULT 'strict'")

    // 订阅 Token 表
    await this.pool.execute(`
      CREATE TABLE IF NOT EXISTS sub_tokens (
        id VARCHAR(64) PRIMARY KEY,
        token VARCHAR(255) NOT NULL UNIQUE,
        name VARCHAR(255),
        status VARCHAR(50) DEFAULT 'active',
        expires_at DATETIME,
        max_access INT DEFAULT 0,
        access_count INT DEFAULT 0,
        one_time_use BOOLEAN DEFAULT FALSE,
        is_consumed BOOLEAN DEFAULT FALSE,
        allowed_ips JSON,
        enabled_nodes JSON,
        created_by VARCHAR(255),
        user_id VARCHAR(64) DEFAULT NULL,
        last_access_at DATETIME,
        last_access_ip VARCHAR(100),
        last_user_agent TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_token (token),
        INDEX idx_status (status),
        INDEX idx_expires_at (expires_at),
        INDEX idx_user_id (user_id),
        INDEX idx_one_time_use (one_time_use)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `)

    // 添加新字段（如果表已存在）
    await this._addColumnIfNotExists('sub_tokens', 'one_time_use', 'BOOLEAN DEFAULT FALSE')
    await this._addColumnIfNotExists('sub_tokens', 'is_consumed', 'BOOLEAN DEFAULT FALSE')
    await this._addColumnIfNotExists('sub_tokens', 'user_id', 'VARCHAR(64) DEFAULT NULL')
    await this._addColumnIfNotExists('sub_tokens', 'vless_uuid', 'VARCHAR(36) DEFAULT NULL')
    await this.normalizeCurrentUserTokens()

    // 用户统计表
    await this.pool.execute(`
      CREATE TABLE IF NOT EXISTS sub_user_stats (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id VARCHAR(64) NOT NULL,
        date DATE NOT NULL,
        access_count INT DEFAULT 0,
        download_bytes BIGINT DEFAULT 0,
        upload_bytes BIGINT DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uk_user_date (user_id, date),
        INDEX idx_user_id (user_id),
        INDEX idx_date (date)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `)

    logger.info('✅ Subscription MySQL tables initialized')
  }

  // ==================== 用户相关操作 ====================

  async createUser(userData) {
    const {
      id,
      username,
      passwordHash,
      name,
      role,
      parentId,
      subscriptionToken,
      expiresAt,
      isActive,
      trafficLimit = 536870912000, // 默认500GB
      trafficUsed = 0
    } = userData

    const sql = `
      INSERT INTO sub_users (id, username, password_hash, name, role, parent_id, subscription_token, expires_at, is_active, traffic_limit, traffic_used, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    `
    await this.pool.execute(sql, [
      id,
      username,
      passwordHash,
      name || username,
      role || 'user',
      parentId || null,
      subscriptionToken || null,
      expiresAt || null,
      isActive !== false,
      trafficLimit,
      trafficUsed
    ])

    return { id, username, name, role, trafficLimit, trafficUsed }
  }

  async getUserById(userId) {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_users WHERE id = ?',
      [userId]
    )
    return rows[0] ? this._formatUser(rows[0]) : null
  }

  async getUserBySubscriptionToken(token) {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_users WHERE subscription_token = ?',
      [token]
    )
    return rows[0] ? this._formatUser(rows[0]) : null
  }

  async getUserByUsername(username) {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_users WHERE username = ?',
      [username]
    )
    return rows[0] ? this._formatUser(rows[0]) : null
  }

  async updateUser(userId, updates) {
    const allowedFields = ['name', 'role', 'parent_id', 'subscription_token', 'expires_at', 'is_active', 'last_login_at', 'password_hash', 'traffic_limit', 'traffic_used', 'traffic_reset_at', 'token_mode']
    const setClauses = []
    const values = []

    for (const [key, value] of Object.entries(updates)) {
      const snakeKey = this._camelToSnake(key)
      if (allowedFields.includes(snakeKey)) {
        setClauses.push(`${snakeKey} = ?`)
        values.push(value)
      }
    }

    if (setClauses.length === 0) return

    values.push(userId)
    const sql = `UPDATE sub_users SET ${setClauses.join(', ')} WHERE id = ?`
    await this.pool.execute(sql, values)
  }

  // 获取用户的下级用户列表
  async getSubUsers(parentId) {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_users WHERE parent_id = ? ORDER BY created_at DESC',
      [parentId]
    )
    return rows.map(row => this._formatUser(row))
  }

  async deleteUser(userId) {
    await this.pool.execute('DELETE FROM sub_users WHERE id = ?', [userId])
  }

  async listUsers() {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_users ORDER BY created_at DESC'
    )
    return rows.map(row => this._formatUser(row))
  }

  // ==================== Token 相关操作 ====================

  async createToken(tokenData) {
    const {
      id,
      token,
      name,
      expiresAt,
      maxAccess,
      oneTimeUse,
      userId,
      allowedIPs,
      enabledNodes,
      createdBy,
      vlessUuid
    } = tokenData

    const sql = `
      INSERT INTO sub_tokens (id, token, name, expires_at, max_access, one_time_use, user_id, allowed_ips, enabled_nodes, created_by, vless_uuid, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    `
    await this.pool.execute(sql, [
      id,
      token,
      name,
      expiresAt,
      maxAccess || 0,
      oneTimeUse || false,
      userId || null,
      JSON.stringify(allowedIPs || []),
      JSON.stringify(enabledNodes || []),
      createdBy || 'admin',
      vlessUuid || null
    ])

    return { id, token, name, oneTimeUse, vlessUuid }
  }

  // 获取用户关联的 Token
  async getTokenByUserId(userId) {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_tokens WHERE user_id = ? ORDER BY created_at DESC LIMIT 1',
      [userId]
    )
    return rows[0] ? this._formatToken(rows[0]) : null
  }

  // 标记 Token 为已消费
  async markTokenConsumed(token) {
    const sql = `UPDATE sub_tokens SET is_consumed = TRUE WHERE token = ?`
    await this.pool.execute(sql, [token])
  }

  // 使用户的所有旧 token 失效（严格模式）
  async invalidateUserTokens(userId) {
    const sql = `UPDATE sub_tokens SET status = 'revoked' WHERE user_id = ? AND status = 'active'`
    await this.pool.execute(sql, [userId])
  }

  // 重置 Token（根据 strictMode 参数决定模式）
  // strictMode=true: 严格模式，生成新 Token 后旧 Token 立即失效
  // strictMode=false: 宽松模式，新旧 Token 并存
  async regenerateToken(oldToken, newToken, strictMode = true, vlessUuid = null) {
    // 获取旧 token 的信息
    const oldTokenData = await this.getToken(oldToken)
    if (!oldTokenData) {
      return false
    }

    // 严格模式：先使该用户的所有旧 token 失效
    if (strictMode) {
      if (oldTokenData.userId) {
        await this.invalidateUserTokens(oldTokenData.userId)
      } else {
        // 如果没有 userId，只使当前 token 失效
        await this.pool.execute(
          `UPDATE sub_tokens SET status = 'revoked' WHERE token = ?`,
          [oldToken]
        )
      }
    }

    // 创建新 token 记录
    const newTokenId = newToken.substring(0, 8)

    // 重新计算过期时间：从当前时间开始 30 天
    const newExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    const expiresAt = newExpiresAt.toISOString().slice(0, 19).replace('T', ' ')

    // 如果旧 token 没有关联用户，自动关联到 admin 用户
    const DEFAULT_ADMIN_USER_ID = '2165a7372f9f56e0'
    const userId = oldTokenData.userId || DEFAULT_ADMIN_USER_ID
    const oneTimeUse = oldTokenData.userId ? false : oldTokenData.oneTimeUse || false

    const sql = `
      INSERT INTO sub_tokens (id, token, name, status, expires_at, max_access, one_time_use, user_id, allowed_ips, enabled_nodes, created_by, vless_uuid, created_at)
      VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    `
    await this.pool.execute(sql, [
      newTokenId,
      newToken,
      oldTokenData.name || '订阅链接',
      expiresAt,
      oldTokenData.maxAccess || 0,
      oneTimeUse,
      userId,
      JSON.stringify(oldTokenData.allowedIPs || []),
      JSON.stringify(oldTokenData.enabledNodes || []),
      oldTokenData.createdBy || 'admin',
      vlessUuid || null
    ])

    return true
  }

  // 获取用户的所有有效 token
  async getTokensByUserId(userId) {
    const [rows] = await this.pool.execute(
      "SELECT * FROM sub_tokens WHERE user_id = ? AND status = 'active' ORDER BY created_at DESC",
      [userId]
    )
    return rows.map(row => this._formatToken(row))
  }

  async getToken(token) {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_tokens WHERE token = ?',
      [token]
    )
    return rows[0] ? this._formatToken(rows[0]) : null
  }

  async getTokenById(id) {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_tokens WHERE id = ?',
      [id]
    )
    return rows[0] ? this._formatToken(rows[0]) : null
  }

  async updateToken(token, updates) {
    const allowedFields = ['name', 'status', 'expires_at', 'max_access', 'access_count', 'allowed_ips', 'enabled_nodes', 'last_access_at', 'last_access_ip', 'last_user_agent']
    const setClauses = []
    const values = []

    for (const [key, value] of Object.entries(updates)) {
      const snakeKey = this._camelToSnake(key)
      if (allowedFields.includes(snakeKey)) {
        setClauses.push(`${snakeKey} = ?`)
        if (snakeKey === 'allowed_ips' || snakeKey === 'enabled_nodes') {
          values.push(JSON.stringify(value))
        } else {
          values.push(value)
        }
      }
    }

    if (setClauses.length === 0) return

    values.push(token)
    const sql = `UPDATE sub_tokens SET ${setClauses.join(', ')} WHERE token = ?`
    await this.pool.execute(sql, values)
  }

  async incrementTokenAccess(token, clientIP, userAgent) {
    const sql = `
      UPDATE sub_tokens
      SET access_count = access_count + 1,
          last_access_at = NOW(),
          last_access_ip = ?,
          last_user_agent = ?
      WHERE token = ?
    `
    await this.pool.execute(sql, [clientIP, userAgent, token])
  }

  async deleteToken(token) {
    const [result] = await this.pool.execute(
      'DELETE FROM sub_tokens WHERE token = ?',
      [token]
    )
    return result.affectedRows > 0
  }

  async listTokens() {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_tokens ORDER BY created_at DESC'
    )
    return rows.map(row => this._formatToken(row))
  }

  // 为没有 vless_uuid 的 active token 补充 UUID
  async backfillVlessUuids() {
    const crypto = require('crypto')
    const [rows] = await this.pool.execute(
      "SELECT id FROM sub_tokens WHERE status = 'active' AND vless_uuid IS NULL"
    )
    for (const row of rows) {
      const uuid = crypto.randomUUID()
      await this.pool.execute(
        'UPDATE sub_tokens SET vless_uuid = ? WHERE id = ?',
        [uuid, row.id]
      )
    }
    return rows.length
  }

  // 获取所有有 UUID 的 active token
  async getActiveTokensWithUuid() {
    const [rows] = await this.pool.execute(
      "SELECT * FROM sub_tokens WHERE status = 'active' AND vless_uuid IS NOT NULL"
    )
    return rows.map(row => this._formatToken(row))
  }

  // 当前绑定到用户账号的订阅链接需要支持客户端重复刷新。
  async normalizeCurrentUserTokens() {
    const [result] = await this.pool.execute(`
      UPDATE sub_tokens t
      JOIN sub_users u ON u.subscription_token = t.token
      SET t.one_time_use = FALSE, t.is_consumed = FALSE
      WHERE t.status = 'active'
        AND (t.one_time_use = TRUE OR t.is_consumed = TRUE)
    `)

    if (result.affectedRows > 0) {
      logger.info(`🔧 Normalized ${result.affectedRows} current user subscription tokens to reusable mode`)
    }
  }

  // 按状态查询用户的 token
  async getTokensByUserIdAndStatus(userId, status) {
    const [rows] = await this.pool.execute(
      'SELECT * FROM sub_tokens WHERE user_id = ? AND status = ?',
      [userId, status]
    )
    return rows.map(row => this._formatToken(row))
  }

  // ==================== 流量相关操作 ====================

  // 更新用户流量使用量
  async updateTrafficUsed(userId, bytesUsed) {
    const sql = `UPDATE sub_users SET traffic_used = traffic_used + ? WHERE id = ?`
    await this.pool.execute(sql, [bytesUsed, userId])
  }

  // 重置用户流量
  async resetTraffic(userId) {
    const sql = `UPDATE sub_users SET traffic_used = 0, traffic_reset_at = NOW() WHERE id = ?`
    await this.pool.execute(sql, [userId])
  }

  // 获取管理员的下级用户数量
  async getSubUserCount(parentId) {
    const [rows] = await this.pool.execute(
      'SELECT COUNT(*) as count FROM sub_users WHERE parent_id = ?',
      [parentId]
    )
    return parseInt(rows[0]?.count) || 0
  }

  // 获取管理员所有下级用户的总流量使用
  async getSubUsersTotalTraffic(parentId) {
    const [rows] = await this.pool.execute(
      'SELECT SUM(traffic_used) as total_used, SUM(traffic_limit) as total_limit FROM sub_users WHERE parent_id = ?',
      [parentId]
    )
    return {
      totalUsed: parseInt(rows[0]?.total_used) || 0,
      totalLimit: parseInt(rows[0]?.total_limit) || 0
    }
  }

  // ==================== 统计相关操作 ====================

  async recordUserStats(userId, stats = {}) {
    const { downloadBytes = 0, uploadBytes = 0 } = stats
    const today = new Date().toISOString().split('T')[0]

    const sql = `
      INSERT INTO sub_user_stats (user_id, date, access_count, download_bytes, upload_bytes)
      VALUES (?, ?, 1, ?, ?)
      ON DUPLICATE KEY UPDATE
        access_count = access_count + 1,
        download_bytes = download_bytes + VALUES(download_bytes),
        upload_bytes = upload_bytes + VALUES(upload_bytes)
    `
    await this.pool.execute(sql, [userId, today, downloadBytes, uploadBytes])
  }

  async getUserStats(userId) {
    const today = new Date().toISOString().split('T')[0]

    // 获取总统计
    const [totalRows] = await this.pool.execute(`
      SELECT
        SUM(access_count) as access_count,
        SUM(download_bytes) as download_bytes,
        SUM(upload_bytes) as upload_bytes,
        MAX(updated_at) as last_access_at
      FROM sub_user_stats WHERE user_id = ?
    `, [userId])

    // 获取今日统计
    const [todayRows] = await this.pool.execute(`
      SELECT access_count, download_bytes, upload_bytes
      FROM sub_user_stats WHERE user_id = ? AND date = ?
    `, [userId, today])

    const total = totalRows[0] || {}
    const todayData = todayRows[0] || {}

    return {
      total: {
        accessCount: parseInt(total.access_count) || 0,
        downloadBytes: parseInt(total.download_bytes) || 0,
        uploadBytes: parseInt(total.upload_bytes) || 0,
        lastAccessAt: total.last_access_at || null
      },
      today: {
        accessCount: parseInt(todayData.access_count) || 0,
        downloadBytes: parseInt(todayData.download_bytes) || 0,
        uploadBytes: parseInt(todayData.upload_bytes) || 0
      }
    }
  }

  async getSystemStats() {
    // 获取 Token 统计
    const [tokenStats] = await this.pool.execute(`
      SELECT
        COUNT(*) as total,
        SUM(CASE WHEN status = 'active' AND (expires_at IS NULL OR expires_at > NOW()) THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN status != 'active' OR (expires_at IS NOT NULL AND expires_at <= NOW()) THEN 1 ELSE 0 END) as expired,
        SUM(access_count) as total_access
      FROM sub_tokens
    `)

    // 获取用户数量
    const [userStats] = await this.pool.execute(`
      SELECT COUNT(*) as count FROM sub_users
    `)

    const stats = tokenStats[0] || {}
    return {
      totalAccess: parseInt(stats.total_access) || 0,
      activeTokens: parseInt(stats.active) || 0,
      expiredTokens: parseInt(stats.expired) || 0,
      userCount: parseInt(userStats[0]?.count) || 0
    }
  }

  // ==================== 工具方法 ====================

  // 检查并添加列（如果不存在）
  async _addColumnIfNotExists(table, column, definition) {
    try {
      const [rows] = await this.pool.execute(`
        SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
      `, [table, column])

      if (rows.length === 0) {
        await this.pool.execute(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`)
        logger.info(`✅ Added column ${column} to ${table}`)
      }
    } catch (error) {
      // 忽略错误，可能是列已存在
      logger.debug(`Column ${column} check for ${table}: ${error.message}`)
    }
  }

  _camelToSnake(str) {
    return str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`)
  }

  _snakeToCamel(str) {
    return str.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase())
  }

  _formatUser(row) {
    if (!row) return null
    return {
      id: row.id,
      username: row.username,
      name: row.name,
      passwordHash: row.password_hash,
      role: row.role || 'user',
      parentId: row.parent_id || null,
      subscriptionToken: row.subscription_token || '',
      expiresAt: row.expires_at ? row.expires_at.toISOString() : '',
      isActive: row.is_active ? 'true' : 'false',
      lastLoginAt: row.last_login_at ? row.last_login_at.toISOString() : '',
      createdAt: row.created_at ? row.created_at.toISOString() : '',
      // 流量限制字段
      trafficLimit: parseInt(row.traffic_limit) || 536870912000, // 默认500GB
      trafficUsed: parseInt(row.traffic_used) || 0,
      trafficResetAt: row.traffic_reset_at ? row.traffic_reset_at.toISOString() : null,
      // 订阅链接模式：strict=严格模式，loose=宽松模式
      tokenMode: row.token_mode || 'strict'
    }
  }

  _formatToken(row) {
    if (!row) return null
    return {
      id: row.id,
      token: row.token,
      name: row.name,
      status: row.status,
      expiresAt: row.expires_at ? row.expires_at.toISOString() : null,
      maxAccess: row.max_access || 0,
      accessCount: row.access_count || 0,
      oneTimeUse: !!row.one_time_use,
      isConsumed: !!row.is_consumed,
      userId: row.user_id || null,
      allowedIPs: this._parseJson(row.allowed_ips) || [],
      enabledNodes: this._parseJson(row.enabled_nodes) || [],
      vlessUuid: row.vless_uuid || null,
      createdBy: row.created_by,
      lastAccessAt: row.last_access_at ? row.last_access_at.toISOString() : null,
      lastAccessIP: row.last_access_ip,
      lastUserAgent: row.last_user_agent,
      createdAt: row.created_at ? row.created_at.toISOString() : null
    }
  }

  _parseJson(value) {
    if (!value) return null
    if (typeof value === 'object') return value
    try {
      return JSON.parse(value)
    } catch {
      return null
    }
  }
}

const subscriptionMysql = new SubscriptionMySQLClient()

module.exports = subscriptionMysql
