# frozen_string_literal: true

module Transit
  module Itinerary
    # Round-based public transit search (RAPTOR) over a compiled Graph.
    class Router
      MAX_ROUNDS = 5
      WINDOW = 180
      DAY_HORIZON = 18 * 60
      DEPARTURE_CAP = 40
      MIN_TRANSFER = 2
      WALK_ONLY_METERS = 1_200
      RESULT_CAP = 5
      # Beyond this, city buses are only used for first/last mile near O/D.
      LONG_HAUL_METERS = 25_000
      LOCAL_BUS_METERS = 3_000
      CORRIDOR_PAD_METERS = 40_000
      # Island ferry/airport terminals may sit outside the O–D bbox (高雄港 for
      # 台北→馬公); pull them in and allow city buses that feed those gateways.
      ISLAND_GATEWAY_PAD_DEG = 0.18
      ISLAND_NAME_HINTS = %w[
        澎湖 馬公 綠島 蘭嶼 小琉球 金門 馬祖 南竿 北竿 七美 望安
        琉球 福澳 尚義 penghu magong kinmen matsu nangan liuqiu
      ].freeze
      # After the first profile finds a trip, later searches ignore arrivals
      # much worse than that (still leave room for fewer-transfer options).
      PRUNE_SLACK_MINUTES = 75
      PROFILES = [
        { "id" => "earliest", transfer_penalty: 0, walk_weight: 1 },
        { "id" => "fewer_transfers", transfer_penalty: 45, walk_weight: 1 },
        { "id" => "less_walking", transfer_penalty: 0, walk_weight: 4 }
      ].freeze

      attr_reader :notice

      def initialize(graph, origin:, destination:, depart_at:)
        @graph = graph
        @origin = origin
        @destination = destination
        @depart_at = depart_at
        @date = depart_at.to_date
        @depart_min = depart_at.hour * 60 + depart_at.min
        @latest = @depart_min + WINDOW
        @notice = nil
        @blocked_routes = nil
        @prune_clock = nil
        prepare_pruning!
      end

      def call
        return [] unless @origin && @destination

        @egress_stops = @graph.stops_near(@destination["lat"], @destination["lon"], Geometry::ACCESS_METERS)
        merge_island_water_air_access!
        found = collect_itineraries
        if found.none? { |item| item["profile"] != "walk" }
          @latest = @depart_min + DAY_HORIZON
          @prune_clock = nil
          later = collect_itineraries
          if later.any? { |item| item["profile"] != "walk" }
            later.each { |item| item["later"] = true unless item["profile"] == "walk" }
            @notice = I18n.t("map.itinerary.later_notice")
            found = later
          end
        end
        found = diversify_trunk_modes(found)
        found = diversify(found) if found.count { |item| item["profile"] != "walk" } < 2
        walk = direct_walk
        if walk && (found.empty? || walk["duration_minutes"] < found.first["duration_minutes"])
          found << walk unless found.any? { |item| item["signature"] == walk["signature"] }
        end
        # Diversify may append a faster ferry/flight after an earlier profile hit.
        found.sort_by! { |item|
          [ item["profile"] == "walk" ? 1 : 0, item["duration_minutes"].to_i, item["transfers"].to_i ]
        }
        found.first(RESULT_CAP).map { |item| item.except("signature") }
      end

      # Harbor ↔ airport on the same island is often 2–8 km; treat those
      # terminals as access/egress with the real walk (or last-mile) time.
      def merge_island_water_air_access!
        return if @gateway_ids.blank?

        existing_egress = @egress_stops.map(&:first).to_set
        @gateway_ids.each do |sid|
          stop = @graph.stops[sid]
          next unless %w[ferry flight].include?(stop["kind"].to_s)

          if near_place?(stop, @destination, 15_000) && !existing_egress.include?(sid)
            dist = Geometry.meters(stop["lat"], stop["lon"], @destination["lat"], @destination["lon"])
            @egress_stops << [ sid, dist ]
            existing_egress << sid
          end
        end
      end

      private

      def prepare_pruning!
        return if @graph.nil? || @origin.nil? || @destination.nil?

        @od_meters = Geometry.meters(@origin["lat"], @origin["lon"], @destination["lat"], @destination["lon"])
        @restrict_local_bus = @od_meters > LONG_HAUL_METERS
        pad_meters = [ [ @od_meters * 0.55 + 8_000, CORRIDOR_PAD_METERS ].min, 12_000 ].max
        mid_lat = (@origin["lat"].to_f + @destination["lat"].to_f) / 2.0
        lat_pad = pad_meters / 111_320.0
        lon_pad = pad_meters / (111_320.0 * Math.cos(mid_lat * Math::PI / 180).abs.clamp(0.2, 1.0))
        @min_lat = [ @origin["lat"].to_f, @destination["lat"].to_f ].min - lat_pad
        @max_lat = [ @origin["lat"].to_f, @destination["lat"].to_f ].max + lat_pad
        @min_lon = [ @origin["lon"].to_f, @destination["lon"].to_f ].min - lon_pad
        @max_lon = [ @origin["lon"].to_f, @destination["lon"].to_f ].max + lon_pad
        @gateway_ids = Set.new
        prepare_island_gateways!

        return unless @restrict_local_bus

        @access_ids = @graph.stops_near(@origin["lat"], @origin["lon"], LOCAL_BUS_METERS, limit: 80).map(&:first).to_set
        @egress_ids = @graph.stops_near(@destination["lat"], @destination["lon"], LOCAL_BUS_METERS, limit: 80).map(&:first).to_set
        @local_bus_ok = {}
      end

      def prepare_island_gateways!
        water_air = []
        @graph.stops.each_with_index do |stop, id|
          next unless %w[ferry flight].include?(stop["kind"].to_s)

          water_air << id
        end
        return if water_air.empty?

        seed = water_air.select { |id| water_air_seed_terminal?(@graph.stops[id]) }
        return if seed.empty?

        terminals = Set.new(seed)
        @graph.patterns.each do |pattern|
          route = @graph.route_at(pattern)
          next unless %w[ferry flight].include?(route["mode"].to_s)

          stops = pattern["stops"]
          next unless stops.any? { |sid| terminals.include?(sid) }

          stops.each { |sid| terminals << sid }
        end

        terminals.each do |sid|
          stop = @graph.stops[sid]
          lat = stop["lat"].to_f
          lon = stop["lon"].to_f
          @min_lat = [ @min_lat, lat - ISLAND_GATEWAY_PAD_DEG ].min
          @max_lat = [ @max_lat, lat + ISLAND_GATEWAY_PAD_DEG ].max
          @min_lon = [ @min_lon, lon - ISLAND_GATEWAY_PAD_DEG ].min
          @max_lon = [ @max_lon, lon + ISLAND_GATEWAY_PAD_DEG ].max
          @gateway_ids << sid
          @graph.stops_near(lat, lon, LOCAL_BUS_METERS, limit: 48).each do |id, _dist|
            @gateway_ids << id
          end
        end
      end

      def water_air_seed_terminal?(stop)
        # Catch harbor + airport that share an island (馬公商港 ↔ 馬公機場 ~6 km).
        return true if near_place?(stop, @origin, 12_000) || near_place?(stop, @destination, 12_000)

        od_hints = island_hints_in(@origin["name"]) | island_hints_in(@destination["name"])
        return false if od_hints.empty?

        stop_hints = island_hints_in(stop["name"])
        od_hints.intersect?(stop_hints)
      end

      def near_place?(stop, place, meters = Geometry::ACCESS_METERS * 3)
        Geometry.meters(stop["lat"], stop["lon"], place["lat"], place["lon"]) <= meters
      end

      def island_hints_in(name)
        raw = Geometry.normalize(name.to_s)
        return Set.new if raw.blank?

        ISLAND_NAME_HINTS.select { |hint| raw.include?(Geometry.normalize(hint)) }.to_set
      end

      def island_name_hint?(name)
        island_hints_in(name).any?
      end

      def island_trip?
        @gateway_ids&.any? || island_name_hint?(@origin&.dig("name")) || island_name_hint?(@destination&.dig("name"))
      end

      def collect_itineraries
        found = []
        return found unless @graph && @graph.stops.any?

        profiles_for_search.each do |profile|
          itinerary = search(profile)
          next if itinerary.nil?
          next if found.any? { |item| item["signature"] == itinerary["signature"] }

          found << itinerary
          tighten_prune_clock!(itinerary)
        end
        found
      end

      def profiles_for_search
        # Long-haul less-walking rarely differs from earliest and costs a full RAPTOR.
        return PROFILES.reject { |profile| profile["id"] == "less_walking" } if @restrict_local_bus

        PROFILES
      end

      def tighten_prune_clock!(itinerary)
        return if itinerary.nil? || itinerary["profile"] == "walk"

        arrive = @depart_min + itinerary["duration_minutes"].to_i
        ceiling = arrive + PRUNE_SLACK_MINUTES
        @prune_clock = @prune_clock.nil? ? ceiling : [ @prune_clock, ceiling ].min
      end

      # When HSR/TRA wins, still surface highway coach (and TRA if only HSR).
      # Island O/D: always try to show both 渡輪 and 飛機 when both exist.
      def diversify_trunk_modes(found)
        return found if @graph.nil? || @graph.stops.empty? || found.length >= RESULT_CAP

        modes = trunk_modes_in(found)
        if island_trip?
          unless modes.include?("ferry")
            append_alternate(found, blocked_modes: %w[flight], profile_id: "alternate") do |itinerary|
              trunk_modes_in([ itinerary ]).include?("ferry")
            end
          end
          unless trunk_modes_in(found).include?("flight")
            append_alternate(found, blocked_modes: %w[ferry], profile_id: "alternate") do |itinerary|
              trunk_modes_in([ itinerary ]).include?("flight")
            end
          end
        end

        modes = trunk_modes_in(found)
        return found unless (modes & %w[hsr rail]).any?

        # Coach even when HSR is fastest — hide rail trunks so intercity bus can win.
        unless modes.include?("bus")
          append_alternate(found, blocked_modes: %w[hsr rail flight], profile_id: "coach") do |itinerary|
            trunk_modes_in([ itinerary ]).include?("bus")
          end
        end

        # TRA alternative when the only long-haul option was HSR.
        if trunk_modes_in(found).include?("hsr") && !trunk_modes_in(found).include?("rail")
          append_alternate(found, blocked_modes: %w[hsr flight], profile_id: "alternate") do |itinerary|
            trunk_modes_in([ itinerary ]).include?("rail")
          end
        end

        found
      end

      # When profiles collapse to one path, hide those routes and search once more.
      def diversify(found)
        return found if found.length >= RESULT_CAP || @graph.nil? || @graph.stops.empty?

        blocked = route_ids_in(found)
        return found if blocked.empty?

        append_alternate(found, blocked_routes: blocked, profile_id: "alternate")
        found
      end

      def append_alternate(found, profile_id:, blocked_modes: nil, blocked_routes: nil)
        return if found.length >= RESULT_CAP

        with_relaxed_prune do
          @blocked_modes = blocked_modes && Set.new(blocked_modes)
          @blocked_routes = blocked_routes && Set.new(blocked_routes)
          itinerary = search(PROFILES.first.merge("id" => profile_id))
          next if itinerary.nil?
          next if found.any? { |item| item["signature"] == itinerary["signature"] }
          next if block_given? && !yield(itinerary)

          found << itinerary
        end
      ensure
        @blocked_modes = nil
        @blocked_routes = nil
      end

      def with_relaxed_prune
        previous_prune = @prune_clock
        previous_latest = @latest
        @prune_clock = nil
        # Slow island ferries (and coaches) often board after the first 3h window
        # that a flight/HSR already filled.
        @latest = @depart_min + DAY_HORIZON
        yield
      ensure
        @prune_clock = previous_prune
        @latest = previous_latest
      end

      def route_ids_in(itineraries)
        Array(itineraries).each_with_object(Set.new) do |item, set|
          Array(item["legs"]).each do |leg|
            next unless leg["kind"] == "ride"

            id = leg["route_id"].to_s
            set << id if id.present?
          end
        end
      end

      def trunk_modes_in(itineraries)
        Array(itineraries).each_with_object(Set.new) do |item, set|
          Array(item["legs"]).each do |leg|
            next unless leg["kind"] == "ride"

            mode = leg["mode"].to_s
            if %w[hsr rail ferry flight].include?(mode) || (mode == "bus" && leg["minutes"].to_i >= 90)
              set << mode
            end
          end
        end
      end

      def search(profile)
        @profile = profile
        @service_cache = {}
        marked = prune_marked(seed_access)
        marked = prune_marked((marked + footpaths(marked)).uniq)
        consider_destination
        MAX_ROUNDS.times do
          break if marked.empty?

          @boarding = Array.new(@graph.stops.length)
          marked.each { |id| @boarding[id] = @best[id] }
          improved = []
          queue = {}
          marked.each do |stop_id|
            @graph.serving[stop_id].each do |pattern_index, offset|
              next unless pattern_usable?(pattern_index)

              current = queue[pattern_index]
              queue[pattern_index] = offset if current.nil? || offset < current
            end
          end
          queue.each do |pattern_index, from_offset|
            scan_pattern(pattern_index, from_offset, improved)
          end
          marked = prune_marked((improved + footpaths(improved)).uniq)
          consider_destination
          # Once we have a destination, drop labels that cannot beat it.
          marked = prune_marked(marked)
        end
        build_itinerary
      end

      def arrival_limit
        limits = [ @dest&.dig(:clock), @prune_clock ].compact
        limits.min
      end

      def prune_marked(stop_ids)
        limit = arrival_limit
        return stop_ids if limit.nil?

        stop_ids.select do |id|
          label = @best[id]
          label && label[:clock] < limit
        end
      end

      def blocked_pattern?(pattern_index)
        route = @graph.route_at(@graph.patterns[pattern_index])
        return true if @blocked_routes&.include?(route["id"].to_s)
        return true if @blocked_modes&.include?(route["mode"].to_s)

        false
      end

      def pattern_usable?(pattern_index)
        return false if blocked_pattern?(pattern_index)
        return true unless @restrict_local_bus

        route = @graph.route_at(@graph.patterns[pattern_index])
        return true unless route["mode"] == "bus"
        return true if route["id"].to_s.start_with?("inter_city")

        local_bus_pattern_ok?(pattern_index)
      end

      def local_bus_pattern_ok?(pattern_index)
        cached = @local_bus_ok[pattern_index]
        return cached unless cached.nil?

        stops = @graph.patterns[pattern_index]["stops"]
        @local_bus_ok[pattern_index] = stops.any? { |sid|
          @access_ids.include?(sid) || @egress_ids.include?(sid) || @gateway_ids.include?(sid)
        }
      end

      def local_bus_board_allowed?(pattern_index, stop_id, label)
        return true unless @restrict_local_bus

        route = @graph.route_at(@graph.patterns[pattern_index])
        return true unless route["mode"] == "bus"
        return true if route["id"].to_s.start_with?("inter_city")

        # First mile near origin, last mile near destination, or feeder to an
        # island ferry / airport gateway after a trunk ride.
        return true if @access_ids.include?(stop_id)
        return true if label[:rides].positive? && @egress_ids.include?(stop_id)
        return true if label[:rides].positive? && @gateway_ids.include?(stop_id)

        false
      end

      def seed_access
        @best = Array.new(@graph.stops.length)
        @dest = nil
        marked = []
        @graph.stops_near(@origin["lat"], @origin["lon"], Geometry::ACCESS_METERS).each do |id, distance|
          walk = Geometry.walk_minutes(distance)
          relax(id, clock: @depart_min + walk, walk:, rides: 0, pred_kind: "access", pred: { "kind" => "access", "walk" => walk })
          marked << id
        end
        marked
      end

      # Classic RAPTOR: walk each pattern once, catching the earliest trip (or
      # headway) as boarding options appear — O(stops × trips), not O(stops² × trips).
      def scan_pattern(pattern_index, from_offset, improved)
        return if blocked_pattern?(pattern_index)

        pattern = @graph.patterns[pattern_index]
        services = cached_services(pattern_index, pattern)
        return if services.empty?

        trips = services.flat_map { |service| service["trips"] }
        headways = services.flat_map { |service| service["headways"] }
        stops = pattern["stops"]
        scan_trips(pattern_index, stops, from_offset, trips, improved) if trips.any?
        scan_headways(pattern_index, stops, from_offset, headways, improved) if headways.any?
      end

      def scan_trips(pattern_index, stops, from_offset, trips, improved)
        trip = nil
        delta = 0
        board_stop = nil
        board_index = nil
        board_label = nil
        board_dep = nil
        board_ready = nil
        dest_limit = arrival_limit

        (from_offset...stops.length).each do |offset|
          stop_id = stops[offset]

          if trip
            arrival = trip["times"][offset] + delta
            if arrival >= board_dep && (dest_limit.nil? || arrival < dest_limit)
              if relax_ride(stop_id, arrival, board_label, board_stop, pattern_index, board_index, offset, board_dep, trip:, delta:, ready: board_ready)
                improved << stop_id
              end
            end
          end

          label = @boarding[stop_id]
          next if label.nil?
          next unless local_bus_board_allowed?(pattern_index, stop_id, label)

          ready = label[:pred_kind] == "ride" ? label[:clock] + MIN_TRANSFER : label[:clock]
          best_dep = nil
          best_trip = nil
          best_delta = nil
          trips.each do |candidate|
            base = candidate["times"][offset]
            next if base.nil?

            dep = candidate_departure(base, ready)
            next if dep.nil?
            next if dest_limit && dep >= dest_limit

            if best_dep.nil? || dep < best_dep
              best_dep = dep
              best_trip = candidate
              best_delta = dep - base
            end
          end
          next if best_dep.nil?

          if trip.nil?
            trip = best_trip
            delta = best_delta
            board_stop = stop_id
            board_index = offset
            board_label = label
            board_dep = best_dep
            board_ready = ready
          else
            continuing = trip["times"][offset] + delta
            if best_dep < continuing
              trip = best_trip
              delta = best_delta
              board_stop = stop_id
              board_index = offset
              board_label = label
              board_dep = best_dep
              board_ready = ready
            end
          end
        end
      end

      def scan_headways(pattern_index, stops, from_offset, headways, improved)
        boarded = nil
        dest_limit = arrival_limit

        (from_offset...stops.length).each do |offset|
          stop_id = stops[offset]

          if boarded
            arrival = boarded[:dep] + boarded[:ride][boarded[:index]...offset].sum
            if dest_limit.nil? || arrival < dest_limit
              if relax_ride(stop_id, arrival, boarded[:label], boarded[:stop], pattern_index, boarded[:index], offset, boarded[:dep], headway: boarded[:every], ready: boarded[:ready])
                improved << stop_id
              end
            end
          end

          label = @boarding[stop_id]
          next if label.nil?
          next unless local_bus_board_allowed?(pattern_index, stop_id, label)

          ready = label[:pred_kind] == "ride" ? label[:clock] + MIN_TRANSFER : label[:clock]
          best_dep = nil
          best_band = nil
          headways.each do |band|
            dep = next_headway(ready, band)
            next if dep.nil?
            next if dest_limit && dep >= dest_limit

            if best_dep.nil? || dep < best_dep
              best_dep = dep
              best_band = band
            end
          end
          next if best_dep.nil?

          ride = Array(best_band["ride"]).map(&:to_i)
          continuing = boarded && (boarded[:dep] + boarded[:ride][boarded[:index]...offset].sum)
          if boarded.nil? || best_dep < continuing
            boarded = {
              label:,
              stop: stop_id,
              index: offset,
              dep: best_dep,
              ride:,
              every: best_band["every"],
              ready:
            }
          end
        end
      end

      def relax_ride(stop_id, clock, board, board_stop, pattern_index, board_index, alight_index, dep, trip: nil, delta: 0, headway: nil, ready: nil)
        pred = {
          "kind" => "ride",
          "from" => board_stop,
          "pattern" => pattern_index,
          "board_index" => board_index,
          "alight_index" => alight_index,
          "dep" => dep,
          "arr" => clock,
          "ready" => ready
        }
        if trip
          pred["train"] = trip["train"]
          pred["times"] = trip["times"]
          pred["delta"] = delta
        end
        pred["headway"] = headway if headway
        relax(stop_id, clock:, walk: board[:walk], rides: board[:rides] + 1, pred_kind: "ride", pred:)
      end

      def footpaths(stop_ids)
        reached = []
        stop_ids.uniq.each do |stop_id|
          label = @best[stop_id]
          next if label.nil?

          @graph.foot[stop_id].each do |target, minutes|
            clock = label[:clock] + minutes
            next unless relax(
              target,
              clock:,
              walk: label[:walk] + minutes,
              rides: label[:rides],
              pred_kind: "walk",
              pred: { "kind" => "walk", "from" => stop_id, "minutes" => minutes }
            )

            reached << target
          end
        end
        reached
      end

      def consider_destination
        Array(@egress_stops).each do |id, distance|
          label = @best[id]
          next if label.nil?

          walk = Geometry.walk_minutes(distance)
          clock = label[:clock] + walk
          walk_total = label[:walk] + walk
          rides = label[:rides]
          transfers = [ rides - 1, 0 ].max
          score = clock + (@profile[:walk_weight] - 1) * walk_total + @profile[:transfer_penalty] * transfers
          next unless @dest.nil? || score < @dest[:score] || (score == @dest[:score] && clock < @dest[:clock])

          @dest = { clock:, walk: walk_total, rides:, score:, from: id, egress: walk }
        end
      end

      def relax(stop_id, clock:, walk:, rides:, pred_kind:, pred:)
        limit = arrival_limit
        return false if limit && clock >= limit

        stop = @graph.stops[stop_id]
        lat = stop["lat"].to_f
        lon = stop["lon"].to_f
        return false if lat < @min_lat || lat > @max_lat || lon < @min_lon || lon > @max_lon

        transfers = [ rides - 1, 0 ].max
        score = clock + (@profile[:walk_weight] - 1) * walk + @profile[:transfer_penalty] * transfers
        current = @best[stop_id]
        return false if current && (score > current[:score] || (score == current[:score] && clock >= current[:clock]))

        @best[stop_id] = { clock:, walk:, rides:, score:, pred_kind:, pred:, stop_id: }
        true
      end

      def build_itinerary
        return nil if @dest.nil?

        legs = []
        if @dest[:egress].positive?
          stop = @graph.stops[@dest[:from]]
          legs.unshift(walk_leg(stop, @destination, @dest[:clock] - @dest[:egress], @dest[:clock]))
        end
        cursor = @dest[:from]
        while cursor
          label = @best[cursor]
          pred = label[:pred]
          case pred["kind"]
          when "access"
            if pred["walk"].to_i.positive?
              stop = @graph.stops[cursor]
              legs.unshift(walk_leg(@origin, stop, @depart_min, @depart_min + pred["walk"]))
            end
            break
          when "walk"
            from = @graph.stops[pred["from"]]
            to = @graph.stops[cursor]
            legs.unshift(walk_leg(from, to, label[:clock] - pred["minutes"], label[:clock]))
            cursor = pred["from"]
          when "ride"
            legs.unshift(ride_leg(pred))
            cursor = pred["from"]
          else
            break
          end
        end
        package(collapse_rail_legs(legs), @profile["id"], @dest[:clock])
      end

      # TRA often hops 縱貫→山線→台東 as separate patterns; show one 台鐵 leg and
      # concatenate every corridor segment that was ridden.
      def collapse_rail_legs(legs)
        result = []
        index = 0
        while index < legs.length
          leg = legs[index]
          unless leg["kind"] == "ride" && leg["mode"] == "rail"
            result << leg
            index += 1
            next
          end

          merged = leg.deep_dup
          index += 1
          while index < legs.length
            nxt = legs[index]
            if nxt["kind"] == "walk" && legs[index + 1] && legs[index + 1]["kind"] == "ride" && legs[index + 1]["mode"] == "rail"
              index += 1
              next
            end
            break unless nxt["kind"] == "ride" && nxt["mode"] == "rail"

            merge_rail_leg!(merged, nxt)
            index += 1
          end
          result << decorate_rail_leg!(merged)
        end
        result
      end

      def merge_rail_leg!(into, other)
        into["to"] = other["to"]
        into["alight_at"] = other["alight_at"]
        into["minutes"] = minutes_between(into["board_at"], into["alight_at"])
        into["geometry"] = concat_latlngs(into["geometry"], other["geometry"])
        if into["stops"].is_a?(Array) && other["stops"].is_a?(Array)
          into["stops"] = into["stops"] + other["stops"].drop(1)
        elsif other["stops"].is_a?(Array)
          into["stops"] = other["stops"]
        end
        if into["train_number"].present? && into["train_number"] == other["train_number"]
          # through-running: keep the shared train and its departure list
        elsif other["train_number"].present? && into["train_number"].blank?
          into["train_number"] = other["train_number"]
          into["departures"] = other["departures"] if other["departures"]
        end
        into["route_id"] = [ into["route_id"], other["route_id"] ].compact.join("+")
      end

      def decorate_rail_leg!(leg)
        leg["name"] = I18n.t("map.itinerary.kinds.rail", default: "台鐵")
        leg["color"] ||= "#003366"
        leg
      end

      def concat_latlngs(left, right)
        a = Array(left)
        b = Array(right)
        return b if a.empty?
        return a if b.empty?

        if a.last.is_a?(Array) && b.first.is_a?(Array) && a.last[0] == b.first[0] && a.last[1] == b.first[1]
          a + b.drop(1)
        else
          a + b
        end
      end

      def minutes_between(from_iso, to_iso)
        start = Time.zone.parse(from_iso.to_s) rescue nil
        finish = Time.zone.parse(to_iso.to_s) rescue nil
        return 0 unless start && finish

        ((finish - start) / 60).round
      end

      def ride_leg(pred)
        pattern = @graph.patterns[pred["pattern"]]
        route = @graph.route_at(pattern)
        ids = pattern["stops"][pred["board_index"]..pred["alight_index"]]
        points = ids.map { |id| @graph.stops[id] }
        from = points.first
        to = points.last
        geometry = Geometry.clip_geojson(route["geojson"], from["lat"], from["lon"], to["lat"], to["lon"])
        geometry ||= points.map { |stop| [ stop["lat"], stop["lon"] ] }
        name = route["mode"] == "rail" ? I18n.t("map.itinerary.kinds.rail", default: "台鐵") : route["name"]
        leg = {
          "kind" => "ride",
          "mode" => route["mode"],
          "name" => name,
          "route_id" => route["id"],
          "color" => route["color"],
          "from" => place_point(from),
          "to" => place_point(to),
          "board_at" => iso(pred["dep"]),
          "alight_at" => iso(pred["arr"]),
          "minutes" => pred["arr"] - pred["dep"],
          "geometry" => geometry
        }
        leg["line_name"] = route["name"] if route["mode"] == "rail" && route["name"].present?
        leg["train_number"] = pred["train"] if pred["train"].present?
        leg["headway_minutes"] = pred["headway"] if pred["headway"]
        if pred["times"].is_a?(Array)
          delta = pred["delta"].to_i
          leg["stops"] = points.each_with_index.map do |stop, index|
            { "name" => stop["name"], "time" => iso(pred["times"][pred["board_index"] + index] + delta) }
          end
        end
        departures = listed_departures(pattern, pred)
        if departures.any?
          leg["departures"] = departures.first(DEPARTURE_CAP)
          omitted = departures.length - leg["departures"].length
          leg["departures_omitted"] = omitted if omitted.positive?
        end
        leg
      end

      def listed_departures(pattern, pred)
        rows = listed_trip_departures(pattern, pred)
        rows = listed_headway_departures(pattern, pred) if rows.empty?
        rows
      end

      def listed_trip_departures(pattern, pred)
        return [] unless pred["times"].is_a?(Array)

        ready = pred["ready"] || pred["dep"]
        horizon = @depart_min + DAY_HORIZON
        rows = []
        active_services(pattern).each do |service|
          Array(service["trips"]).each do |trip|
            times = trip["times"]
            base = times[pred["board_index"]]
            next if base.nil?

            [ 0, 1440 ].each do |shift|
              departure = base + shift
              arrival = times[pred["alight_index"]] + shift
              next if departure < ready || departure > horizon || arrival < departure

              rows << {
                "train_number" => trip["train"],
                "board_at" => iso(departure),
                "alight_at" => iso(arrival),
                "chosen" => trip["train"] == pred["train"] && departure == pred["dep"]
              }
            end
          end
        end
        rows.uniq { |row| [ row["train_number"], row["board_at"] ] }.sort_by { |row| row["board_at"] }
      end

      def listed_headway_departures(pattern, pred)
        ride_minutes = pred["arr"].to_i - pred["dep"].to_i
        return [] if ride_minutes <= 0

        ready = pred["ready"] || pred["dep"]
        horizon = @depart_min + DAY_HORIZON
        rows = []
        active_services(pattern).each do |service|
          Array(service["headways"]).each do |band|
            every = band["every"].to_i
            start_min = band["start"].to_i
            finish = band["end"].to_i
            next if every <= 0 || finish < start_min

            clock = start_min
            clock += every while clock < ready
            while clock <= finish && clock <= horizon && rows.length < DEPARTURE_CAP
              rows << {
                "board_at" => iso(clock),
                "alight_at" => iso(clock + ride_minutes),
                "chosen" => clock == pred["dep"]
              }
              clock += every
            end
          end
        end
        rows.uniq { |row| row["board_at"] }.sort_by { |row| row["board_at"] }
      end

      def walk_leg(from, to, depart_min, arrive_min)
        {
          "kind" => "walk",
          "mode" => "walk",
          "name" => I18n.t("map.itinerary.walk"),
          "from" => place_point(from),
          "to" => place_point(to),
          "board_at" => iso(depart_min),
          "alight_at" => iso(arrive_min),
          "minutes" => arrive_min - depart_min,
          "geometry" => [ [ from["lat"], from["lon"] ], [ to["lat"], to["lon"] ] ]
        }
      end

      def direct_walk
        distance = Geometry.meters(@origin["lat"], @origin["lon"], @destination["lat"], @destination["lon"])
        return nil if distance > WALK_ONLY_METERS

        minutes = Geometry.walk_minutes(distance)
        return nil if minutes <= 0

        package(
          [ walk_leg(@origin, @destination, @depart_min, @depart_min + minutes) ],
          "walk",
          @depart_min + minutes
        )
      end

      def package(legs, profile, arrive_min)
        return nil if legs.empty?

        arrive = arrive_min
        rides = legs.count { |leg| leg["kind"] == "ride" }
        {
          "profile" => profile,
          "depart_at" => iso(@depart_min),
          "arrive_at" => iso(arrive),
          "duration_minutes" => arrive - @depart_min,
          "transfers" => [ rides - 1, 0 ].max,
          "walk_minutes" => legs.sum { |leg| leg["kind"] == "walk" ? leg["minutes"].to_i : 0 },
          "legs" => legs,
          "signature" => legs.select { |leg| leg["kind"] == "ride" }.map { |leg| "#{leg['route_id']}:#{leg['from']['name']}:#{leg['to']['name']}" }.join("|").presence || "walk"
        }
      end

      def place_point(point)
        { "name" => point["name"].to_s, "lat" => point["lat"].to_f, "lon" => point["lon"].to_f }
      end

      def iso(minutes)
        day = @date + (minutes / 1440)
        clock = minutes % 1440
        Time.zone.local(day.year, day.month, day.day, clock / 60, clock % 60).iso8601
      end

      def cached_services(pattern_index, pattern)
        @service_cache[pattern_index] ||= active_services(pattern)
      end

      def active_services(pattern)
        pattern["services"].filter_map do |code, body|
          body if service_active?(code, @date)
        end
      end

      def service_active?(code, date)
        return true if code == "daily"
        return code == "date_#{date.iso8601}" if code.start_with?("date_")
        return ServiceCalendarResolver.fingerprint_matches_date?(code, date) if code.start_with?("sd_")
        return date.saturday? || date.sunday? if code == "holiday"

        ServiceCalendarResolver.weekday_simple_code_for_date(date) == code
      end

      def candidate_departure(time, ready)
        return nil if time.nil?

        [ 0, 1440 ].each do |shift|
          departure = time + shift
          return departure if departure >= ready && departure <= @latest
        end
        nil
      end

      def next_headway(ready, band)
        start_min = band["start"]
        finish = band["end"]
        every = band["every"]
        return nil if every <= 0 || finish < start_min

        departure = ready <= start_min ? start_min : start_min + ((ready - start_min).to_f / every).ceil * every
        return nil if departure > finish || departure > @latest

        departure
      end
    end
  end
end
