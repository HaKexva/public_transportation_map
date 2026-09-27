const PROFILES = {
  hsr: { accel: 0.22, decel: 0.22 },
  express: { accel: 0.28, decel: 0.28 },
  juguang: { accel: 0.31, decel: 0.31 },
  local: { accel: 0.34, decel: 0.34 },
  constant: { accel: 0, decel: 0 }
}

// TDX TrainTypeCode (1 太魯閣, 2 普悠瑪, 3 自強, 4 莒光, 5 復興, 6 區間, 7 普快,
// 10 區間快, 11 自強3000) and ODS CarClass prefixes (110x 自強, 111x 莒光, ...).
const TRA_TYPE_CODES = {
  1: "express", 2: "express", 3: "express", 11: "express",
  4: "juguang",
  5: "local", 6: "local", 7: "local", 10: "local"
}
const TRA_CAR_CLASS_PREFIXES = [
  [ /^110/, "express" ],
  [ /^111/, "juguang" ],
  [ /^11[2-4]/, "local" ]
]
const EXPRESS_TYPES = /自強|太魯閣|普悠瑪|express|limited|taroko|puyuma/i
const JUGUANG_TYPES = /莒光|chu-?kuang/i
const LOCAL_TYPES = /區間|復興|普快|local|commuter/i
const HSR_TYPES = /hsr|高鐵/i
const METRO_SYSTEMS = /metro|mrt|light_rail/i

export function motionKind(systemId, tripType) {
  const system = String(systemId || "")
  const type = String(tripType ?? "").trim()
  if (system === "hsr" || HSR_TYPES.test(type)) return "hsr"

  if (/^\d+$/.test(type)) {
    const code = Number(type)
    if (TRA_TYPE_CODES[code]) return TRA_TYPE_CODES[code]
    const match = TRA_CAR_CLASS_PREFIXES.find(([ pattern ]) => pattern.test(type))
    if (match) return match[1]
  }
  if (EXPRESS_TYPES.test(type)) return "express"
  if (JUGUANG_TYPES.test(type)) return "juguang"
  if (LOCAL_TYPES.test(type)) return "local"

  // Metro hops are always station to station; other unknown types move at constant speed.
  if (METRO_SYSTEMS.test(system)) return "local"
  return "constant"
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
  if (accel <= 0 && decel <= 0) return t

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
