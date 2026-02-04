/**
 * 流量统计服务 - 从 Hysteria2 和 Xray 获取流量数据
 */

const { exec } = require('child_process')
const { promisify } = require('util')
const execAsync = promisify(exec)
const redis = require('../models/redis')
const logger = require('../utils/logger')

// 配置
const CONFIG = {
  hysteria2: {
    apiUrl: process.env.HY2_STATS_URL || 'http://127.0.0.1:9999',
    secret: process.env.HY2_STATS_SECRET || 'CHANGE_ME'
  },
  xray: {
    apiPort: parseInt(process.env.XRAY_API_PORT, 10) || 10085
  }
}

// Redis 键前缀
const TRAFFIC_PREFIX = 'traffic_stats:'

class TrafficStatsService {
  constructor() {
    this.lastStats = {
      hysteria2: { upload: 0, download: 0 },
      xray: { upload: 0, download: 0 }
    }
  }

  /**
   * 获取 Hysteria2 流量统计
   */
  async getHysteria2Stats() {
    try {
      const response = await fetch(`${CONFIG.hysteria2.apiUrl}/traffic?clear=false`, {
        headers: {
          'Authorization': CONFIG.hysteria2.secret
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const data = await response.json()

      // Hysteria2 返回格式: { "user": { "tx": 123, "rx": 456 } }
      let totalUpload = 0
      let totalDownload = 0

      for (const [user, stats] of Object.entries(data)) {
        totalUpload += stats.tx || 0
        totalDownload += stats.rx || 0
      }

      return {
        success: true,
        upload: totalUpload,
        download: totalDownload,
        users: data
      }
    } catch (error) {
      logger.debug(`Hysteria2 stats error: ${error.message}`)
      return {
        success: false,
        upload: 0,
        download: 0,
        error: error.message
      }
    }
  }

  /**
   * 获取 Xray 流量统计
   */
  async getXrayStats() {
    try {
      // 使用 xray api 命令获取统计
      const { stdout } = await execAsync(
        `/usr/local/bin/xray api statsquery --server=127.0.0.1:${CONFIG.xray.apiPort} -pattern ""`,
        { timeout: 5000 }
      )

      const stats = JSON.parse(stdout)
      let totalUpload = 0
      let totalDownload = 0

      // 解析统计数据
      if (stats.stat) {
        for (const item of stats.stat) {
          if (item.name.includes('uplink')) {
            totalUpload += item.value || 0
          } else if (item.name.includes('downlink')) {
            totalDownload += item.value || 0
          }
        }
      }

      return {
        success: true,
        upload: totalUpload,
        download: totalDownload,
        raw: stats
      }
    } catch (error) {
      logger.debug(`Xray stats error: ${error.message}`)
      return {
        success: false,
        upload: 0,
        download: 0,
        error: error.message
      }
    }
  }

  /**
   * 获取所有流量统计
   */
  async getAllStats() {
    const [hy2Stats, xrayStats] = await Promise.all([
      this.getHysteria2Stats(),
      this.getXrayStats()
    ])

    const totalUpload = (hy2Stats.upload || 0) + (xrayStats.upload || 0)
    const totalDownload = (hy2Stats.download || 0) + (xrayStats.download || 0)

    return {
      total: {
        upload: totalUpload,
        download: totalDownload,
        total: totalUpload + totalDownload
      },
      hysteria2: {
        upload: hy2Stats.upload || 0,
        download: hy2Stats.download || 0,
        available: hy2Stats.success
      },
      xray: {
        upload: xrayStats.upload || 0,
        download: xrayStats.download || 0,
        available: xrayStats.success
      }
    }
  }

  /**
   * 保存流量统计到 Redis
   */
  async saveStats() {
    try {
      const stats = await this.getAllStats()
      const today = new Date().toISOString().split('T')[0]
      const now = new Date().toISOString()

      // 保存总统计
      await redis.client.hset(`${TRAFFIC_PREFIX}total`, {
        upload: stats.total.upload.toString(),
        download: stats.total.download.toString(),
        lastUpdated: now
      })

      // 保存今日统计（增量）
      const todayKey = `${TRAFFIC_PREFIX}daily:${today}`
      await redis.client.hincrby(todayKey, 'upload', stats.total.upload - (this.lastStats.total?.upload || 0))
      await redis.client.hincrby(todayKey, 'download', stats.total.download - (this.lastStats.total?.download || 0))
      await redis.client.expire(todayKey, 7 * 24 * 60 * 60) // 7天过期

      this.lastStats = stats

      return stats
    } catch (error) {
      logger.error('Failed to save traffic stats:', error)
      return null
    }
  }

  /**
   * 获取保存的流量统计
   */
  async getSavedStats() {
    try {
      const today = new Date().toISOString().split('T')[0]

      const [totalStats, todayStats] = await Promise.all([
        redis.client.hgetall(`${TRAFFIC_PREFIX}total`),
        redis.client.hgetall(`${TRAFFIC_PREFIX}daily:${today}`)
      ])

      return {
        total: {
          upload: parseInt(totalStats?.upload) || 0,
          download: parseInt(totalStats?.download) || 0,
          lastUpdated: totalStats?.lastUpdated
        },
        today: {
          upload: parseInt(todayStats?.upload) || 0,
          download: parseInt(todayStats?.download) || 0
        }
      }
    } catch (error) {
      logger.error('Failed to get saved traffic stats:', error)
      return {
        total: { upload: 0, download: 0 },
        today: { upload: 0, download: 0 }
      }
    }
  }

  /**
   * 格式化字节数
   */
  formatBytes(bytes) {
    if (bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  /**
   * 获取格式化的统计信息
   */
  async getFormattedStats() {
    const realtime = await this.getAllStats()
    const saved = await this.getSavedStats()

    return {
      realtime: {
        upload: this.formatBytes(realtime.total.upload),
        download: this.formatBytes(realtime.total.download),
        total: this.formatBytes(realtime.total.total),
        uploadBytes: realtime.total.upload,
        downloadBytes: realtime.total.download,
        hysteria2Available: realtime.hysteria2.available,
        xrayAvailable: realtime.xray.available
      },
      today: {
        upload: this.formatBytes(saved.today.upload),
        download: this.formatBytes(saved.today.download),
        uploadBytes: saved.today.upload,
        downloadBytes: saved.today.download
      },
      history: {
        upload: this.formatBytes(saved.total.upload),
        download: this.formatBytes(saved.total.download),
        lastUpdated: saved.total.lastUpdated
      }
    }
  }
}

module.exports = new TrafficStatsService()
