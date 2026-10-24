# frozen_string_literal: true

module Geojson
  # Weekend / holiday suspensions from TDX Schedule ServiceDay flags, stored on
  # each bus GeoJSON as properties.off_days (e.g. ["saturday", "sunday"]) so
  # route lists can flag them without a TDX call per route. Also stores
  # properties.daily_trips (weekday departures in the busier direction), which
  # the map uses to shade frequent routes darker.
  #
  #   bin/rails geojson:bus_service_days
  module BusServiceDays
    WEEKDAY_KEYS = %w[Monday Tuesday Wednesday Thursday Friday].freeze
    OFF_DAY_KEYS = { "saturday" => "Saturday", "sunday" => "Sunday", "holiday" => "NationalHolidays" }.freeze

    module_function

    # Days a weekday route does not run, or [] when it runs every day (or only
    # at weekends, or has no ServiceDay data at all).
    def off_days(rows)
      days = Array(rows).flat_map { |row| Array(row["Frequencys"]) + Array(row["Timetables"]) }
        .filter_map { |entry| entry["ServiceDay"] if entry["ServiceDay"].is_a?(Hash) }
      return [] if days.empty?
      return [] unless days.any? { |day| WEEKDAY_KEYS.any? { |key| day[key].to_i == 1 } }

      OFF_DAY_KEYS.filter_map do |code, key|
        next unless days.any? { |day| day.key?(key) }

        code if days.none? { |day| day[key].to_i == 1 }
      end
    end

    # Weekday departures in the busier direction: listed Timetables trips plus
    # the trips implied by Frequencys headway bands. nil without data.
    def daily_trips(rows)
      per_direction = Array(rows).group_by { |row| row["Direction"].to_i }.values.map do |direction_rows|
        trips = direction_rows.flat_map { |row| Array(row["Timetables"]) }.select { |trip| weekday?(trip) }
          .filter_map { |trip| trip.dig("StopTimes", 0, "DepartureTime") }.uniq.size
        bands = direction_rows.flat_map { |row| Array(row["Frequencys"]) }.select { |band| weekday?(band) }
          .uniq { |band| band.values_at("StartTime", "EndTime", "MinHeadwayMins", "MaxHeadwayMins") }
        trips + bands.sum { |band| band_trips(band) }
      end
      busiest = per_direction.max
      busiest&.positive? ? busiest.round : nil
    end

    def weekday?(entry)
      service = entry["ServiceDay"]
      !service.is_a?(Hash) || service["Wednesday"].to_i == 1
    end

    def band_trips(band)
      start = clock_minutes(band["StartTime"])
      finish = clock_minutes(band["EndTime"])
      headways = [ band["MinHeadwayMins"], band["MaxHeadwayMins"] ].map(&:to_f).select(&:positive?)
      return 0 if start.nil? || finish.nil? || headways.empty?

      finish += 24 * 60 if finish <= start
      (finish - start) / (headways.sum / headways.size)
    end

    def clock_minutes(value)
      hours, minutes = value.to_s.scan(/\d+/).first(2).map(&:to_i)
      hours && minutes ? (hours * 60) + minutes : nil
    end

    # Schedule rows cut to the trips leaving inside (or outside) "08:00-21:30":
    # Timetables trips by first departure, Frequencys bands clipped to the window.
    def clip_rows(rows, hours, inside:)
      from, to = hours.to_s.split("-").map { |value| clock_minutes(value) }
      return rows unless from && to

      keep = ->(minutes) { minutes && (minutes >= from && minutes < to) == inside }
      Array(rows).map do |row|
        trips = Array(row["Timetables"]).select { |trip| keep.(clock_minutes(trip.dig("StopTimes", 0, "DepartureTime"))) }
        bands = Array(row["Frequencys"]).flat_map { |band| clip_band(band, from, to, inside:) }
        row.merge("Timetables" => trips, "Frequencys" => bands)
      end
    end

    def clip_band(band, from, to, inside:)
      start = clock_minutes(band["StartTime"])
      finish = clock_minutes(band["EndTime"])
      return [] unless start && finish

      finish += 24 * 60 if finish <= start
      ranges = inside ? [ [ from, to ] ] : [ [ 0, from ], [ to, 48 * 60 ] ]
      ranges.filter_map do |low, high|
        a = [ start, low ].max
        b = [ finish, high ].min
        band.merge("StartTime" => clock(a), "EndTime" => clock(b)) if b > a
      end
    end

    def clock(minutes)
      format("%02d:%02d", (minutes / 60) % 24, minutes % 60)
    end

    def refresh!(client: Transit::TdxClient.new(ignore_breaker: true), bus_root: Geojson::BusLayout.bus_root, city_ids: nil, apply: true)
      files = Dir.glob(bus_root.join("**/*.geojson")).reject { |path| File.basename(path).start_with?("_") }
      by_city = files.group_by { |path| JSON.parse(File.read(path)).dig("properties", "city_id") }

      updated = 0
      Geojson::BusCatalog.cities.each do |city|
        next if city_ids.present? && !city_ids.include?(city.id)

        paths = by_city[city.id]
        next if paths.blank?

        rows = client.fetch_all(dataset_path("Schedule", city))
        snapshot_city!(client, city, rows)
        by_name = rows.group_by { |row| zh(row["RouteName"]) }
        changed = apply ? paths.count { |path| apply!(path, by_name, city) } : 0
        updated += changed
        puts "#{city.id}: #{rows.size} schedules, #{changed} files updated"
      rescue Transit::TdxClient::Error => error
        puts "#{city.id}: skipped (#{error.message})"
      end
      updated
    end

    # Same flags from the local TDX snapshot (no API calls).
    def apply_snapshot!(bus_root: Geojson::BusLayout.bus_root)
      Dir.glob(bus_root.join("**/*.geojson")).count do |path|
        next false if File.basename(path).start_with?("_")

        properties = JSON.parse(File.read(path))["properties"] || {}
        city = Geojson::BusCatalog.find(properties["city_id"])
        next false unless city

        ref = properties["ref"].to_s
        by_name = [ ref, ref.sub(/[A-J]\z/i, "") ].uniq.to_h do |name|
          [ name, Transit::BusTdxSnapshot.read(city.id, name)&.dig("schedules").presence ]
        end.compact
        by_name.any? && apply!(path, by_name, city)
      end
    end

    def apply!(path, by_name, city)
      data = JSON.parse(File.read(path))
      properties = data["properties"] ||= {}
      ref = properties["ref"].to_s
      names = [ ref ]
      names << ref.sub(/[A-J]\z/i, "") if city.kind == :intercity
      rows = names.uniq.filter_map { |name| by_name[name] }.first
      return false unless rows

      detour_hours = properties["detour_hours"].presence
      via = detour_hours ? Geojson::BusTimedDetours.base_via(properties["via"]) : properties["via"]
      name = detour_hours ? Geojson::BusTimedDetours.base_name(properties["name"], properties["via"]) : properties["name"]
      subroute = subroute_name(name.presence || ref)
      variant = own_rows(rows, ref:, name:, via:)
      main = rows.select { |row| zh(row["SubRouteName"]) == ref }
      own = variant.presence || main
      if detour_hours
        inside = Geojson::BusTimedDetours.detour?(properties["via"])
        own = clip_rows(own.presence || rows, detour_hours, inside:)
      end
      off = off_days(own.presence || rows)
      window = subroute != ref && variant.any? ? service_window(variant, main) : nil
      trips = daily_trips(own.presence || rows)
      return false if Array(properties["off_days"]) == off && properties["service_window"] == window && properties["daily_trips"] == trips

      { "off_days" => off.presence, "service_window" => window, "daily_trips" => trips }.each do |key, value|
        value ? properties[key] = value : properties.delete(key)
      end
      File.write(path, "#{JSON.pretty_generate(data)}\n")
      true
    end

    # TDX rows (Schedule, SubRoutes, fares) for one drawn variant: its own
    # SubRouteName, the raw name of a relabelled SubRoute ("237延駛政大校區" is
    # "237經政大校區", "249繞駛崁頂" is "249繞崁頂"), for a plain variant
    # (本線, 不繞駛三總) everything except the SubRoutes split from it, and for a plain route with no row of its own name
    # (306(三重) beside 306(大都會)) everything except the split SubRoutes.
    def own_rows(rows, ref:, name:, via: nil)
      splits = Geojson::BusImporter::SUBROUTE_SPLITS
      names = via.present? ? Geojson::BusImporter.split_names_for_main(via) : []
      return rows.reject { |row| names.include?(zh(row["SubRouteName"])) } if names.any?

      raw = Geojson::BusImporter.subroute_split(via)&.first
      wanted = [ subroute_name(name.presence || ref), raw ].compact
      own = rows.select { |row| wanted.include?(zh(row["SubRouteName"])) }
      return own if own.any? || via.present?

      exact = rows.select { |row| zh(row["SubRouteName"]) == ref }
      exact.presence || rows.reject { |row| splits.key?(zh(row["SubRouteName"])) }
    end

    # "216（不繞駛榮總院區）" is TDX SubRouteName "216不繞駛榮總院區".
    def subroute_name(name)
      name.to_s.delete("（）()")
    end

    # A variant that only runs after the main route's last departure (or
    # before its first): { "after" => "22:30" } / { "before" => "06:00" }.
    def service_window(variant_rows, main_rows)
      variant = departure_times(variant_rows)
      main = departure_times(main_rows)
      return nil if variant.empty? || main.empty?

      if variant.min > main.max
        { "after" => variant.min }
      elsif variant.max < main.min
        { "before" => variant.max }
      end
    end

    def departure_times(rows)
      Array(rows).flat_map { |row|
        Array(row["Timetables"]).map { |trip| trip.dig("StopTimes", 0, "DepartureTime") } +
          Array(row["Frequencys"]).flat_map { |frequency| [ frequency["StartTime"], frequency["EndTime"] ] }
      }.filter_map { |time| time.to_s[/\A\d{2}:\d{2}/] }
    end

    # "216（不繞駛榮總院區）" + after 22:30 → "216（22:30後不繞駛榮總院區）".
    def display_name(name, window)
      return name unless window.is_a?(Hash)

      label = window["after"] ? "#{window['after']}後" : window["before"] && "#{window['before']}前"
      return name unless label

      if name.to_s.match?(/（[^（）]*）\z/)
        name.sub(/（([^（）]*)）\z/) { "（#{label}#{Regexp.last_match(1)}）" }
      else
        "#{name}（#{label}）"
      end
    end

    def display_name_en(name, window)
      return name unless window.is_a?(Hash)

      label = window["after"] ? "after #{window['after']}" : window["before"] && "before #{window['before']}"
      return name unless label

      if name.to_s.match?(/\([^()]*\)\z/)
        name.sub(/\(([^()]*)\)\z/) { "(#{label}, #{Regexp.last_match(1)})" }
      else
        "#{name} (#{label})"
      end
    end

    # The same download also feeds the route-details snapshot.
    def snapshot_city!(client, city, schedules)
      routes = client.fetch_all(dataset_path("Route", city))
      fares = begin
        client.fetch_all(dataset_path("RouteFare", city))
      rescue Transit::TdxClient::Error
        []
      end
      Transit::BusTdxSnapshot.write_city!(city.id, schedules:, routes:, fares:)
    end

    def dataset_path(dataset, city)
      city.kind == :intercity ? "v2/Bus/#{dataset}/InterCity" : "v2/Bus/#{dataset}/City/#{city.tdx_city}"
    end

    def zh(value)
      value.is_a?(Hash) ? value["Zh_tw"].to_s : value.to_s
    end
  end
end
