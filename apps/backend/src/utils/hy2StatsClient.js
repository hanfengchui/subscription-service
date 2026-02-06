/**
 * Hysteria2 流量统计客户端
 * 支持容器环境下将 localhost 自动回退到 host.docker.internal
 */

function normalizeApiUrl(apiUrl) {
  return (apiUrl || '').replace(/\/+$/, '')
}

function getHy2StatsCandidates(apiUrl) {
  const normalized = normalizeApiUrl(apiUrl)
  const candidates = []

  const push = (url) => {
    if (url && !candidates.includes(url)) {
      candidates.push(url)
    }
  }

  push(normalized)

  try {
    const parsed = new URL(normalized)
    const localHosts = new Set(['127.0.0.1', 'localhost'])

    if (localHosts.has(parsed.hostname)) {
      const basePath = parsed.pathname && parsed.pathname !== '/' ? parsed.pathname : ''
      const hostDockerInternal = `${parsed.protocol}//host.docker.internal${parsed.port ? `:${parsed.port}` : ''}${basePath}`
      push(hostDockerInternal)
    }
  } catch {
    // 保持原始地址即可
  }

  return candidates
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 5000) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)

  try {
    return await fetch(url, {
      ...options,
      signal: controller.signal
    })
  } finally {
    clearTimeout(timer)
  }
}

async function fetchHy2Traffic({ apiUrl, secret, clear = false, timeoutMs = 5000 }) {
  const clearParam = clear ? 'true' : 'false'
  const candidates = getHy2StatsCandidates(apiUrl)

  let lastError = 'No available Hysteria2 stats endpoint'

  for (const candidate of candidates) {
    const requestUrl = `${candidate}/traffic?clear=${clearParam}`

    try {
      const response = await fetchWithTimeout(
        requestUrl,
        {
          headers: {
            Authorization: secret
          }
        },
        timeoutMs
      )

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const data = await response.json()
      return {
        success: true,
        data,
        sourceUrl: requestUrl
      }
    } catch (error) {
      lastError = `${requestUrl} -> ${error.message}`
    }
  }

  return {
    success: false,
    error: lastError,
    data: {},
    candidates
  }
}

module.exports = {
  getHy2StatsCandidates,
  fetchHy2Traffic
}
