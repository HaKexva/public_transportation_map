# frozen_string_literal: true

module Transit
  # Service hours, headways / timetables, fares and fare buffer zones for one
  # bus route from the stored TDX Route, Schedule and RouteFare rows
  # (bus_route_timetables), plus the fleet seen on the route (Transit::BusFleet).
  class BusRouteDetailsQuery
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    MAX_DEPARTURES = 240

    WEEKDAYS = %w[Monday Tuesday Wednesday Thursday Friday].freeze
    WEEKEND = %w[Saturday Sunday].freeze

    ROUTE_TYPES = { 11 => "city", 12 => "highway", 13 => "freeway", 14 => "shuttle" }.freeze
    FARE_CLASSES = {
      1 => "adult", 2 => "student", 3 => "child", 4 => "senior",
      5 => "disabled", 6 => "disabled_child", 7 => "disabled_companion", 8 => "group", 9 => "military"
    }.freeze

    def initialize(route_id:, route: nil)
      @route = route || RouteCatalog.find(route_id.to_s)
    end

    def call
      return error_payload("unknown_route") unless @route && @route["city_id"].present?

      @city = Geojson::BusCatalog.find(@route["city_id"])
      return error_payload("unknown_city") unless @city

      details = build
      return details if details[:error]

      fleet = Transit::BusFleet.summary(@route["id"])
      fleet ? details.merge(fleet:) : details
    end

    private

    def error_payload(error)
      { route_id: @route&.dig("id"), error: error }
    end

    def build
      schedules, route, fares = snapshot_rows
      return error_payload("not_found") unless route || schedules&.any?

      details_payload(route:, fares:, schedules:, merged: merged_services)
    end

    # [schedules, route, fares] from the daily TDX snapshot.
    def snapshot_rows
      candidate_names.each do |name|
        snapshot = Transit::BusTdxSnapshot.read(@city.id, name)
        next unless snapshot && (snapshot["schedules"].any? || snapshot["routes"].any?)

        uid = snapshot["schedules"].first&.dig("RouteUID")
        route = snapshot["routes"].find { |row| row["RouteUID"] == uid } || snapshot["routes"].first
        return [ snapshot["schedules"], route, snapshot["fares"] ]
      end
      nil
    end

    def details_payload(route:, fares:, schedules:, merged:)
      route ||= {}
      subroutes = preferred(Array(route["SubRoutes"])) { |sub| zh(sub["SubRouteName"]) }
      hours = service_hours(subroutes)
      route_schedules = preferred(schedules) { |row| zh(row["SubRouteName"]) }
      if (detour_hours = @route["detour_hours"]).present?
        inside = Geojson::BusTimedDetours.detour?(@route["via"])
        route_schedules = Geojson::BusServiceDays.clip_rows(route_schedules, detour_hours, inside:)
      end
      timetable = serialize_schedules(route_schedules)
      merged.each do |label, merged_hours, merged_timetable|
        hours.concat(merged_hours.map { |row| row.merge(label:) })
        timetable.concat(merged_timetable.map { |row| row.merge(label:) })
      end

      {
        route_id: @route["id"],
        at: CLOCK_ZONE.now.iso8601,
        route_type: ROUTE_TYPES[route["BusRouteType"].to_i],
        departure_stop: route["DepartureStopNameZh"].presence,
        destination_stop: route["DestinationStopNameZh"].presence,
        ticket_description: route["TicketPriceDescriptionZh"].presence,
        buffer_zone_description: route["FareBufferZoneDescriptionZh"].presence,
        off_days: Geojson::BusServiceDays.off_days(route_schedules),
        service_hours: hours,
        schedules: timetable,
        fare: serialize_fare(preferred(fares) { |row| row["SubRouteName"].to_s })
      }.compact
    end

    # Night services folded into this route (e.g. 39夜 on 39) keep their own
    # hours and timetable, labelled with their ref.
    def merged_services
      Array(@route["merged_refs"]).filter_map do |ref|
        snapshot = Transit::BusTdxSnapshot.read(@city.id, ref)
        next unless snapshot

        schedules = snapshot["schedules"]
        uid = schedules.first&.dig("RouteUID")
        route = snapshot["routes"].find { |row| row["RouteUID"] == uid } || snapshot["routes"].first
        subroutes = Array(route&.dig("SubRoutes")).select { |sub| zh(sub["SubRouteName"]) == ref }.presence ||
          Array(route&.dig("SubRoutes"))
        rows = schedules.select { |row| zh(row["SubRouteName"]) == ref }.presence || schedules
        next if subroutes.empty? && rows.empty?

        [ ref, service_hours(subroutes), serialize_schedules(rows) ]
      end
    end

    def candidate_names
      names = [ @route["ref"].to_s ]
      names << @route["ref"].to_s.sub(/[A-J]\z/i, "") if @city.kind == :intercity
      names.uniq.reject(&:blank?)
    end

    # Prefer rows for this variant (237本線 / 237延駛政大校區), then the exact
    # public ref (skip 狗狗公車 / 區間 variants).
    def preferred(rows)
      name, via = @route.values_at("name", "via")
      if @route["detour_hours"].present?
        name = Geojson::BusTimedDetours.base_name(name, via)
        via = Geojson::BusTimedDetours.base_via(via)
      end
      own = Geojson::BusServiceDays.own_rows(rows, ref: @route["ref"].to_s, name:, via:)
      return own if own.any? && own.length < rows.length

      exact = rows.select { |row| yield(row) == @route["ref"].to_s }
      exact.presence || rows
    end

    def service_hours(subroutes)
      subroutes.group_by { |sub| sub["Direction"].to_i }.sort.map do |direction, rows|
        sub = rows.first
        {
          direction: direction,
          first: clock(sub["FirstBusTime"]),
          last: clock(sub["LastBusTime"]),
          holiday_first: clock(sub["HolidayFirstBusTime"]),
          holiday_last: clock(sub["HolidayLastBusTime"])
        }.compact
      end.reject { |row| row.keys == [ :direction ] }
    end

    def serialize_schedules(rows)
      rows.group_by { |row| row["Direction"].to_i }.sort.map do |direction, direction_rows|
        frequencies = direction_rows.flat_map { |row| Array(row["Frequencys"]) }
        timetables = direction_rows.flat_map { |row| Array(row["Timetables"]) }
        {
          direction: direction,
          weekday: service_block(frequencies, timetables, WEEKDAYS),
          holiday: service_block(frequencies, timetables, WEEKEND)
        }.compact
      end
    end

    def service_block(frequencies, timetables, days)
      bands = frequencies.select { |row| runs_on?(row, days) }.map { |row|
        {
          start: clock(row["StartTime"]),
          end: clock(row["EndTime"]),
          min_headway: row["MinHeadwayMins"],
          max_headway: row["MaxHeadwayMins"]
        }
      }.uniq.sort_by { |band| band[:start].to_s }

      departures = timetables.select { |row| runs_on?(row, days) }.filter_map { |trip|
        first = Array(trip["StopTimes"]).min_by { |stop| stop["StopSequence"].to_i }
        clock(first&.dig("DepartureTime") || first&.dig("ArrivalTime"))
      }.uniq.sort

      return nil if bands.empty? && departures.empty?

      block = {}
      block[:frequencies] = bands if bands.any?
      if departures.any?
        block[:departures] = departures.first(MAX_DEPARTURES)
        block[:departure_count] = departures.size
        gaps = departures.map { |time| minutes(time) }.each_cons(2).map { |a, b| b - a }.select(&:positive?)
        block[:headway] = { min: gaps.min, max: gaps.max, median: gaps.sort[gaps.size / 2] } if gaps.any?
      end
      block
    end

    def runs_on?(row, days)
      service = row["ServiceDay"]
      return true unless service.is_a?(Hash)

      days.any? { |day| service[day].to_i == 1 }
    end

    def serialize_fare(rows)
      return nil if rows.empty?

      row = rows.first
      section = Array(row["SectionFares"]).first
      od = Array(row["ODFares"])
      stage = Array(row["StageFares"])

      fare = {
        free: row["IsFreeBus"].to_i == 1,
        pricing: if section then "section" elsif od.any? then "od" elsif stage.any? then "stage" end
      }.compact

      if section
        fare[:prices] = fare_prices(Array(section["Fares"]))
        fare[:buffer_zones] = Array(section["BufferZones"]).map { |zone|
          {
            direction: zone["Direction"].to_i,
            from: zone.dig("FareBufferZoneOrigin", "StopName"),
            to: zone.dig("FareBufferZoneDestination", "StopName")
          }
        }.uniq
      elsif od.any? || stage.any?
        adult = (od + stage).flat_map { |entry| Array(entry["Fares"]) }
          .select { |price| price["FareClass"].to_i == 1 && price["TicketType"].to_i == 1 }
          .map { |price| price["Price"].to_i }
          .select(&:positive?)
        fare[:adult_range] = [ adult.min, adult.max ] if adult.any?
      end
      fare
    end

    def fare_prices(fares)
      fares.select { |price| price["TicketType"].to_i == 1 }
        .filter_map { |price|
          label = FARE_CLASSES[price["FareClass"].to_i]
          { fare_class: label, price: price["Price"].to_i } if label && price["Price"].to_i >= 0
        }
        .uniq { |price| price[:fare_class] }
    end

    def clock(value)
      text = value.to_s.strip
      return nil if text.blank?

      text = "#{text[0, 2]}:#{text[2, 2]}" if text.match?(/\A\d{4}\z/)
      text.match?(/\A\d{1,2}:\d{2}\z/) ? text.rjust(5, "0") : nil
    end

    def minutes(time)
      hours, mins = time.split(":").map(&:to_i)
      (hours * 60) + mins
    end

    def zh(value)
      value.is_a?(Hash) ? value["Zh_tw"].to_s : value.to_s
    end
  end
end
