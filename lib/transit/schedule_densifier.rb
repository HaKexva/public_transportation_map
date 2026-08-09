# frozen_string_literal: true

module Transit
  # Inserts through-stations so express trips follow the corridor instead of
  # chord-jumping between booked stops.
  class ScheduleDensifier
    def densify(route, ordered_stops)
      stops = Array(ordered_stops)
      return stops if stops.length < 2 || route.nil?

      stations = route_stations(route)
      return stops if stations.length < 3

      first_idx = station_index(stations, stops.first[:station_ref])
      last_idx = station_index(stations, stops.last[:station_ref])
      return stops if first_idx.nil? || last_idx.nil? || first_idx == last_idx

      corridor = first_idx <= last_idx ? stations[first_idx..last_idx] : stations[last_idx..first_idx].reverse
      return stops if corridor.length <= stops.length

      booked = stops.map { |stop| [ stop, station_index(corridor, stop[:station_ref]) ] }
      booked.select! { |_stop, idx| idx }
      return stops if booked.length < 2

      densified = []
      booked.each_cons(2) do |(left, left_idx), (right, right_idx)|
        densified << left
        next if right_idx <= left_idx + 1

        span = right_idx - left_idx
        left_arr = left[:arrival].to_f
        left_dep = left[:departure].to_f
        right_arr = right[:arrival].to_f
        travel = wrap_delta(left_dep, right_arr)
        next if travel <= 0

        ((left_idx + 1)...right_idx).each do |idx|
          frac = (idx - left_idx).to_f / span
          pass = wrap_add(left_dep, travel * frac)
          station = corridor[idx]
          densified << {
            station_ref: station.station_ref,
            name: station.name,
            arrival: pass,
            departure: pass,
            through: true
          }
        end
      end
      densified << booked.last.first
      densified
    end

    private

    def route_stations(route)
      scope = route.transit_route_stations
      both = scope.where(direction: TransitRoute::DIRECTION_BOTH).ordered.to_a
      return both if both.length >= 3

      scope.ordered.to_a.uniq(&:station_ref)
    end

    def station_index(stations, ref)
      tokens = TrainContinuation.station_tokens(ref)
      return nil if tokens.empty?

      stations.find_index do |station|
        TrainContinuation.same_station?(station.station_ref, ref)
      end
    end

    def wrap_delta(from_minutes, to_minutes)
      delta = to_minutes.to_f - from_minutes.to_f
      delta += 1440 if delta < -720
      delta
    end

    def wrap_add(from_minutes, delta)
      value = from_minutes.to_f + delta.to_f
      value -= 1440 if value >= 1440
      value += 1440 if value.negative?
      value
    end
  end
end
