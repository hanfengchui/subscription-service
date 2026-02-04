const path = require('path')
require('dotenv').config()

const config = {
  server: {
    port: parseInt(process.env.PORT, 10) || 3000,
    host: process.env.HOST || '0.0.0.0',
    nodeEnv: process.env.NODE_ENV || 'development',
    trustProxy: process.env.TRUST_PROXY === 'true'
  },
  redis: {
    host: process.env.REDIS_HOST || '127.0.0.1',
    port: parseInt(process.env.REDIS_PORT, 10) || 6379,
    password: process.env.REDIS_PASSWORD || '',
    db: parseInt(process.env.REDIS_DB, 10) || 0,
    connectTimeout: parseInt(process.env.REDIS_CONNECT_TIMEOUT, 10) || 10000,
    commandTimeout: parseInt(process.env.REDIS_COMMAND_TIMEOUT, 10) || 5000,
    retryDelayOnFailover: parseInt(process.env.REDIS_RETRY_DELAY, 10) || 100,
    maxRetriesPerRequest: parseInt(process.env.REDIS_MAX_RETRIES, 10) || 3,
    lazyConnect: process.env.REDIS_LAZY_CONNECT !== 'false',
    enableTLS: process.env.REDIS_ENABLE_TLS === 'true'
  },
  logging: {
    level: process.env.LOG_LEVEL || 'info',
    dirname: path.join(__dirname, '..', 'logs'),
    maxSize: process.env.LOG_MAX_SIZE || '10m',
    maxFiles: parseInt(process.env.LOG_MAX_FILES, 10) || 5
  },
  system: {
    timezoneOffset: parseInt(process.env.TIMEZONE_OFFSET, 10) || 8
  }
}

module.exports = config
