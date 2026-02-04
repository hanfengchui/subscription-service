const Redis = require('ioredis')
const config = require('../../config/config')
const logger = require('../utils/logger')

class RedisClient {
  constructor() {
    this.client = null
    this.isConnected = false
  }

  async connect() {
    if (this.isConnected && this.client) {
      return this.client
    }

    this.client = new Redis({
      host: config.redis.host,
      port: config.redis.port,
      password: config.redis.password,
      db: config.redis.db,
      retryDelayOnFailover: config.redis.retryDelayOnFailover,
      maxRetriesPerRequest: config.redis.maxRetriesPerRequest,
      lazyConnect: config.redis.lazyConnect,
      tls: config.redis.enableTLS ? {} : false
    })

    this.client.on('connect', () => {
      this.isConnected = true
      logger.info('🔗 Redis connected successfully')
    })

    this.client.on('error', (err) => {
      this.isConnected = false
      logger.error('❌ Redis connection error:', err)
    })

    this.client.on('close', () => {
      this.isConnected = false
      logger.warn('⚠️ Redis connection closed')
    })

    await this.client.connect()
    return this.client
  }

  async disconnect() {
    if (this.client) {
      await this.client.quit()
      this.isConnected = false
      logger.info('👋 Redis disconnected')
    }
  }

  getClient() {
    return this.client
  }

  getClientSafe() {
    if (!this.client || !this.isConnected) {
      throw new Error('Redis client is not connected')
    }
    return this.client
  }
}

module.exports = new RedisClient()
