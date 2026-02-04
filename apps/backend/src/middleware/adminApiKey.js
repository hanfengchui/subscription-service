const crypto = require('crypto')
const logger = require('../utils/logger')

const parseAdminKeys = () => {
  const raw = process.env.SUB_ADMIN_API_KEY || ''
  return raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
}

const timingSafeEquals = (a, b) => {
  if (!a || !b) return false
  const bufA = Buffer.from(a)
  const bufB = Buffer.from(b)
  if (bufA.length !== bufB.length) return false
  return crypto.timingSafeEqual(bufA, bufB)
}

const extractApiKey = (req) => {
  const headerCandidates = [
    req.headers['x-sub-admin-key'],
    req.headers['x-api-key'],
    req.headers['authorization']
  ]

  for (const candidate of headerCandidates) {
    let value = candidate
    if (Array.isArray(value)) {
      value = value[0]
    }
    if (typeof value !== 'string') {
      continue
    }
    let trimmed = value.trim()
    if (!trimmed) {
      continue
    }
    if (/^Bearer\s+/i.test(trimmed)) {
      trimmed = trimmed.replace(/^Bearer\s+/i, '').trim()
    }
    if (trimmed) {
      return trimmed
    }
  }

  return ''
}

const authenticateAdminApiKey = (req, res, next) => {
  const allowedKeys = parseAdminKeys()
  if (allowedKeys.length === 0) {
    logger.warn('⚠️ Admin API key not configured, rejecting admin request')
    return res.status(401).json({ error: 'Admin API key not configured' })
  }

  const providedKey = extractApiKey(req)
  if (!providedKey) {
    return res.status(401).json({ error: 'Missing admin API key' })
  }

  const isValid = allowedKeys.some((key) => timingSafeEquals(key, providedKey))
  if (!isValid) {
    return res.status(403).json({ error: 'Invalid admin API key' })
  }

  return next()
}

module.exports = { authenticateAdminApiKey }
