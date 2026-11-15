# frozen_string_literal: true

require "digest"
require "json"

module Geojson
  # One-way TDX routes that are really the two directions of a longer and a
  # shorter line. 795往十分寮 / 795往平溪 leave 木柵; 795往木柵 comes back from
  # either 十分 or 平溪. Draw 795（十分） and 795（平溪）, and cut the shared
  # return so the short line starts at 平溪.
  class BusTerminusLines
    SPECS = {
      "NewTaipei" => [
        {
          "ref" => "795",
          "lines" => [
            {
              "label" => "十分",
              "label_en" => "Shifen",
              "outbound" => "795往十分寮(台灣好行-木柵平溪線)",
              "inbound" => "795往木柵(台灣好行-木柵平溪線)"
            },
            {
              "label" => "平溪",
              "label_en" => "Pingxi",
              "outbound" => "795往平溪(台灣好行-木柵平溪線)",
              "inbound" => "795往木柵(台灣好行-木柵平溪線)",
              "inbound_from" => "平溪"
            }
          ]
        }
      ]
    }.freeze

    def self.apply!(bus_root: Geojson::BusLayout.bus_root, city_id: nil)
      written = []
      SPECS.each do |spec_city, families|
        next if city_id && spec_city != city_id.to_s

        subdir = Geojson::BusLayout.subdir_for(spec_city)
        next if subdir.blank?

        root = bus_root.join(subdir)
        next unless root.exist?

        by_name = index_by_name(root)
        families.each do |family|
          lines = family["lines"]
          sources = lines.flat_map { |line| [ line["outbound"], line["inbound"] ] }.uniq
          next unless sources.all? { |name| by_name[name] }

          lines.each do |line|
            outbound = JSON.parse(File.read(by_name[line["outbound"]]))
            inbound = JSON.parse(File.read(by_name[line["inbound"]]))
            trim_inbound_from!(inbound, line["inbound_from"]) if line["inbound_from"]
            collection = combine(family["ref"], line, outbound, inbound, city_id: spec_city)
            path = by_name[line["outbound"]].dirname.join("#{collection.dig("properties", "id")}.geojson")
            File.write(path, "#{JSON.pretty_generate(collection)}\n")
            written << path
          end
          sources.each { |name| File.delete(by_name[name]) }
        end
      end
      written
    end

    def self.index_by_name(root)
      Dir.glob(root.join("**/*.geojson")).each_with_object({}) do |path, index|
        next if File.basename(path).start_with?("_")

        name = JSON.parse(File.read(path)).dig("properties", "name").to_s
        index[name] = Pathname.new(path) if name.present?
      rescue JSON::ParserError
        next
      end
    end

    # TDX publishes the return as one route whose trips all claim to leave
    # 十分遊客中心. Each operating day has the same number of return trips as
    # outbound trips, in the same order: a 平溪 short turn's return clock is
    # the 平溪 departure, and a 十分寮 trip's return clock is the 十分 departure.
    def self.assign_return_trips(outbound_by_label, return_trips)
      chosen = {}
      service_days.each do |day|
        outbound = outbound_by_label.flat_map { |label, trips|
          Array(trips).select { |trip| runs_on?(trip, day) }.map { |trip| [ departure_clock(trip), label ] }
        }.sort_by(&:first)
        inbound = Array(return_trips).select { |trip| runs_on?(trip, day) }.sort_by { |trip| departure_clock(trip) }
        next unless outbound.size == inbound.size && outbound.size.positive?
        next if outbound.any? { |clock, _label| clock.blank? } || inbound.any? { |trip| departure_clock(trip).blank? }

        inbound.each_with_index do |trip, index|
          ((chosen[trip] ||= {})[day] = outbound[index].last)
        end
      end

      grouped = Hash.new { |hash, label| hash[label] = [] }
      chosen.each do |trip, day_labels|
        day_labels.group_by(&:last).each do |label, pairs|
          copy = JSON.parse(JSON.generate(trip))
          copy["ServiceDay"] = service_days.index_with { |day| pairs.any? { |paired, _label| paired == day } ? 1 : 0 }
          grouped[label] << copy
        end
      end
      grouped
    end

    # [schedules, route, fares] with the return trips for this line on direction 1.
    def self.combined_snapshot(city_id, route)
      return nil unless defined?(Transit::BusTdxSnapshot)

      family = SPECS[city_id.to_s]&.find { |spec|
        spec["ref"] == route["ref"].to_s && spec["lines"].any? { |line| line["label"] == route["via"].to_s }
      }
      return nil unless family

      line = family["lines"].find { |item| item["label"] == route["via"].to_s }
      loaded = family["lines"].filter_map { |item|
        snap = Transit::BusTdxSnapshot.read(city_id, item["outbound"])
        [ item["label"], snap ] if snap
      }
      return nil unless loaded.map(&:first).sort == family["lines"].map { |item| item["label"] }.sort

      inbound = Transit::BusTdxSnapshot.read(city_id, line["inbound"])
      return nil unless inbound

      outbound = loaded.find { |label, _snap| label == line["label"] }.last
      assigned = assign_return_trips(
        loaded.to_h { |label, snap| [ label, snap["schedules"].flat_map { |row| Array(row["Timetables"]) } ] },
        inbound["schedules"].flat_map { |row| Array(row["Timetables"]) }
      )
      trips = assigned[line["label"]] || []
      template = inbound["schedules"].first || {}
      route_row = JSON.parse(JSON.generate(outbound["routes"].first || {}))
      sub_template = route_row["SubRoutes"]&.first || {}
      own_out = outbound["schedules"].flat_map { |row| Array(row["Timetables"]) }
      route_row["SubRoutes"] = [ hours_subroute(sub_template, own_out, 0) ]
      route_row["SubRoutes"] << hours_subroute(sub_template, trips, 1) if trips.any?

      [
        Array(outbound["schedules"]).map { |row| row.merge("Direction" => 0) } +
          [ template.merge("Direction" => 1, "Timetables" => trips) ],
        route_row,
        outbound["fares"]
      ]
    end

    def self.combine(ref, line, outbound, inbound, city_id:)
      label = line["label"]
      name = "#{ref}（#{label}）"
      name_en = "#{ref} (#{line["label_en"]})"
      slug = "#{city_id.underscore}_#{ref}_#{Digest::SHA1.hexdigest(label)[0, 10]}"
      properties = (outbound["properties"] || {}).dup
      %w[id name name_en ref via via_en].each { |key| properties.delete(key) }
      properties.merge!(
        "id" => slug,
        "name" => name,
        "name_en" => name_en,
        "ref" => ref,
        "via" => label,
        "via_en" => line["label_en"],
        "tdx_ref" => line["outbound"]
      )
      {
        "type" => "FeatureCollection",
        "name" => name,
        "properties" => properties,
        "features" => retarget(outbound["features"], 0, name, name_en, ref) +
          retarget(inbound["features"], 1, name, name_en, ref)
      }
    end

    def self.retarget(features, direction, name, name_en, ref)
      Array(features).map do |feature|
        copy = JSON.parse(JSON.generate(feature))
        props = copy["properties"] ||= {}
        props["direction"] = direction
        if props["feature_type"] == "route"
          props["name"] = name
          props["name_en"] = name_en
          props["ref"] = ref
        end
        copy
      end
    end

    # The shared return is published from the far terminus. A short line keeps
    # the path only from `stop_name` onward.
    def self.trim_inbound_from!(data, stop_name)
      return data if stop_name.blank?

      stops = Array(data["features"]).select { |feature|
        feature.dig("geometry", "type") == "Point" && feature.dig("properties", "name") == stop_name
      }
      origin = stops.first&.dig("geometry", "coordinates")
      return data unless origin.is_a?(Array)

      seen = false
      data["features"].reject! do |feature|
        next false unless feature.dig("geometry", "type") == "Point"
        next false if seen

        if feature.dig("properties", "name") == stop_name
          seen = true
          false
        else
          true
        end
      end
      Array(data["features"]).each do |feature|
        next unless feature.dig("geometry", "type") == "LineString"

        coords = feature.dig("geometry", "coordinates")
        start = coords.index { |point| Geojson::BusLoopCloser.meters_between(point, origin) <= 80 }
        start ||= coords.each_with_index.min_by { |point, _index| Geojson::BusLoopCloser.meters_between(point, origin) }&.last
        feature["geometry"]["coordinates"] = coords[start..] if start
      end
      data
    end

    def self.hours_subroute(template, trips, direction)
      sub = template.merge("Direction" => direction)
      { service_days.first(5) => %w[FirstBusTime LastBusTime], service_days.last(2) => %w[HolidayFirstBusTime HolidayLastBusTime] }
        .each do |days, keys|
          clocks = trips.select { |trip| days.any? { |day| trip.dig("ServiceDay", day).to_i == 1 } }
            .filter_map { |trip| departure_clock(trip) }.sort
          next if clocks.empty?

          sub[keys[0]] = clocks.first.tr(":", "")
          sub[keys[1]] = clocks.last.tr(":", "")
        end
      sub
    end

    def self.service_days
      %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday]
    end

    def self.runs_on?(trip, day)
      trip.dig("ServiceDay", day).to_i == 1
    end

    def self.departure_clock(trip)
      stop = Array(trip["StopTimes"]).min_by { |row| row["StopSequence"].to_i }
      (stop&.dig("DepartureTime") || stop&.dig("ArrivalTime")).to_s[/\A\d{2}:\d{2}/]
    end
  end
end
