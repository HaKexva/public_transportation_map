function haversineKm(a, b) {
  const toRad = Math.PI / 180
  const lat1 = a[1] * toRad
  const lat2 = b[1] * toRad
  const dLat = lat2 - lat1
  const dLng = (b[0] - a[0]) * toRad
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h)))
}

export function buildChainage(line) {
  if (!Array.isArray(line) || line.length < 2) return null

  const cum = [ 0 ]
  for (let i = 1; i < line.length; i += 1) {
    cum.push(cum[i - 1] + haversineKm(line[i - 1], line[i]))
  }

  return { line, cum, lengthKm: cum[cum.length - 1] }
}

export function longestTrackLine(tracks) {
  if (!Array.isArray(tracks) || tracks.length === 0) return null
  return tracks.reduce((best, line) => {
    if (!Array.isArray(line) || line.length < 2) return best
    if (!best || line.length > best.length) return line
    return best
  }, null)
}

export function pointAtDistance(chainage, distanceKm) {
  if (!chainage?.line || !chainage?.cum?.length) return null

  const { line, cum } = chainage
  const dist = Math.max(0, Math.min(cum[cum.length - 1], Number(distanceKm) || 0))
  if (dist <= 0) return { lat: line[0][1], lng: line[0][0] }
  if (dist >= cum[cum.length - 1]) return { lat: line[line.length - 1][1], lng: line[line.length - 1][0] }

  let lo = 0
  let hi = cum.length - 1
  while (lo < hi) {
    const mid = (lo + hi) >> 1
    if (cum[mid] < dist) lo = mid + 1
    else hi = mid
  }

  const i = Math.max(lo, 1)
  const span = cum[i] - cum[i - 1]
  const t = span > 0 ? (dist - cum[i - 1]) / span : 0
  const a = line[i - 1]
  const b = line[i]
  return {
    lat: a[1] + ((b[1] - a[1]) * t),
    lng: a[0] + ((b[0] - a[0]) * t)
  }
}

export function nearestDistance(chainage, lng, lat) {
  if (!chainage?.line || !chainage?.cum) return null

  const { line, cum } = chainage
  let bestD = null
  let bestDist = Infinity

  for (let i = 0; i < line.length - 1; i += 1) {
    const ax = line[i][0]
    const ay = line[i][1]
    const bx = line[i + 1][0]
    const by = line[i + 1][1]
    const dx = bx - ax
    const dy = by - ay
    const len2 = (dx * dx) + (dy * dy)
    let t = len2 > 0 ? (((lng - ax) * dx) + ((lat - ay) * dy)) / len2 : 0
    t = Math.max(0, Math.min(1, t))
    const px = ax + (dx * t)
    const py = ay + (dy * t)
    const dist = Math.sqrt(((lat - py) * 111) ** 2 + ((lng - px) * 101) ** 2)
    if (dist >= bestDist) continue
    bestDist = dist
    bestD = cum[i] + ((cum[i + 1] - cum[i]) * t)
  }

  return bestD
}
