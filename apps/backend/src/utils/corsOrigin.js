function normalizeOrigin(origin) {
  return String(origin || '').trim().replace(/\/$/, '')
}

function parseAllowedOrigins(value) {
  return String(value || '*')
    .split(',')
    .map(normalizeOrigin)
    .filter(Boolean)
}

function createCorsOptions() {
  const allowedOrigins = parseAllowedOrigins(process.env.CORS_ORIGIN || '*')

  if (allowedOrigins.includes('*')) {
    return {
      origin: '*',
      credentials: false
    }
  }

  return {
    origin(origin, callback) {
      if (!origin) {
        return callback(null, true)
      }

      const normalized = normalizeOrigin(origin)
      callback(null, allowedOrigins.includes(normalized))
    },
    credentials: false
  }
}

module.exports = {
  createCorsOptions,
  parseAllowedOrigins
}
