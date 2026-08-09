const PROFILES = {
  hsr: { accel: 0.22, decel: 0.22 },
  express: { accel: 0.28, decel: 0.28 },
  local: { accel: 0.34, decel: 0.34 }
}

const EXPRESS_TYPES = /自強|太魯閣|普悠瑪|EMU|express|limited|taroko|puyuma|temu|tc/i
const HSR_TYPES = /hsr|高鐵/i

export function motionKind(systemId, tripType) {
  const blob = `${systemId || ""} ${tripType || ""}`
  if (String(systemId) === "hsr" || HSR_TYPES.test(blob)) return "hsr"
  if (EXPRESS_TYPES.test(blob)) return "express"
  return "local"
}

function distanceShare(accel, cruiseEnd, decel, part) {
  const accelDist = accel * 0.5
  const decelDist = decel * 0.5
  const cruiseDist = Math.max(cruiseEnd - accel, 0)
  const total = accelDist + cruiseDist + decelDist || 1
  if (part === "accel") return accelDist / total
  if (part === "decel") return decelDist / total
  return cruiseDist / total
}

export function easedProgress(linear, kind = "local") {
  const t = Math.max(0, Math.min(1, Number(linear) || 0))
  const profile = PROFILES[kind] || PROFILES.local
  const accel = profile.accel
  const decel = profile.decel
  const cruiseStart = accel
  const cruiseEnd = 1 - decel

  if (t <= 0) return 0
  if (t >= 1) return 1

  if (t < cruiseStart) {
    const u = t / accel
    return u * u * distanceShare(accel, cruiseEnd, decel, "accel")
  }

  if (t > cruiseEnd) {
    const u = (1 - t) / decel
    return 1 - (u * u * distanceShare(accel, cruiseEnd, decel, "decel"))
  }

  const accelShare = distanceShare(accel, cruiseEnd, decel, "accel")
  const cruiseShare = distanceShare(accel, cruiseEnd, decel, "cruise")
  const frac = (t - cruiseStart) / (cruiseEnd - cruiseStart)
  return Math.max(0, Math.min(1, accelShare + (cruiseShare * frac)))
}

export function speedKmh(linear, { kind = "local", hopKm, hopMinutes } = {}) {
  if (!(hopMinutes > 0) || !(hopKm > 0)) return 0
  const dt = 0.02
  const t = Math.max(0, Math.min(1, Number(linear) || 0))
  const p0 = easedProgress(Math.max(t - dt, 0), kind)
  const p1 = easedProgress(Math.min(t + dt, 1), kind)
  const dmin = hopMinutes * (2 * dt)
  if (dmin <= 0) return 0
  return (hopKm * Math.abs(p1 - p0) / dmin) * 60
}
