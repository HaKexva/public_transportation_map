# frozen_string_literal: true

require "json"
require "set"

module Transit
  module Itinerary
    # Turns rail trips, metro headways, bus timetables, ferry/flight catalogs,
    # and out-of-station links into a Graph. Query time only reads that graph.
    class Compiler
      WEEKDAY_KEYS = %w[Monday Tuesday Wednesday Thursday Friday].freeze
      TRANSFER_MINUTES = {
        "passage" => 4,
        "fare_discount" => 6,
        "walk_transfer" => 8
      }.freeze
      SAME_PLACE_MINUTES = 2
      NEARBY_CAP = 8
      MODE_COLORS = {
        "bus" => "#2563eb",
        "metro" => "#0070bd",
        "rail" => "#004B87",
        "hsr" => "#DB5325",
        "ferry" => "#0891b2",
        "flight" => FlightScheduleCatalog::COLOR
      }.freeze

      class << self
        def write!(path: Graph.path)
          graph = from_database
          graph.write(path)
          graph
        end

        def from_database
          patterns = []
          patterns.concat(schedule_patterns)
          patterns.concat(headway_patterns(skip_route_directions: timed_route_directions(patterns)))
          patterns.concat(bus_patterns)
          patterns.concat(ferry_patterns)
          patterns.concat(flight_patterns)
          aliases = {}
          patterns.each do |pattern|
            Array(pattern[:stops]).each do |stop|
              Array(stop[:aliases]).each { |alias_key| aliases[alias_key] = stop[:key] }
            end
          end
          build(patterns:, transfers: transfer_edges(transfer_document, aliases))
        end

        def build(patterns:, transfers: [])
          stops = []
          by_key = {}
          routes = []

          Array(patterns).each do |pattern|
            stop_ids = []
            kept_indexes = []
            Array(pattern[:stops]).each_with_index do |stop, index|
              key = stop[:key].to_s
              next if key.blank?

              unless by_key.key?(key)
                by_key[key] = stops.length
                stops << {
                  "name" => stop[:name].to_s,
                  "name_en" => stop[:name_en].to_s,
                  "lat" => stop[:lat].to_f,
                  "lon" => stop[:lon].to_f,
                  "kind" => (stop[:kind] || pattern[:mode]).to_s,
                  "key" => key
                }
              end
              next if stop_ids.last == by_key[key]

              stop_ids << by_key[key]
              kept_indexes << index
            end
            next if stop_ids.length < 2

            services = normalize_pattern_services(pattern[:services], stop_ids, stops, pattern[:mode], kept_indexes)
            next if services.empty?

            routes << {
              "id" => pattern[:id].to_s,
              "name" => pattern[:name].to_s,
              "name_en" => pattern[:name_en].to_s,
              "mode" => pattern[:mode].to_s,
              "color" => pattern[:color].presence || MODE_COLORS[pattern[:mode].to_s] || "#2563eb",
              "geojson" => pattern[:geojson].to_s,
              "patterns" => [ { "stops" => stop_ids, "services" => services } ]
            }
          end

          edges = {}
          Array(transfers).each do |edge|
            from = by_key[edge[:from_key].to_s]
            to = by_key[edge[:to_key].to_s]
            next if from.nil? || to.nil? || from == to

            add_edge(edges, from, to, edge[:minutes].to_i, explicit: true)
            add_edge(edges, to, from, edge[:minutes].to_i, explicit: true)
          end
          link_nearby(stops, edges)
          link_water_air_hubs(stops, edges)

          Graph.new(
            "stops" => stops,
            "routes" => routes,
            "transfers" => edges.map { |(from, to), body| [ from, to, body[:minutes] ] }
          )
        end

        def bus_patterns_for(city_id:, route_name:, schedules:, stops_by_uid:, sequence_uids: {}, color: nil, geojson: nil, route_id: nil)
          Array(schedules).group_by { |row| row["Direction"].to_i }.filter_map do |direction, rows|
            trips_by_code = Hash.new { |hash, key| hash[key] = [] }
            headways_by_code = Hash.new { |hash, key| hash[key] = [] }
            stop_defs = stop_defs_from_timetables(rows, stops_by_uid)
            if stop_defs.nil?
              uids = Array(sequence_uids[direction] || sequence_uids[direction.to_s])
              stop_defs = collapse_defs(uids.filter_map { |uid| stops_by_uid[uid.to_s] })
            end
            next if stop_defs.length < 2

            rows.each do |row|
              Array(row["Timetables"]).each do |trip|
                built = timed_stops(Array(trip["StopTimes"]), stops_by_uid)
                built ||= origin_trip(Array(trip["StopTimes"]), stop_defs)
                next if built.nil?
                next unless same_keys?(stop_defs, built[:stops])

                service_codes(trip["ServiceDay"]).each do |code|
                  trips_by_code[code] << built[:times]
                end
              end

              Array(row["Frequencys"] || row["Frequencies"]).each do |band|
                every = band["MaxHeadwayMins"].to_i
                every = band["MinHeadwayMins"].to_i if every <= 0
                start_min = minutes_of(band["StartTime"])
                end_min = minutes_of(band["EndTime"])
                next if every <= 0 || start_min.nil? || end_min.nil? || end_min <= start_min

                service_codes(band["ServiceDay"]).each do |code|
                  headways_by_code[code] << { start: start_min, end: end_min, every: every }
                end
              end
            end

            services = {}
            codes = (trips_by_code.keys + headways_by_code.keys).uniq
            codes.each do |code|
              trips = trips_by_code[code].uniq
              headways = trips.empty? ? headways_by_code[code] : []
              next if trips.empty? && headways.empty?

              services[code] = { trips: trips, headways: headways }
            end
            next if services.empty?

            {
              id: route_id.presence || "#{city_id}:#{route_name}:#{direction}",
              name: route_name.to_s,
              mode: "bus",
              color: color,
              geojson: geojson,
              stops: stop_defs,
              services: services
            }
          end
        end

        def ferry_patterns
          Geojson::FerryCatalog::FALLBACK_STATIONS_BY_SLUG.filter_map do |slug, stations|
            entry = FerryScheduleCatalog.fetch(slug)
            next if entry.nil?

            line = Geojson::FerryCatalog::LINES.find { |item| item.slug == slug }
            stop_defs = stations.map { |station| ferry_stop(station) }
            patterns = []
            patterns.concat(ferry_headway_patterns(slug, line, stop_defs, entry[:headways]))
            patterns.concat(ferry_trip_patterns(slug, line, stop_defs, entry[:trips]))
            patterns
          end.flatten
        end

        def flight_patterns
          FlightScheduleCatalog.routes.flat_map do |slug, entry|
            from = FlightScheduleCatalog.airport(entry[:from])
            to = FlightScheduleCatalog.airport(entry[:to])
            next [] if from.nil? || to.nil?

            stop_defs = [ flight_stop(from), flight_stop(to) ]
            flight_trip_patterns(slug, entry, stop_defs)
          end
        end

        def transfer_edges(document, aliases)
          Array(document).filter_map do |row|
            endpoints = Array(row["endpoints"])
            next if endpoints.length < 2

            from = aliases["#{endpoints[0]['route_id']}:#{endpoints[0]['ref']}"]
            to = aliases["#{endpoints[1]['route_id']}:#{endpoints[1]['ref']}"]
            next if from.blank? || to.blank?

            { from_key: from, to_key: to, minutes: TRANSFER_MINUTES.fetch(row["kind"].to_s, 6) }
          end
        end

        def patterns_from_schedule_trips(trips, coords:)
          buckets = {}
          each_record(trips) do |trip|
            route = trip.transit_route
            next if route.nil?

            ordered = trip.trip_stop_times.sort_by(&:stop_sequence)
            stops = []
            times = []
            ordered.each do |stop_time|
              ref = stop_time.station_ref.to_s
              coord = coord_for(coords, route, ref)
              next if coord.nil?

              clock = minutes_of(stop_time.departure_time || stop_time.arrival_time)
              next if clock.nil?

              stops << rail_stop(route, ref, coord, name_for(route, ref, coords))
              times << clock
            end
            collapsed = collapse_timed(stops, times)
            next if collapsed.nil?

            code = trip.service_calendar&.code.to_s
            code = "daily" if code.blank?
            key = [ route.id, trip.direction.to_s, collapsed[:stops].map { |stop| stop[:key] } ]
            bucket = buckets[key] ||= {
              id: "#{route.system_id}:#{route.route_id}:#{trip.direction}",
              name: route.name,
              name_en: route.name_en,
              mode: mode_for(route.system_id),
              color: route.color,
              geojson: route.geojson_path,
              stops: collapsed[:stops],
              services: Hash.new { |hash, service| hash[service] = { trips: [], headways: [] } }
            }
            bucket[:services][code][:trips] << { train: trip.train_number.to_s.presence, times: collapsed[:times] }
          end
          buckets.values
        end

        def patterns_from_headway_rules(rules, coords:, skip_route_directions: [])
          skipped = skip_route_directions.to_set
          patterns = Array(rules).filter_map do |rule|
            route = rule.transit_route
            next if route.nil?
            next if skipped.include?([ route.id, rule.direction.to_s ])

            stations, reverse_order = stations_for_direction(route, rule.direction)
            stops = stations.filter_map do |station|
              ref = station.station_ref.to_s
              coord = coord_for(coords, route, ref)
              next if coord.nil?

              rail_stop(route, ref, coord, station.name.presence || name_for(route, ref, coords))
            end
            stops.reverse! if reverse_order
            stops = collapse_defs(stops)
            next if stops.length < 2

            start_min = minutes_of(rule.starts_at)
            end_min = minutes_of(rule.ends_at)
            every = rule.interval_seconds.to_i / 60
            next if start_min.nil? || end_min.nil? || every <= 0 || end_min <= start_min

            code = rule.service_calendar&.code.to_s
            code = "daily" if code.blank?
            {
              id: "#{route.system_id}:#{route.route_id}:#{rule.direction}:headway",
              name: route.name,
              name_en: route.name_en,
              mode: mode_for(route.system_id),
              color: route.color,
              geojson: route.geojson_path,
              stops: stops,
              services: {
                code => { trips: [], headways: [ { start: start_min, end: end_min, every: every } ] }
              }
            }
          end
          mirror_missing_headway_directions(patterns)
        end

        # Metro schedule dumps often only store one headway direction. Mirror the
        # opposite so RAPTOR can ride both ways with the same frequency bands.
        # Each outbound band is its own pattern with the same id; mirror every band.
        def mirror_missing_headway_directions(patterns)
          present_ids = patterns.map { |pattern| pattern[:id].to_s }.to_set
          extras = []
          patterns.group_by { |pattern| pattern[:id].to_s }.each do |id, group|
            mirrored_id = mirror_headway_pattern_id(id)
            next if mirrored_id.nil? || present_ids.include?(mirrored_id)

            group.each do |pattern|
              extras << pattern.merge(
                id: mirrored_id,
                stops: Array(pattern[:stops]).reverse
              )
            end
            present_ids << mirrored_id
          end
          patterns + extras
        end

        def mirror_headway_pattern_id(id)
          return id.sub(":outbound:headway", ":inbound:headway") if id.include?(":outbound:headway")
          return id.sub(":inbound:headway", ":outbound:headway") if id.include?(":inbound:headway")
          return id.sub(":forward:headway", ":reverse:headway") if id.include?(":forward:headway")
          return id.sub(":reverse:headway", ":forward:headway") if id.include?(":reverse:headway")

          nil
        end

        def minutes_of(value)
          return nil if value.nil?
          return value.to_i if value.is_a?(Numeric)

          text = value.respond_to?(:strftime) ? value.strftime("%H:%M") : value.to_s
          parts = text.split(":")
          return nil if parts.length < 2

          parts[0].to_i * 60 + parts[1].to_i
        end

        def service_codes(service_day)
          return [ "daily" ] unless service_day.is_a?(Hash)

          codes = []
          codes << "weekday" if WEEKDAY_KEYS.all? { |key| ServiceDayMapper.active?(service_day, key) }
          codes << "saturday" if ServiceDayMapper.active?(service_day, "Saturday")
          codes << "sunday" if ServiceDayMapper.active?(service_day, "Sunday")
          codes << "holiday" if ServiceDayMapper.active?(service_day, "NationalHolidays") && codes.empty?
          return [ "daily" ] if codes.empty?
          return [ "daily" ] if codes.sort == %w[saturday sunday weekday]

          codes.uniq
        end

        def sequence_from_geojson(path, direction)
          data = JSON.parse(File.read(path))
          Array(data["features"]).filter_map do |feature|
            props = feature["properties"] || {}
            next unless props["feature_type"] == "station"
            next unless props["direction"].to_i == direction.to_i

            props["ref"].to_s.presence
          end
        rescue JSON::ParserError, Errno::ENOENT
          []
        end

        private

        def each_record(records, &block)
          if records.respond_to?(:find_each)
            records.find_each(batch_size: 500, &block)
          else
            records.each(&block)
          end
        end

        def schedule_patterns
          return [] unless defined?(ScheduleTrip)

          trips = ScheduleTrip.joins(:schedule_dataset).merge(ScheduleDataset.active)
            .includes(:trip_stop_times, :service_calendar, :transit_route)
          patterns_from_schedule_trips(trips, coords: :geojson)
        end

        def headway_patterns(skip_route_directions:)
          return [] unless defined?(HeadwayRule)

          rules = HeadwayRule.joins(:schedule_dataset).merge(ScheduleDataset.active)
            .includes(:service_calendar, :transit_route)
          patterns_from_headway_rules(rules, coords: :geojson, skip_route_directions:)
        end

        def timed_route_directions(patterns)
          patterns.filter_map do |pattern|
            id = pattern[:id].to_s
            next unless id.match?(/\A[^:]+:[^:]+:/)

            parts = id.split(":")
            next if parts.last == "headway"

            route = TransitRoute.find_by(system_id: parts[0], route_id: parts[1])
            [ route.id, parts[2] ] if route
          end
        end

        def bus_patterns
          return [] unless defined?(BusRouteTimetable)

          uids = bus_directory
          manifest = bus_manifest_index
          sequence_cache = {}
          patterns = []
          BusRouteTimetable.find_each do |row|
            entry = manifest[[ row.city_id.to_s, row.route_name.to_s]]
            geojson = entry && entry["file"]
            sequence = {}
            if geojson.present? && sequence_needed?(row.schedules)
              path = Rails.root.join("public#{geojson}")
              sequence_cache[path.to_s] ||= {}
              [ 0, 1 ].each do |direction|
                sequence_cache[path.to_s][direction] ||= sequence_from_geojson(path, direction)
                sequence[direction] = sequence_cache[path.to_s][direction]
              end
            end
            patterns.concat(
              bus_patterns_for(
                city_id: row.city_id,
                route_name: row.route_name,
                schedules: row.schedules,
                stops_by_uid: uids,
                sequence_uids: sequence,
                color: entry && entry["color"],
                geojson: geojson,
                route_id: entry && entry["id"]
              )
            )
          rescue StandardError => error
            warn "itinerary bus skip #{row.city_id} #{row.route_name}: #{error.message}"
          end
          patterns
        end

        # Taipei / New Taipei / Taichung dumps often only list the origin
        # departure. Load the GeoJSON stop order so we can synthesize the rest
        # (and so frequency-only rows have a pattern at all).
        def sequence_needed?(schedules)
          Array(schedules).any? do |row|
            Array(row["Timetables"]).none? { |trip| Array(trip["StopTimes"]).length >= 2 }
          end
        end

        # Every StopUID in each `_stop_routes.json` group — the search index
        # only keeps one representative UID per group, which drops most TDX
        # poles from timetable → graph matching.
        def bus_directory
          records = []
          root = Geojson::BusLayout.bus_root
          Dir.glob(root.join("**/#{Geojson::BusStopIndexWriter::INDEX_FILENAME}")).sort.each do |file|
            subdir = Pathname.new(file).relative_path_from(root).each_filename.first.to_s
            payload = JSON.parse(File.read(file))
            groups = payload.is_a?(Hash) ? payload["groups"] : nil
            next unless groups.is_a?(Hash)

            groups.each do |key, group|
              next unless group.is_a?(Hash)

              records << { subdir:, key: key.to_s, group: }
            end
          rescue JSON::ParserError, ArgumentError
            next
          end

          host_for = {}
          records.each do |row|
            peer = row[:group]["shelter_of"]
            next unless peer.is_a?(Hash) && peer["subdir"].present? && peer["key"].present?

            host_for["#{row[:subdir]}:#{row[:key]}"] = "#{peer["subdir"]}:#{peer["key"]}"
          end

          entries = {}
          records.each do |row|
            id = "#{row[:subdir]}:#{row[:key]}"
            next if host_for.key?(id)

            group = row[:group]
            name = group["name"].to_s
            lat = group["lat"]
            lon = group["lon"]
            next if name.blank? || !lat.is_a?(Numeric) || !lon.is_a?(Numeric)

            entries[id] = {
              key: "bus:#{id}",
              name: name,
              name_en: group["name_en"].to_s,
              lat: lat.to_f,
              lon: lon.to_f,
              kind: "bus"
            }
          end

          uids = {}
          records.sort_by { |row| host_for.key?("#{row[:subdir]}:#{row[:key]}") ? 1 : 0 }.each do |row|
            id = "#{row[:subdir]}:#{row[:key]}"
            entry = entries[host_for[id] || id]
            next unless entry

            Array(row[:group]["stops"]).each do |uid|
              uid = uid.to_s
              next if uid.blank?

              uids[uid] ||= entry
            end
          end
          uids
        end

        def bus_manifest_index
          path = Rails.root.join("public/geojson/bus/manifest.json")
          return {} unless path.exist?

          data = JSON.parse(path.read)
          Array(data["bus"]).each_with_object({}) do |entry, index|
            city = entry["city_id"].to_s
            [ entry["name"], entry["ref"], entry["id"] ].each do |key|
              next if key.blank?

              index[[ city, key.to_s ]] ||= entry
            end
          end
        rescue JSON::ParserError
          {}
        end

        def transfer_document
          path = Rails.root.join("public/geojson/out_of_station_transfers.json")
          return [] unless path.exist?

          JSON.parse(path.read)
        rescue JSON::ParserError
          []
        end

        def ferry_stop(station)
          {
            key: format("ferry:%.4f:%.4f", station[:lat].to_f, station[:lon].to_f),
            name: station[:name],
            name_en: station[:name_en],
            lat: station[:lat].to_f,
            lon: station[:lon].to_f,
            kind: "ferry",
            aliases: []
          }
        end

        def flight_stop(airport)
          {
            key: format("flight:%.4f:%.4f", airport[:lat].to_f, airport[:lon].to_f),
            name: airport[:name],
            name_en: airport[:name_en],
            lat: airport[:lat].to_f,
            lon: airport[:lon].to_f,
            kind: "flight",
            aliases: []
          }
        end

        def flight_trip_patterns(slug, entry, stop_defs)
          grouped = Hash.new { |hash, key| hash[key] = Hash.new { |services, code| services[code] = [] } }
          Array(entry[:trips]).each do |trip|
            direction = trip[:direction].to_s
            stops = direction == "reverse" ? stop_defs.reverse : stop_defs
            times = increasing(Array(trip[:times]).map { |clock| minutes_of(clock) })
            next if times.nil? || times.length != stops.length

            grouped[direction][trip[:calendar].to_s] << times
          end
          grouped.map do |direction, services|
            stops = direction == "reverse" ? stop_defs.reverse : stop_defs
            {
              id: "#{slug}:#{direction}",
              name: entry[:name] || slug,
              name_en: entry[:name_en],
              mode: "flight",
              color: FlightScheduleCatalog::COLOR,
              geojson: nil,
              stops: stops,
              services: services.transform_values { |times| { trips: times, headways: [] } }
            }
          end
        end

        def ferry_headway_patterns(slug, line, stop_defs, headways)
          Array(headways).flat_map do |band|
            directions = band[:direction].to_s == "both" ? %w[forward reverse] : [ band[:direction].to_s ]
            directions.filter_map do |direction|
              stops = direction == "reverse" ? stop_defs.reverse : stop_defs
              ride = Array(band[:ride])
              ride = ride.reverse if direction == "reverse"
              next if ride.length != stops.length - 1

              {
                id: "#{slug}:#{direction}",
                name: line&.name || slug,
                name_en: line&.name_en,
                mode: "ferry",
                color: Geojson::FerryCatalog::COLOR,
                geojson: "/geojson/ferry/#{slug}.geojson",
                stops: stops,
                services: {
                  band[:calendar].to_s => {
                    trips: [],
                    headways: [ {
                      start: minutes_of(band[:start]),
                      end: minutes_of(band[:end]),
                      every: band[:every].to_i,
                      ride: ride
                    } ]
                  }
                }
              }
            end
          end
        end

        def ferry_trip_patterns(slug, line, stop_defs, trips)
          grouped = Hash.new { |hash, key| hash[key] = Hash.new { |services, code| services[code] = [] } }
          Array(trips).each do |trip|
            direction = trip[:direction].to_s
            stops = direction == "reverse" ? stop_defs.reverse : stop_defs
            times = increasing(Array(trip[:times]).map { |clock| minutes_of(clock) })
            next if times.nil? || times.length != stops.length

            grouped[direction][trip[:calendar].to_s] << times
          end
          grouped.map do |direction, services|
            stops = direction == "reverse" ? stop_defs.reverse : stop_defs
            {
              id: "#{slug}:#{direction}",
              name: line&.name || slug,
              name_en: line&.name_en,
              mode: "ferry",
              color: Geojson::FerryCatalog::COLOR,
              geojson: "/geojson/ferry/#{slug}.geojson",
              stops: stops,
              services: services.transform_values { |times| { trips: times, headways: [] } }
            }
          end
        end

        def rail_stop(route, ref, coord, name)
          {
            key: "rail:#{route.system_id}:#{ref}",
            name: name.presence || ref,
            name_en: "",
            lat: coord[0].to_f,
            lon: coord[1].to_f,
            kind: mode_for(route.system_id),
            aliases: [ "#{route.route_id}:#{ref}" ]
          }
        end

        def coord_for(coords, route, ref)
          if coords == :geojson
            GeojsonStationCoords.lookup(route, ref)
          elsif coords.respond_to?(:call)
            coords.call(route, ref)
          else
            coords[[ route.system_id.to_s, ref ]] || coords[ref]
          end
        end

        def name_for(route, ref, coords)
          return nil unless coords == :geojson

          GeojsonStationCoords.lookup_name(route, ref)
        end

        def stations_for_direction(route, direction)
          # Reuse the map vehicle orderer: transfer stations are often appended
          # out of sequence, so BL/R/G/O numbers beat stop_sequence.
          query = VehiclePositionQuery.new(at: Time.current, route_ids: [ route.route_id ])
          stations = query.ordered_route_stations(route, direction.to_s)
          return [ stations, false ] if stations.length >= 2

          rows = route.transit_route_stations.ordered.to_a
          wanted = reverse_direction?(direction) ? "reverse" : "forward"
          picked = rows.select { |station| station.direction == wanted }
          return [ picked, false ] if picked.any?

          picked = rows.select { |station| station.direction == "both" }
          picked = rows if picked.empty?
          [ picked, reverse_direction?(direction) ]
        end

        def reverse_direction?(direction)
          %w[inbound reverse 1 northbound].include?(direction.to_s)
        end

        def mode_for(system_id)
          case system_id.to_s
          when "hsr" then "hsr"
          when "ferry" then "ferry"
          when /metro/ then "metro"
          else "rail"
          end
        end

        def stop_defs_from_timetables(rows, stops_by_uid)
          Array(rows).each do |row|
            Array(row["Timetables"]).each do |trip|
              built = timed_stops(Array(trip["StopTimes"]), stops_by_uid)
              return built[:stops] if built
            end
          end
          nil
        end

        def timed_stops(stop_times, stops_by_uid)
          ordered = stop_times.sort_by { |stop| stop["StopSequence"].to_i }
          defs = []
          times = []
          ordered.each do |stop|
            uid = stop["StopUID"].to_s.presence || stop["StopID"].to_s
            found = stops_by_uid[uid]
            next if found.nil?

            clock = minutes_of(stop["DepartureTime"] || stop["ArrivalTime"])
            next if clock.nil?

            defs << found
            times << clock
          end
          collapse_timed(defs, times)
        end

        # TDX city schedules that only publish the first stop's clock: keep that
        # departure and estimate the remaining arrivals from stop spacing.
        def origin_trip(stop_times, stop_defs)
          return nil if stop_defs.length < 2

          ordered = stop_times.sort_by { |stop| stop["StopSequence"].to_i }
          return nil unless ordered.length == 1

          clock = minutes_of(ordered.first["DepartureTime"] || ordered.first["ArrivalTime"])
          return nil if clock.nil?

          times = [ clock ]
          stop_defs.each_cons(2) do |from, to|
            times << times.last + Geometry.ride_minutes(from[:lat], from[:lon], to[:lat], to[:lon], "bus")
          end
          { stops: stop_defs, times: times }
        end

        def collapse_timed(stops, times)
          defs = []
          kept = []
          stops.each_with_index do |stop, index|
            next if defs.last && defs.last[:key] == stop[:key]

            defs << stop
            kept << times[index]
          end
          return nil if defs.length < 2

          { stops: defs, times: increasing(kept) }
        end

        def collapse_defs(stops)
          stops.each_with_object([]) do |stop, list|
            list << stop unless list.last && list.last[:key] == stop[:key]
          end
        end

        def same_keys?(left, right)
          left.map { |stop| stop[:key] } == right.map { |stop| stop[:key] }
        end

        def coerce_trip(trip, stop_count, kept_indexes)
          if trip.is_a?(Hash)
            train = (trip[:train] || trip["train"]).to_s.presence
            times = Array(trip[:times] || trip["times"])
          else
            train = nil
            times = Array(trip)
          end
          times = kept_indexes.map { |index| times[index] } if times.length != stop_count
          times = increasing(times.map { |value| value.nil? ? nil : value.to_i })
          return nil if times.nil? || times.length != stop_count

          { "train" => train, "times" => times }
        end

        def increasing(times)
          return nil if times.any?(&:nil?)

          out = []
          times.each do |time|
            time += 1440 while out.last && time < out.last
            out << time
          end
          out
        end

        def normalize_pattern_services(services, stop_ids, stops, mode, kept_indexes)
          Array(services).each_with_object({}) do |(code, body), out|
            next unless body.is_a?(Hash)

            trips = Array(body[:trips] || body["trips"]).filter_map do |trip|
              coerce_trip(trip, stop_ids.length, kept_indexes)
            end.uniq
            headways = Array(body[:headways] || body["headways"]).filter_map do |band|
              start_min = (band[:start] || band["start"]).to_i
              end_min = (band[:end] || band["end"]).to_i
              every = (band[:every] || band["every"]).to_i
              next if every <= 0 || end_min <= start_min

              ride = Array(band[:ride] || band["ride"]).map(&:to_i)
              if ride.length != stop_ids.length - 1
                ride = stop_ids.each_cons(2).map do |from, to|
                  Geometry.ride_minutes(stops[from]["lat"], stops[from]["lon"], stops[to]["lat"], stops[to]["lon"], mode)
                end
              end
              { "start" => start_min, "end" => end_min, "every" => every, "ride" => ride }
            end
            next if trips.empty? && headways.empty?

            out[code.to_s] = { "trips" => trips, "headways" => headways }
          end
        end

        def add_edge(edges, from, to, minutes, explicit:)
          minutes = [ minutes, 1 ].max
          current = edges[[ from, to ]]
          if current.nil?
            edges[[ from, to ]] = { minutes:, explicit: }
          elsif explicit && !current[:explicit]
            edges[[ from, to ]] = { minutes:, explicit: true }
          elsif explicit == current[:explicit] && minutes < current[:minutes]
            edges[[ from, to ]] = { minutes:, explicit: }
          end
        end

        def link_nearby(stops, edges)
          grid = Hash.new { |hash, key| hash[key] = [] }
          stops.each_with_index do |stop, id|
            lat_i, lon_i = Geometry.cell_index(stop["lat"], stop["lon"])
            grid["#{lat_i}:#{lon_i}"] << id
          end
          radius = (Geometry::TRANSFER_METERS / Geometry::CELL_METERS).ceil + 1
          stops.each_with_index do |stop, id|
            lat_i, lon_i = Geometry.cell_index(stop["lat"], stop["lon"])
            nearby = []
            (lat_i - radius..lat_i + radius).each do |row|
              (lon_i - radius..lon_i + radius).each do |col|
                grid["#{row}:#{col}"].each do |other|
                  next if other == id

                  distance = Geometry.meters(stop["lat"], stop["lon"], stops[other]["lat"], stops[other]["lon"])
                  next if distance > Geometry::TRANSFER_METERS

                  minutes = distance < Geometry::SAME_PLACE_METERS ? SAME_PLACE_MINUTES : Geometry.walk_minutes(distance)
                  nearby << [ other, minutes ]
                end
              end
            end
            nearby.sort_by(&:last).first(NEARBY_CAP).each do |other, minutes|
              add_edge(edges, id, other, minutes, explicit: false)
            end
          end
        end

        FERRY_HUB_METERS = 1_500
        # Domestic airports are often several km from TRA/HSR (台東豐年、小港).
        FLIGHT_HUB_METERS = 6_000
        FLIGHT_HUB_CAP_MINUTES = 45
        ISLAND_TERMINAL_PAIR_METERS = 12_000
        ISLAND_TERMINAL_PAIR_MINUTES = 25

        # Airports/piers often sit farther from MRT/TRA than city bus poles; also
        # pair harbor ↔ airport on the same island as a fixed shuttle transfer.
        def link_water_air_hubs(stops, edges)
          hubs = stops.each_with_index.select { |stop, _id| %w[ferry flight].include?(stop["kind"].to_s) }
          hubs.each do |hub, hub_id|
            hub_kind = hub["kind"].to_s
            hub_limit = hub_kind == "flight" ? FLIGHT_HUB_METERS : FERRY_HUB_METERS
            candidates = []
            stops.each_with_index do |stop, id|
              next if id == hub_id

              kind = stop["kind"].to_s
              distance = Geometry.meters(hub["lat"], hub["lon"], stop["lat"], stop["lon"])
              if %w[metro rail hsr bus].include?(kind) && distance <= hub_limit
                minutes = Geometry.walk_minutes(distance)
                minutes = [ minutes, FLIGHT_HUB_CAP_MINUTES ].min if hub_kind == "flight"
                candidates << [ id, minutes ]
              elsif %w[ferry flight].include?(kind) && kind != hub_kind && distance <= ISLAND_TERMINAL_PAIR_METERS
                candidates << [ id, ISLAND_TERMINAL_PAIR_MINUTES ]
              end
            end
            candidates.sort_by(&:last).first(NEARBY_CAP * 2).each do |other, minutes|
              add_edge(edges, hub_id, other, minutes, explicit: true)
              add_edge(edges, other, hub_id, minutes, explicit: true)
            end
          end
        end
      end
    end
  end
end
