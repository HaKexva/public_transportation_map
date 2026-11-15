# frozen_string_literal: true

require "digest"

module Geojson
  # Routes that only enter 三總內湖院區 during set hours publish one SubRoute
  # whose path always runs through the campus. That campus path is the main
  # line. The file with the campus cut out is the timed exception
  # （08:00前、21:30後不繞駛三總）. Routes with their own 經三總 / 不經三總
  # SubRoutes (903, 521, 藍20) are split by BusImporter::SUBROUTE_SPLITS,
  # where 經三總 stays the plain route.
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
    # 617副 enters on every trip, including the 07:00 departure, so it is not split.
    ROUTES = {
      "Taipei" => {
        "617" => %w[08:00 21:30], "284" => %w[08:00 21:30],
        "市民小巴10" => %w[08:00 21:30], "645" => %w[08:00 21:30], "645副" => %w[08:00 18:00],
        "278" => %w[08:00 21:30], "0東" => %w[08:00 21:30], "紅29" => %w[08:00 21:30],
        "藍27" => %w[08:00 21:30], "28" => %w[08:00 21:30], "551" => %w[08:00 21:30]
      }
    }.freeze
    # 551 繞駛行善路經金龍寺 only runs at 1510 (inside campus hours), so it has
    # no early/late 不繞駛三總 sibling. Other 551 行善×金龍 combos still split.
    NO_OUTSIDE_VIA = [
      "繞駛行善路經金龍寺"
    ].freeze
    # 繞三總的班次不停福華商場。停福華商場的是不繞三總的班次。
    # 福華若是民權東路上的折返就整段切掉；若路線本來就沿民權開過，只拿掉停靠。
    CAMPUS_SKIP_STOPS = [ "福華商場" ].freeze
    LABEL_SEPARATOR = "、"
    CLOCK_BEFORE = /\A\d{2}:\d{2}前\z/
    CLOCK_AFTER = /\A\d{2}:\d{2}後不繞駛三總\z/
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

    def skip_label(hours)
      from, to = hours
      "#{from}前、#{to}後#{PLAIN_LABEL}"
    end

    def skip_label_en(hours)
      from, to = hours
      "before #{from} and after #{to}, skips Tri-Service General Hospital"
    end

    # "繞駛行善路經金龍寺、繞駛三總" → "繞駛三總". The timed skip is two
    # segments because the label itself contains "、".
    def label_of(via)
      campus_suffix(via)
    end

    def detour?(via)
      label_of(via) == DETOUR_LABEL
    end

    # Trips drawn through the campus (the main line) use the inside hours.
    def inside_hours?(properties)
      case properties["campus_span"]
      when "inside" then true
      when "outside" then false
      else detour?(properties["via"])
      end
    end

    # The variant's own label before the 三總 split ("繞駛行善路經金龍寺"), nil
    # for routes that had none.
    def base_via(via)
      parts = via.to_s.split(LABEL_SEPARATOR)
      suffix = campus_suffix(via)
      parts.pop(suffix.count(LABEL_SEPARATOR) + 1) if suffix
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

        split!(path, router:) || trim_inside_skips!(path)
      rescue JSON::ParserError
        false
      end
    end

    def no_outside_via?(via)
      label = base_via(via).presence || via.to_s
      NO_OUTSIDE_VIA.include?(label)
    end

    # Writes the campus path next to `path` as the main line, and rewrites
    # `path` as the timed skip (08:00前、21:30後不繞駛三總).
    def split!(path, router: Geojson::OsmRoadRouter.new)
      data = JSON.parse(File.read(path))
      properties = data["properties"] || {}
      hours = hours_for(properties["city_id"], properties["ref"])
      return false unless hours
      return false if properties["campus_span"].present? || properties["via"].to_s.include?("三總")

      # Trips that only run inside campus hours keep a single through-campus file.
      if no_outside_via?(properties["via"])
        titled = write_labels!(data, slug: properties["id"], via: properties["via"],
          via_en: properties["via_en"].presence, hours:, span: "inside", keep_trips: true)
        File.write(path, "#{JSON.pretty_generate(titled)}\n")
        return true
      end

      plain = Marshal.load(Marshal.dump(data))
      return false unless cut_campus!(plain, router)

      drop_inside_skips!(data)
      slug = "#{properties['id']}_#{Digest::SHA1.hexdigest(DETOUR_LABEL)[0, 10]}"
      main = write_labels!(data, slug:, via: base_via(properties["via"]), via_en: properties["via_en"].presence, hours:, span: "inside")
      skip = write_labels!(plain, slug: properties["id"], via: timed_via(properties["via"], hours),
        via_en: timed_via_en(properties["via_en"], hours), hours:, span: "outside")
      File.write(File.join(File.dirname(path), "#{slug}.geojson"), "#{JSON.pretty_generate(main)}\n")
      File.write(path, "#{JSON.pretty_generate(skip)}\n")
      true
    end

    # 繞駛三總 becomes the plain route name. 不繞駛三總 with hours becomes
    # "08:00前、21:30後不繞駛三總". Returns false when the file is already titled.
    def retitle!(data)
      properties = data["properties"] || {}
      suffix = campus_suffix(properties["via"])
      return false unless [ DETOUR_LABEL, PLAIN_LABEL ].include?(suffix)

      hours = clock_hours(properties["detour_hours"])
      return false if suffix == PLAIN_LABEL && hours.nil?

      if suffix == DETOUR_LABEL
        via = base_via(properties["via"])
        via_en = strip_hospital_en(properties["via_en"])
        span = hours ? "inside" : nil
      else
        via = timed_via(properties["via"], hours)
        via_en = timed_via_en(properties["via_en"], hours)
        span = "outside"
      end
      data.replace(write_labels!(data, slug: properties["id"], via:, via_en:, hours:, span:, keep_trips: true))
      true
    end

    # Already-split campus files: drop stops the 繞三總 trip does not serve.
    def trim_inside_skips!(path)
      data = JSON.parse(File.read(path))
      return false unless campus_trip?(data)
      return false unless drop_inside_skips!(data)

      File.write(path, "#{JSON.pretty_generate(data)}\n")
      true
    end

    def campus_trip?(data)
      properties = data["properties"] || {}
      return false if properties["campus_span"] == "outside"
      return true if properties["campus_span"] == "inside"
      return false if properties["via"].to_s.match?(/不繞|不經/)

      enters_campus?(data)
    end

    def enters_campus?(data)
      data["features"].any? do |feature|
        next false unless feature.dig("geometry", "type") == "LineString"

        feature.dig("geometry", "coordinates").any? { |point| inside?(point) }
      end
    end

    def drop_inside_skips!(data)
      return false unless campus_trip?(data)

      CAMPUS_SKIP_STOPS.any? { |name| drop_campus_skip_stop!(data, name) }
    end

    # Cut a 福華 out-and-back when the campus trip only doubles back for it,
    # then drop the stop either way.
    def drop_campus_skip_stop!(data, name)
      cut = drop_stop_spur!(data, name)
      removed = false
      data["features"].reject! do |feature|
        next false unless feature.dig("geometry", "type") == "Point"
        next false unless feature.dig("properties", "name") == name

        removed = true
        true
      end
      cut || removed
    end

    # Cut the out-and-back that reaches `name`, then drop the stop if the
    # remaining line no longer passes it.
    def drop_stop_spur!(data, name)
      changed = false
      data["features"].each do |feature|
        next unless feature.dig("geometry", "type") == "LineString"

        direction = feature.dig("properties", "direction")
        line = feature.dig("geometry", "coordinates")
        stops = stations_named(data, name, direction)
        stops.each do |stop|
          cut = without_stop_spur(line, stop.dig("geometry", "coordinates"))
          next unless cut

          feature["geometry"]["coordinates"] = cut
          line = cut
          changed = true
        end
      end

      lines = data["features"].select { |feature| feature.dig("geometry", "type") == "LineString" }
        .to_h { |feature| [ feature.dig("properties", "direction"), feature.dig("geometry", "coordinates") ] }
      data["features"].reject! do |feature|
        next false unless feature.dig("geometry", "type") == "Point"
        next false unless feature.dig("properties", "name") == name

        line = lines[feature.dig("properties", "direction")]
        far = line && distance_to_line(feature.dig("geometry", "coordinates"), line) > STOP_METERS
        changed = true if far
        far
      end
      changed
    end

    def stations_named(data, name, direction)
      data["features"].select do |feature|
        feature.dig("geometry", "type") == "Point" &&
          feature.dig("properties", "name") == name &&
          feature.dig("properties", "direction") == direction
      end
    end

    def without_stop_spur(line, stop)
      return nil if line.length < 4 || stop.nil?

      near = line.each_index.select { |index| meters(line[index], stop) <= STOP_METERS }
      return nil if near.empty?

      # A stop partway along an out-and-back is passed twice. Expand from those
      # two passages so the turnaround past the stop is cut with them. A stop
      # at the bulb has one passage; take the outermost rejoin.
      clusters = near.slice_when { |left, right| right > left + 1 }.to_a
      leave, back = if clusters.length >= 2
        expand_spur(line, clusters.first.last, clusters.last.first)
      else
        outermost_rejoin(line, clusters.first.min)
      end
      return nil unless leave && back && path_meters(line[leave..back]) > STUB_MIN_EXCURSION

      line[0..leave] + line[back..]
    end

    # Walk the two passages outward while they stay on the same out-and-back.
    def expand_spur(line, leave, back)
      while leave.positive? && back < line.length - 1 && meters(line[leave - 1], line[back + 1]) < STUB_METERS
        leave -= 1
        back += 1
      end
      while leave.positive? && meters(line[leave - 1], line[back]) < STUB_METERS
        leave -= 1
      end
      while back < line.length - 1 && meters(line[leave], line[back + 1]) < STUB_METERS
        back += 1
      end
      [ leave, back ]
    end

    def outermost_rejoin(line, tip)
      leave = nil
      back = nil
      tip.downto([ tip - 80, 0 ].max) do |index|
        rejoins = ((tip + 1)...[ tip + 80, line.length ].min).find { |other| meters(line[index], line[other]) < STUB_METERS }
        next unless rejoins && path_meters(line[index..rejoins]) > STUB_MIN_EXCURSION

        leave = index
        back = rejoins
      end
      [ leave, back ]
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

    def campus_suffix(via)
      parts = via.to_s.split(LABEL_SEPARATOR)
      if parts.length >= 2 && CLOCK_BEFORE.match?(parts[-2]) && CLOCK_AFTER.match?(parts[-1])
        return parts.last(2).join(LABEL_SEPARATOR)
      end

      parts.last if [ DETOUR_LABEL, PLAIN_LABEL ].include?(parts.last)
    end

    def clock_hours(text)
      parts = text.to_s.split("-", 2)
      parts if parts.size == 2 && parts.all? { |part| part.match?(/\A\d{2}:\d{2}\z/) }
    end

    def strip_hospital_en(text)
      cleaned = text.to_s.gsub(/,?\s*(?:detour via|skips) Tri-Service General Hospital/, "").gsub(/\s{2,}/, " ").strip
      cleaned.sub(/,\z/, "").presence
    end

    def timed_via(via, hours)
      [ base_via(via), skip_label(hours) ].compact.join(LABEL_SEPARATOR).presence
    end

    def timed_via_en(via_en, hours)
      [ strip_hospital_en(via_en), skip_label_en(hours) ].compact.join(", ").presence
    end

    def write_labels!(data, slug:, via:, via_en:, hours:, span:, keep_trips: false)
      data = Marshal.load(Marshal.dump(data))
      properties = data["properties"]
      ref = properties["ref"]
      english_ref = properties["name_en"].to_s.sub(/\s*\(.*\z/, "").presence || ref
      name = via.present? ? "#{ref}（#{via}）" : ref.to_s
      name_en = via_en.present? ? "#{english_ref} (#{via_en})" : english_ref.to_s
      data["id"] = slug if data.key?("id")
      data["name"] = name
      properties.merge!("id" => slug, "name" => name, "name_en" => name_en)
      if via.present?
        properties["via"] = via
        properties["via_en"] = via_en
      else
        properties.delete("via")
        properties.delete("via_en")
      end
      properties["detour_hours"] = hours.join("-") if hours.present?
      properties["campus_span"] = span if span.present?
      properties.delete("daily_trips") unless keep_trips
      data["features"].each do |feature|
        next unless feature["properties"]

        if feature.dig("geometry", "type") == "Point"
          feature["properties"]["line"] = name
        else
          feature["properties"]["name"] = name
          feature["properties"]["name_en"] = name_en
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
