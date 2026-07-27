# frozen_string_literal: true

require "digest"

module Transit
  # Deterministic, stable synthetic delays so the time scrubber can show
  # delayed/early status even without live-vehicle data.
  #
  # Convention:
  # - delay_seconds > 0 => delayed (behind schedule)
  # - delay_seconds < 0 => early (ahead of schedule)
  module SyntheticDelay
    module_function

    def status_for(delay_seconds)
      return "on_time" if delay_seconds.abs < 120

      delay_seconds.positive? ? "delayed" : "early"
    end

    def delay_seconds_for_trip(trip, at:)
      delay_seconds_for_key(trip_cache_key(trip), at: at)
    end

    def delay_seconds_for_headway(route_id:, direction:, at:)
      delay_seconds_for_key("headway:#{route_id}:#{direction}", at: at)
    end

    def delay_seconds_for_key(key, at:)
      # Make the delay stable per (key, day) so scrubbing feels consistent.
      day_key = at.to_date.to_s
      digest = Digest::SHA256.hexdigest("#{key}|#{day_key}|#{at.to_i / 3600}")
      r = digest.to_i(16) % 10_000

      # ~80% on-time (small jitter), ~15% delayed, ~5% early.
      if r < 8_000
        # jitter within +/- 60 seconds
        ((r % 121) - 60)
      elsif r < 9_500
        # delayed: 60..600 seconds
        60 + (r % (11 * 60))
      else
        # early: -60..-300 seconds
        -(60 + (r % (5 * 60)))
      end
    end

    def trip_cache_key(trip)
      trip.train_number.presence || trip.id
    end
  end
end
