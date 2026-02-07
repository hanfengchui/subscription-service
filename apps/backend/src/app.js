const express = require('express')
const cors = require('cors')

const config = require('../config/config')
const logger = require('./utils/logger')
const redis = require('./models/redis')

const subscriptionRoutes = require('./routes/subscriptionRoutes')
const trafficSyncService = require('./services/trafficSyncService')
const hysteria2AuthService = require('./services/hysteria2AuthService')
const subUserService = require('./services/subUserService')

const app = express()

// Trust proxy (for real IP / protocol when behind Nginx)
app.set('trust proxy', config.server.trustProxy)

// Middleware
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  credentials: false
}))
app.use(express.json({ limit: process.env.REQUEST_BODY_LIMIT || '2mb' }))

// Health check
app.get('/health', async (req, res) => {
  res.json({
    status: 'ok',
    service: 'subscription-service',
    timestamp: new Date().toISOString()
  })
})

// Routes
app.use('/sub', subscriptionRoutes)

async function startServices() {
  // Redis is required for session management
  logger.info('🔄 Connecting to Redis...')
  await redis.connect()
  logger.info('✅ Redis connected')

  // Optional background services
  const trafficSyncEnabled = process.env.TRAFFIC_SYNC_ENABLED !== 'false'
  const hy2AuthEnabled = process.env.HY2_AUTH_ENABLED !== 'false'

  if (trafficSyncEnabled) {
    try {
      await trafficSyncService.start()
    } catch (error) {
      logger.error('❌ Failed to start traffic sync service:', error)
    }
  } else {
    logger.warn('⚠️ Traffic sync service disabled')
  }

  if (hy2AuthEnabled) {
    try {
      await hysteria2AuthService.start()
    } catch (error) {
      logger.error('❌ Failed to start Hysteria2 auth service:', error)
    }
  } else {
    logger.warn('⚠️ Hysteria2 auth service disabled')
  }
}

async function start() {
  try {
    await startServices()

    const initAdminEnabled = process.env.SUB_INIT_ADMIN !== 'false'
    if (initAdminEnabled) {
      const maxRetries = 5
      for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          await subUserService.initDefaultAdmin()
          break
        } catch (error) {
          if (attempt < maxRetries) {
            logger.warn(`⏳ Init default admin failed (attempt ${attempt}/${maxRetries}), retrying in ${attempt * 3}s...`)
            await new Promise(r => setTimeout(r, attempt * 3000))
          } else {
            logger.error('❌ Failed to init default admin after all retries:', error)
          }
        }
      }
    }

    const server = app.listen(config.server.port, config.server.host, () => {
      logger.info(
        `🚀 Subscription service listening on http://${config.server.host}:${config.server.port}`
      )
    })

    // Graceful shutdown
    const shutdown = async () => {
      logger.info('🛑 Shutting down...')
      try {
        server.close()
        await hysteria2AuthService.stop()
        await redis.disconnect()
        logger.info('✅ Shutdown complete')
        process.exit(0)
      } catch (error) {
        logger.error('❌ Shutdown error:', error)
        process.exit(1)
      }
    }

    process.on('SIGINT', shutdown)
    process.on('SIGTERM', shutdown)
  } catch (error) {
    logger.error('❌ Failed to start subscription service:', error)
    process.exit(1)
  }
}

start()
