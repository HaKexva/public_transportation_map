# frozen_string_literal: true

module Transit
  # Trapezoid speed profile: accelerate, cruise, decelerate.
  # Returns eased 0..1 progress along a hop given linear time fraction.
  class MotionProfile
    PROFILES = {
      "hsr" => { accel: 0.22, decel: 0.22 },
      "express" => { accel: 0.28, decel: 0.28 },
      "local" => { accel: 0.34, decel: 0.34 }
    }.freeze

    EXPRESS_TYPES = /自強|太魯閣|普悠瑪|EMU|express|limited|taroko|puyuma|temu|tc/i
    HSR_TYPES = /hsr|高鐵/i

    def self.kind_for(system_id:, trip_type: nil)
      blob = "#{system_id} #{trip_type}"
      return "hsr" if system_id.to_s == "hsr" || blob.match?(HSR_TYPES)
      return "express" if blob.match?(EXPRESS_TYPES)

      "local"
    end

    def self.eased_progress(linear, kind: "local")
      t = linear.to_f.clamp(0.0, 1.0)
      profile = PROFILES[kind.to_s] || PROFILES["local"]
      accel = profile[:accel]
      decel = profile[:decel]
      cruise_start = accel
      cruise_end = 1.0 - decel

      if t <= 0
        0.0
      elsif t >= 1
        1.0
      elsif t < cruise_start
        # s = 0.5 a t^2; normalize so full hop integrates to 1
        (t / accel) * (t / accel) * distance_share(accel, cruise_end, decel, :accel)
      elsif t > cruise_end
        u = (1.0 - t) / decel
        1.0 - (u * u * distance_share(accel, cruise_end, decel, :decel))
      else
        accel_share = distance_share(accel, cruise_end, decel, :accel)
        cruise_share = distance_share(accel, cruise_end, decel, :cruise)
        frac = (t - cruise_start) / (cruise_end - cruise_start)
        accel_share + (cruise_share * frac)
      end.clamp(0.0, 1.0)
    end

    def self.speed_kmh(linear, kind:, hop_km:, hop_minutes:)
      return 0.0 if hop_minutes.to_f <= 0 || hop_km.to_f <= 0

      dt = 0.02
      t = linear.to_f.clamp(0.0, 1.0)
      p0 = eased_progress([ t - dt, 0.0 ].max, kind: kind)
      p1 = eased_progress([ t + dt, 1.0 ].min, kind: kind)
      dp = (p1 - p0).abs
      dmin = hop_minutes.to_f * (2 * dt)
      return 0.0 if dmin <= 0

      (hop_km.to_f * dp / dmin) * 60.0
    end

    def self.distance_share(accel, cruise_end, decel, part)
      accel_dist = accel * 0.5
      decel_dist = decel * 0.5
      cruise_dist = [ cruise_end - accel, 0.0 ].max
      total = accel_dist + cruise_dist + decel_dist
      total = 1.0 if total <= 0
      case part
      when :accel then accel_dist / total
      when :decel then decel_dist / total
      else cruise_dist / total
      end
    end
    private_class_method :distance_share
  end
end
