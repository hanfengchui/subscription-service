/**
 * Xray gRPC API 用户管理服务
 * 通过 xray api CLI 命令动态添加/删除 VLESS 用户
 */

const { execFile } = require('child_process')
const { promisify } = require('util')
const fs = require('fs')
const path = require('path')
const os = require('os')
const logger = require('../utils/logger')
const subscriptionMysql = require('../models/subscriptionMysql')

const execFileAsync = promisify(execFile)

const XRAY_BIN = process.env.XRAY_BIN || '/usr/local/bin/xray'
const XRAY_API_ADDR = process.env.XRAY_API_ADDR || 'host.docker.internal:10085'
const XRAY_ENABLED = process.env.XRAY_ENABLED !== 'false'

// 解析 inbound 配置: "vless-grpc:10001,vless-ws:10002"
const XRAY_INBOUNDS = (process.env.XRAY_INBOUND_TAGS || 'vless-grpc:10001,vless-ws:10002')
  .split(',')
  .map(s => s.trim())
  .map(s => {
    const [tag, port] = s.split(':')
    return { tag, port: parseInt(port) || 10001 }
  })

class XrayService {
  /**
   * 为 token 添加 VLESS 用户到所有 inbound
   */
  async addTokenUser(tokenId, uuid) {
    if (!XRAY_ENABLED) return

    for (const inbound of XRAY_INBOUNDS) {
      try {
        await this._addUser(inbound.tag, inbound.port, `token_${tokenId}@sub`, uuid)
      } catch (err) {
        const message = err.message || ''
        if (message.includes('already exists') || message.includes('Added 0') || message.trim() === '') {
          logger.debug(`Xray user token_${tokenId}@sub already exists on ${inbound.tag}`)
        } else {
          logger.error(`Xray addUser failed for ${inbound.tag}:`, message)
        }
      }
    }
  }

  /**
   * 从所有 inbound 删除 token 用户
   */
  async removeTokenUser(tokenId) {
    if (!XRAY_ENABLED) return

    for (const inbound of XRAY_INBOUNDS) {
      try {
        await this._removeUser(inbound.tag, `token_${tokenId}@sub`)
      } catch (err) {
        if (err.message && err.message.includes('not found')) {
          logger.debug(`Xray user token_${tokenId}@sub not found on ${inbound.tag}`)
        } else {
          logger.error(`Xray removeUser failed for ${inbound.tag}:`, err.message)
        }
      }
    }
  }

  /**
   * 启动时同步所有 active token 到 Xray
   */
  async syncAllUsers() {
    if (!XRAY_ENABLED) {
      logger.info('⏭️ Xray service disabled, skipping sync')
      return
    }

    try {
      const backfilled = await subscriptionMysql.backfillVlessUuids()
      if (backfilled > 0) {
        logger.info(`🔧 Backfilled ${backfilled} tokens with vless_uuid`)
      }

      const tokens = await subscriptionMysql.getActiveTokensWithUuid()
      let added = 0
      let failed = 0

      for (const token of tokens) {
        try {
          await this.addTokenUser(token.id, token.vlessUuid)
          added++
        } catch (err) {
          failed++
          logger.error(`Xray sync failed for token ${token.id}:`, err.message)
        }
      }

      logger.info(`✅ Xray sync complete: ${added} users added, ${failed} failed, ${tokens.length} total`)
    } catch (err) {
      logger.error('❌ Xray syncAllUsers failed:', err)
      throw err
    }
  }

  /**
   * 通过 xray api adu 添加用户
   * 使用 inbounds 配置格式（xray api adu 要求的正确格式）
   */
  async _addUser(inboundTag, port, email, uuid) {
    const payload = {
      inbounds: [{
        tag: inboundTag,
        port: port,
        listen: '127.0.0.1',
        protocol: 'vless',
        settings: {
          clients: [{
            id: uuid,
            email: email,
            level: 0
          }],
          decryption: 'none'
        }
      }]
    }

    const tmpFile = path.join(os.tmpdir(), `xray-adu-${Date.now()}-${Math.random().toString(36).slice(2)}.json`)
    try {
      fs.writeFileSync(tmpFile, JSON.stringify(payload))
      const { stdout, stderr } = await execFileAsync(XRAY_BIN, [
        'api', 'adu',
        `--server=${XRAY_API_ADDR}`,
        tmpFile
      ], { timeout: 10000 })

      if (stderr && stderr.includes('failed')) {
        throw new Error(stderr.trim())
      }
      if (stdout && stdout.includes('Added 0')) {
        throw new Error(`Added 0 users for ${inboundTag}`)
      }
      logger.debug(`Xray adu ${inboundTag} ${email}: ${(stdout || '').trim()}`)
    } finally {
      try { fs.unlinkSync(tmpFile) } catch {}
    }
  }

  /**
   * 通过 xray api rmu 删除用户
   * email 是位置参数，不是 -email flag
   */
  async _removeUser(inboundTag, email) {
    const { stdout, stderr } = await execFileAsync(XRAY_BIN, [
      'api', 'rmu',
      `--server=${XRAY_API_ADDR}`,
      `-tag=${inboundTag}`,
      email
    ], { timeout: 10000 })

    if (stderr && stderr.includes('not found')) {
      throw new Error(`user not found: ${email}`)
    }
    if (stderr && stderr.includes('failed')) {
      throw new Error(stderr.trim())
    }
    logger.debug(`Xray rmu ${inboundTag} ${email}: ${(stdout || '').trim()}`)
  }
}

module.exports = new XrayService()
