# frozen_string_literal: true

require "digest"

module Geojson
  # Routes that only enter 三總內湖院區 during set hours publish one SubRoute
  # whose path always runs through the campus. Keep that path as the 繞駛三總
  # variant and turn the route's own file into 不繞駛三總 by cutting the campus
  # stretch out (or re-driving it along the road when the bus enters and
  # leaves by different gates). Routes with their own 經三總 / 不經三總
  # SubRoutes (903, 521, 藍20) are split by BusImporter::SUBROUTE_SPLITS.
  module BusTimedDetours
    DETOUR_LABEL = "繞駛三總"
    PLAIN_LABEL = "不繞駛三總"
    DETOUR_EN = "detour via Tri-Service General Hospital"
    PLAIN_EN = "skips Tri-Service General Hospital"
    CAMPUS = { south: 25.0703, north: 25.0735, west: 121.5900, east: 121.5960 }.freeze
    # East of 成功路二段: lines that only run along the road past the gate stay.
    CAMPUS_CORE_WEST = 121.5915
    # 成功路二段 × 民權東路六段: OSM maps the campus service roads, so a bypass
    # between the 民權東路 and 成功路 gates is routed through this junction.
    JUNCTION = [ 121.59085, 25.06896 ].freeze
    JUNCTION_SEARCH_METERS = 800
    # Hours each route enters the campus (TDX/eBus headway notes).
    ROUTES = {
      "Taipei" => {
        "617" => %w[08:00 21:30], "284" => %w[08:00 21:30], "市民小巴10" => %w[08:00 21:30],
        "645" => %w[08:00 21:30], "645副" => %w[08:00 18:00], "278" => %w[08:00 21:30],
        "0東" => %w[08:00 21:30], "紅29" => %w[08:00 21:30], "藍27" => %w[08:00 21:30],
        "28" => %w[08:00 21:30], "551" => %w[08:00 21:30]
      }
    }.freeze
    LABEL_SEPARATOR = "、"
    MIN_DETOUR_METERS = 300
    SAME_GATE_METERS = 80
    MAX_BYPASS_RATIO = 1.6
    STUB_METERS = 30
    STUB_MIN_EXCURSION = 150
    STOP_METERS = 40

    module_function

    def hours_for(city_id, ref)
      ROUTES.dig(city_id.to_s, ref.to_s)
    end

    # "繞駛行善路經金龍寺、繞駛三總" → "繞駛三總"; nil when not split here.
    def label_of(via)
      label = via.to_s.split(LABEL_SEPARATOR).last
      label if [ DETOUR_LABEL, PLAIN_LABEL ].include?(label)
    end

    def detour?(via)
      label_of(via) == DETOUR_LABEL
    end

    # The variant's own label before the 三總 split ("繞駛行善路經金龍寺"), nil
    # for routes that had none.
    def base_via(via)
      parts = via.to_s.split(LABEL_SEPARATOR)
      parts.pop if label_of(via)
      parts.join(LABEL_SEPARATOR).presence
    end

    def base_name(name, via)
      label = label_of(via) or return name
      base = base_via(via)
      ref = name.to_s.sub(/（.*）\z/, "")
      base ? "#{ref}（#{base}）" : ref.presence || name.to_s.delete_suffix("（#{label}）")
    end

    def apply!(bus_root: Geojson::BusLayout.bus_root, router: Geojson::OsmRoadRouter.new)
      Dir.glob(File.join(bus_root, "**", "*.geojson")).sort.count do |path|
        next false if File.basename(path).start_with?("_")

        split!(path, router:)
      rescue JSON::ParserError
        false
      end
    end

    # Writes the 繞駛 variant next to `path` and rewrites `path` as 不繞駛.
    def split!(path, router: Geojson::OsmRoadRouter.new)
      data = JSON.parse(File.read(path))
      properties = data["properties"] || {}
      hours = hours_for(properties["city_id"], properties["ref"])
      return false unless hours && !properties["via"].to_s.include?("三總")

      plain = Marshal.load(Marshal.dump(data))
      return false unless cut_campus!(plain, router)

      slug = "#{properties['id']}_#{Digest::SHA1.hexdigest(DETOUR_LABEL)[0, 10]}"
      variant = relabel(data, slug, DETOUR_LABEL, DETOUR_EN, hours)
      File.write(File.join(File.dirname(path), "#{slug}.geojson"), "#{JSON.pretty_generate(variant)}\n")
      File.write(path, "#{JSON.pretty_generate(relabel(plain, properties['id'], PLAIN_LABEL, PLAIN_EN, hours))}\n")
      true
    end

    def cut_campus!(data, router)
      lines = data["features"].reject { |feature| feature.dig("geometry", "type") == "Point" }
      changed = false
      lines.each do |feature|
        coords = feature.dig("geometry", "coordinates")
        cut = without_campus(coords, router)
        next unless cut

        feature["geometry"]["coordinates"] = cut
        changed = true
      end
      return false unless changed

      by_direction = lines.to_h { |feature| [ feature.dig("properties", "direction"), feature.dig("geometry", "coordinates") ] }
      data["features"].reject! do |feature|
        next false unless feature.dig("geometry", "type") == "Point"

        line = by_direction[feature.dig("properties", "direction")]
        point = feature.dig("geometry", "coordinates")
        line && near_campus?(point) && distance_to_line(point, line) > STOP_METERS
      end
      true
    end

    # The line with each campus loop removed; nil when it never enters.
    def without_campus(coords, router)
      runs = coords.each_index.select { |index| inside?(coords[index]) }.slice_when { |a, b| b > a + 3 }.to_a
      result = coords
      changed = false
      runs.reverse_each do |run|
        from = [ run.first - 1, 0 ].max
        to = [ run.last + 1, coords.length - 1 ].min
        next if path_meters(coords[from..to]) < MIN_DETOUR_METERS
        next unless coords[from..to].any? { |point| point[0] >= CAMPUS_CORE_WEST }

        bypass = if meters(coords[from], coords[to]) <= SAME_GATE_METERS
          []
        else
          # Entering by one gate and leaving by another: rejoin where the line
          # passes closest to the 成功路 × 民權東路 junction on either side, so
          # the plain path stays on the public roads.
          from = nearest_to_junction(coords, from, -1)
          to = nearest_to_junction(coords, to, 1)
          path = bypass_path(router, coords[from], coords[to])
          # The campus can be a shortcut (645 返程: 成功路 gate → 民權東路), so the
          # road path may be longer, but not a wild detour.
          next unless path && path_meters(path) < path_meters(coords[from..to]) * MAX_BYPASS_RATIO

          path
        end
        result = remove_stubs(result[0..from] + bypass + result[to..], from, from + bypass.length + 1)
        result = remove_spikes(result, from)
        changed = true
      end
      changed ? result : nil
    end

    # Index within JUNCTION_SEARCH_METERS of `index` (walking `step` = -1 back,
    # +1 forward) where the line is closest to JUNCTION.
    def nearest_to_junction(coords, index, step)
      best = index
      travelled = 0.0
      cursor = index
      while (following = cursor + step).between?(0, coords.length - 1)
        travelled += meters(coords[cursor], coords[following])
        break if travelled > JUNCTION_SEARCH_METERS

        cursor = following
        best = cursor if meters(coords[cursor], JUNCTION) < meters(coords[best], JUNCTION)
      end
      best
    end

    def bypass_path(router, from, to)
      direct = router.route(from, to)
      return direct if direct && !enters_core?(direct)

      first = router.route(from, JUNCTION)
      second = router.route(JUNCTION, to)
      path = first && second && (first + second.drop(1))
      path unless path.nil? || enters_core?(path)
    end

    def enters_core?(path)
      path.any? { |point| inside?(point) && point[0] >= CAMPUS_CORE_WEST }
    end

    # A bypass snapped onto a one-way side road drives up it and U-turns back
    # (out and back to within STUB_METERS); cut those excursions.
    def remove_stubs(coords, first, last)
      coords = coords.dup
      index = [ first - 3, 0 ].max
      while index < [ last + 3, coords.length - 1 ].min
        back = (index + 2..[ index + 40, coords.length - 1 ].min).find do |j|
          meters(coords[index], coords[j]) < STUB_METERS && path_meters(coords[index..j]) > STUB_MIN_EXCURSION
        end
        if back
          coords.slice!(index + 1...back)
          last -= back - index - 1
        end
        index += 1
      end
      coords
    end

    # Joins can overshoot the turn by a few metres; drop vertices near the
    # join that double back on themselves.
    def remove_spikes(coords, join)
      coords = coords.dup
      loop do
        window = ([ join - 8, 1 ].max..[ join + 40, coords.length - 2 ].min)
        index = window.find { |i| sharp_reversal?(coords[i - 1], coords[i], coords[i + 1]) }
        break unless index

        coords.delete_at(index)
      end
      coords
    end

    def sharp_reversal?(a, b, c)
      return false if meters(a, b) < 0.5 || meters(b, c) < 0.5

      turn = (bearing(b, c) - bearing(a, b) + 540) % 360 - 180
      turn.abs > 150
    end

    def bearing(a, b)
      Math.atan2((b[1] - a[1]) * 111_000, (b[0] - a[0]) * 101_000) * 180 / Math::PI
    end

    def relabel(data, slug, label, label_en, hours)
      data = Marshal.load(Marshal.dump(data))
      properties = data["properties"]
      ref = properties["ref"]
      ref_en = properties["name_en"].to_s.sub(/\s*\(.*\z/, "").presence || ref
      via = [ properties["via"].presence, label ].compact.join(LABEL_SEPARATOR)
      via_en = [ properties["via_en"].presence, label_en ].compact.join(", ")
      name = "#{ref}（#{via}）"
      name_en = "#{ref_en} (#{via_en})"
      data["id"] = slug
      data["name"] = name
      properties.merge!("id" => slug, "name" => name, "name_en" => name_en, "via" => via, "via_en" => via_en,
                        "detour_hours" => hours.join("-"))
      properties.delete("daily_trips")
      data["features"].each do |feature|
        if feature.dig("geometry", "type") == "Point"
          feature["properties"]["line"] = name
        else
          feature["properties"].merge!("name" => name, "name_en" => name_en)
        end
      end
      data
    end

    def inside?(point)
      point[1].between?(CAMPUS[:south], CAMPUS[:north]) && point[0].between?(CAMPUS[:west], CAMPUS[:east])
    end

    # Campus plus the gate stops on 成功路 / 民權東路 (國防醫學中心).
    def near_campus?(point)
      point[1].between?(CAMPUS[:south] - 0.0006, CAMPUS[:north]) && point[0].between?(CAMPUS[:west] - 0.0007, CAMPUS[:east])
    end

    def meters(a, b)
      Math.hypot((a[0] - b[0]) * 101_000, (a[1] - b[1]) * 111_000)
    end

    def path_meters(points)
      points.each_cons(2).sum { |a, b| meters(a, b) }
    end

    def distance_to_line(point, line)
      line.each_cons(2).map { |a, b| segment_meters(point, a, b) }.min || Float::INFINITY
    end

    def segment_meters(point, a, b)
      ax, ay = (a[0] - point[0]) * 101_000, (a[1] - point[1]) * 111_000
      bx, by = (b[0] - point[0]) * 101_000, (b[1] - point[1]) * 111_000
      dx, dy = bx - ax, by - ay
      length = (dx * dx) + (dy * dy)
      t = length.zero? ? 0 : (-((ax * dx) + (ay * dy)) / length).clamp(0, 1)
      Math.hypot(ax + (t * dx), ay + (t * dy))
    end
  end
end
