# frozen_string_literal: true

module Transit
  # Trapezoid speed profile: accelerate, cruise, decelerate.
  # Returns eased 0..1 progress along a hop given linear time fraction.
  class MotionProfile
    PROFILES = {
      "hsr" => { accel: 0.22, decel: 0.22 },
      "express" => { accel: 0.28, decel: 0.28 },
      "juguang" => { accel: 0.31, decel: 0.31 },
      "local" => { accel: 0.34, decel: 0.34 },
      "constant" => { accel: 0.0, decel: 0.0 }
    }.freeze

    # TDX TrainTypeCode (1 太魯閣, 2 普悠瑪, 3 自強, 4 莒光, 5 復興, 6 區間, 7 普快,
    # 10 區間快, 11 自強3000) and ODS CarClass prefixes (110x 自強, 111x 莒光, ...).
    TRA_TYPE_CODES = {
      1 => "express", 2 => "express", 3 => "express", 11 => "express",
      4 => "juguang",
      5 => "local", 6 => "local", 7 => "local", 10 => "local"
    }.freeze
    TRA_CAR_CLASS_PREFIXES = [
      [ /\A110/, "express" ],
      [ /\A111/, "juguang" ],
      [ /\A11[2-4]/, "local" ]
    ].freeze
    EXPRESS_TYPES = /自強|太魯閣|普悠瑪|express|limited|taroko|puyuma/i
    JUGUANG_TYPES = /莒光|chu-?kuang/i
    LOCAL_TYPES = /區間|復興|普快|local|commuter/i
    HSR_TYPES = /hsr|高鐵/i
    METRO_SYSTEMS = /metro|mrt|light_rail/i

    def self.kind_for(system_id:, trip_type: nil)
      system = system_id.to_s
      type = trip_type.to_s.strip
      return "hsr" if system == "hsr" || type.match?(HSR_TYPES)

      if type.match?(/\A\d+\z/)
        coded = TRA_TYPE_CODES[type.to_i]
        return coded if coded

        prefix = TRA_CAR_CLASS_PREFIXES.find { |pattern, _| type.match?(pattern) }
        return prefix.last if prefix
      end
      return "express" if type.match?(EXPRESS_TYPES)
      return "juguang" if type.match?(JUGUANG_TYPES)
      return "local" if type.match?(LOCAL_TYPES)

      # Metro hops are always station to station; other unknown types move at constant speed.
      system.match?(METRO_SYSTEMS) ? "local" : "constant"
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
      elsif accel <= 0 && decel <= 0
        t
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
