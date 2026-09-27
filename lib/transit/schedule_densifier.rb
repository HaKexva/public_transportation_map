# frozen_string_literal: true

module Transit
  # Inserts through-stations so express trips follow the corridor instead of
  # chord-jumping between booked stops.
  class ScheduleDensifier
    def initialize(coord_lookup: GeojsonStationCoords.method(:lookup))
      @coord_lookup = coord_lookup
    end

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

        left_dep = left[:departure].to_f
        right_arr = right[:arrival].to_f
        travel = wrap_delta(left_dep, right_arr)
        next if travel <= 0

        fractions = distance_fractions(route, corridor, left_idx, right_idx)
        ((left_idx + 1)...right_idx).each do |idx|
          frac = fractions[idx - left_idx]
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

    # Fraction of the left->right distance reached at each corridor index, so
    # pass times follow station spacing; falls back to even spacing when any
    # station lacks coordinates.
    def distance_fractions(route, corridor, left_idx, right_idx)
      span = right_idx - left_idx
      even = (0..span).map { |step| step.to_f / span }
      coords = (left_idx..right_idx).map { |idx| station_coord(route, corridor[idx].station_ref) }
      return even if coords.any?(&:nil?)

      cumulative = [ 0.0 ]
      coords.each_cons(2) { |a, b| cumulative << (cumulative.last + haversine_km(a, b)) }
      total = cumulative.last
      return even unless total.positive?

      cumulative.map { |km| km / total }
    end

    def station_coord(route, ref)
      @station_coords ||= {}
      key = [ route.id, ref ]
      return @station_coords[key] if @station_coords.key?(key)

      @station_coords[key] = @coord_lookup.call(route, ref)
    end

    def haversine_km(a, b)
      lat1 = a[0].to_f * Math::PI / 180.0
      lat2 = b[0].to_f * Math::PI / 180.0
      dlat = lat2 - lat1
      dlng = (b[1].to_f - a[1].to_f) * Math::PI / 180.0
      h = Math.sin(dlat / 2)**2 + (Math.cos(lat1) * Math.cos(lat2) * Math.sin(dlng / 2)**2)
      2 * 6371.0 * Math.asin([ Math.sqrt(h), 1.0 ].min)
    end

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
