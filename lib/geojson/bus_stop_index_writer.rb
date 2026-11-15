# frozen_string_literal: true

require "fileutils"
require "json"

module Geojson
  # Inverts bus GeoJSON stop poles into StationID / lat-lon cluster → routes.
  # Written per city folder as `_stop_routes.json` for lazy map popup lookup.
  class BusStopIndexWriter
    INDEX_FILENAME = "_stop_routes.json"
    BOUNDS_FILENAME = "_stop_index_bounds.json"
    INTERCITY_SUBDIR = "intercity_bus"
    # Same name + this close is one shelter (highway coach sharing a city pole).
    # Opposite kerbs are usually ≥15 m, so stay under that.
    SHELTER_MERGE_METERS = 12

    Result = Data.define(:cities, :stations, :clusters)

    def self.write!(bus_root: nil, road_names: :default)
      new(bus_root: bus_root, road_names: road_names).write!
    end

    def self.index_path_for(subdir, bus_root: nil)
      root = bus_root || Geojson::BusLayout.bus_root
      root.join(subdir, INDEX_FILENAME)
    end

    # { subdir => [min_lon, min_lat, max_lon, max_lat] } of every index's stops.
    def self.bounds_path(bus_root: nil)
      (bus_root || Geojson::BusLayout.bus_root).join(BOUNDS_FILENAME)
    end

    def initialize(bus_root: nil, road_names: :default)
      @bus_root = bus_root || Geojson::BusLayout.bus_root
      @road_names = road_names == :default ? Geojson::OsmRoadNames.default : road_names
    end

    def write!
      by_subdir = Hash.new { |hash, key|
        hash[key] = { "stations" => {}, "clusters" => {}, "groups" => {} }
      }

      Dir.glob(@bus_root.join("**/*.geojson")).sort.each do |path|
        next if File.basename(path).start_with?("_")

        data = JSON.parse(File.read(path))
        properties = data["properties"] || {}
        route_id = properties["id"].presence || File.basename(path, ".geojson")
        city_id = properties["city_id"].presence || Geojson::BusLayout.city_id_for_slug(route_id)
        subdir = Geojson::BusLayout.subdir_for(city_id) || relative_subdir(path)
        next if subdir.blank?

        route = Geojson::BusStopClustering.route_entry(
          "id" => route_id,
          "ref" => properties["ref"],
          "name" => Geojson::BusServiceDays.display_name(properties["name"].presence || properties["ref"] || route_id, properties["service_window"]),
          "color" => properties["color"]
        )

        features = Array(data["features"])
        lines = features.each_with_object({}) do |feature, by_direction|
          next unless feature.dig("properties", "feature_type") == "route" && feature.dig("geometry", "type") == "LineString"

          by_direction[feature.dig("properties", "direction").to_s] ||= feature.dig("geometry", "coordinates")
        end
        stations = features.select { |feature| feature.dig("properties", "feature_type") == "station" }
        next_names = {}.compare_by_identity
        stations.each_with_index do |feature, index|
          direction = feature.dig("properties", "direction").to_s
          following = stations[(index + 1)..].find { |other| other.dig("properties", "direction").to_s == direction }
          next_names[feature] = following&.dig("properties", "name")
        end
        # Board 「往〜」 from the last StopOfRoute name (official bay / pole),
        # not the abbreviated Route 起迄站名 (樹林 vs 樹林藝文綜合行政大樓).
        last_stops = stations.each_with_object({}) do |feature, last|
          last[feature.dig("properties", "direction").to_s] = feature.dig("properties", "name")
        end
        first_stops = stations.each_with_object({}) do |feature, first|
          direction = feature.dig("properties", "direction").to_s
          first[direction] ||= feature.dig("properties", "name")
        end
        last_stops_en = stations.each_with_object({}) do |feature, last|
          props = feature["properties"] || {}
          direction = props["direction"].to_s
          last[direction] = props["name_en"].presence if props["name"].to_s == last_stops[direction]
        end
        intercity = city_id.to_s == "InterCity" || subdir == INTERCITY_SUBDIR

        stations.each do |feature|
          props = feature["properties"] || {}

          lon, lat = Geojson::BusStopClustering.coordinates_for(feature)
          name = props["name"].to_s
          stop_names_en[name] ||= props["name_en"].presence
          platform = props["platform"].presence
          station_id = Geojson::BusStopClustering.station_id_for(props)
          # TDX gives every bay of a terminal (新北板橋公車站 第一–第四月台) one
          # StationID; riders need each platform's routes on their own.
          station_id = self.class.platform_key(station_id, platform) if station_id.present?
          cluster = Geojson::BusStopClustering.cluster_key(name:, lon:, lat:)

          direction = props["direction"].to_s
          last_stop = last_stops[direction]
          first_stop = first_stops[direction]
          stop_route = if last_stop.blank?
            route.dup
          elsif last_stop == name
            route.merge("terminus" => true)
          else
            entry = route.merge("toward" => [ last_stop ])
            toward_en = last_stops_en[direction].presence || stop_names_en[last_stop]
            entry["toward_en"] = [ toward_en ] if toward_en.present?
            entry
          end
          # Highway coaches separate 上客 (board) from 下客 (alight) at termini.
          if intercity
            stop_route = stop_route.merge("board" => true) if first_stop == name
            stop_route = stop_route.merge("alight" => true) if last_stop == name
          end
          city_index = by_subdir[subdir]
          if station_id.present?
            city_index["stations"][station_id] ||= []
            merge_stop_route!(city_index["stations"][station_id], stop_route)
          end
          if cluster.present?
            city_index["clusters"][cluster] ||= []
            merge_stop_route!(city_index["clusters"][cluster], stop_route)
          end
          add_to_group!(
            city_index["groups"], station_id.presence || self.class.platform_key(cluster, platform),
            name:, lon:, lat:, stop_uid: props["ref"], platform:,
            toward: next_names[feature],
            heading: heading_along(lines[props["direction"].to_s], lon, lat)
          )
        end
      rescue JSON::ParserError
        next
      end

      stations = 0
      clusters = 0
      by_subdir.each_value do |payload|
        stations += payload["stations"].size
        clusters += payload["clusters"].size
        sort_routes!(payload)
        finalize_groups!(payload)
        add_english_towards!(payload)
      end
      merge_shared_shelters!(by_subdir)
      by_subdir.each do |subdir, payload|
        sort_routes!(payload)
        path = self.class.index_path_for(subdir, bus_root: @bus_root)
        FileUtils.mkdir_p(path.dirname)
        File.write(path, "#{JSON.pretty_generate(payload)}\n")
        puts "Wrote #{path}"
      end
      write_bounds!(by_subdir)
      Geojson::BusStopSearchIndex.write_groups!(by_subdir, bus_root: @bus_root)

      Result.new(cities: by_subdir.keys.sort, stations:, clusters:)
    end

    def self.platform_key(key, platform)
      key.present? && platform.present? ? "#{key}@#{platform}" : key
    end

    CHINESE_DIGITS = %w[〇 一 二 三 四 五 六 七 八 九].each_with_index.to_h.merge("十" => 10).freeze

    # 第四月台 → Platform 4, A月台 → Platform A, 3號月台 → Platform 3.
    def self.platform_en(platform)
      return nil if platform.blank?

      label = platform.to_s.tr("０-９", "0-9").sub(/\A[第交]/, "").sub(/號?月台\z/, "")
      label = label.chars.reduce(0) { |sum, char| char == "十" ? [ sum, 1 ].max * 10 : sum + CHINESE_DIGITS[char].to_i }.to_s if label.match?(/\A[〇一二三四五六七八九十]+\z/)
      "Platform #{label.tr('號', '-')}"
    end

    private

    # Highway coaches often stop at the same shelter as city buses. Fold those
    # poles together so through-routes, arrivals, and search show one board.
    def merge_shared_shelters!(by_subdir)
      intercity = by_subdir[INTERCITY_SUBDIR]
      return unless intercity.is_a?(Hash)

      by_name = Hash.new { |hash, key| hash[key] = [] }
      by_subdir.each do |subdir, payload|
        next if subdir == INTERCITY_SUBDIR

        (payload["groups"] || {}).each do |key, group|
          by_name[group["name"].to_s] << [ subdir, key.to_s, group ]
        end
      end

      (intercity["groups"] || {}).each do |ic_key, ic_group|
        name = ic_group["name"].to_s
        next if name.blank?

        match = by_name[name]
          .select { |_subdir, _key, group| shelter_pair?(group, ic_group) }
          .min_by { |_subdir, _key, group| shelter_distance_meters(group, ic_group) }
        next unless match

        subdir, city_key, city_group = match
        link_shelters!(
          by_subdir[subdir], city_key, city_group,
          intercity, ic_key.to_s, ic_group,
          peer_subdir: INTERCITY_SUBDIR, host_subdir: subdir
        )
      end
    end

    def shelter_pair?(left, right)
      return false unless platforms_compatible?(left["platform"], right["platform"])

      shelter_distance_meters(left, right) <= SHELTER_MERGE_METERS
    end

    def platforms_compatible?(left, right)
      a = left.to_s.presence
      b = right.to_s.presence
      a.nil? || b.nil? || a == b
    end

    def shelter_distance_meters(from, to)
      lat_scale = 111_320.0
      lon_scale = lat_scale * Math.cos(from["lat"].to_f * Math::PI / 180)
      Math.hypot(
        (to["lat"].to_f - from["lat"].to_f) * lat_scale,
        (to["lon"].to_f - from["lon"].to_f) * lon_scale
      )
    end

    def link_shelters!(host_payload, host_key, host_group, peer_payload, peer_key, peer_group, peer_subdir:, host_subdir:)
      merge_group_stops!(host_group, peer_group)
      merge_group_stops!(peer_group, host_group)
      merge_group_routes!(host_payload, host_key, peer_payload, peer_key)
      merge_group_routes!(peer_payload, peer_key, host_payload, host_key)

      peers = Array(host_group["shelter_peers"])
      peer_ref = { "subdir" => peer_subdir, "key" => peer_key }
      host_group["shelter_peers"] = (peers + [ peer_ref ]).uniq unless peers.include?(peer_ref)
      peer_group["shelter_of"] = { "subdir" => host_subdir, "key" => host_key }
    end

    def merge_group_stops!(into, from)
      into["stops"] = (Array(into["stops"]) | Array(from["stops"])).map(&:to_s).reject(&:blank?).uniq.sort
    end

    def merge_group_routes!(into_payload, into_key, from_payload, from_key)
      from_routes = routes_for(from_payload, from_key)
      return if from_routes.empty?

      into_list = ensure_route_list!(into_payload, into_key)
      from_routes.each { |route| merge_stop_route!(into_list, route) }
    end

    def routes_for(payload, key)
      payload.dig("stations", key) || payload.dig("clusters", key) || []
    end

    def ensure_route_list!(payload, key)
      return payload["stations"][key] if payload["stations"].key?(key)
      return payload["clusters"][key] if payload["clusters"].key?(key)

      if key.include?("|")
        payload["clusters"][key] ||= []
      else
        payload["stations"][key] ||= []
      end
    end

    def write_bounds!(by_subdir)
      bounds = by_subdir.sort.to_h.filter_map do |subdir, payload|
        groups = payload["groups"].values
        next if groups.empty?

        lons = groups.map { |group| group["lon"] }
        lats = groups.map { |group| group["lat"] }
        [ subdir, [ lons.min, lats.min, lons.max, lats.max ] ]
      end
      File.write(self.class.bounds_path(bus_root: @bus_root), "#{JSON.generate(bounds.to_h)}\n")
    end

    # A route serving one pole in both directions heads for both termini.
    # Keep board/alight so highway-coach 上客／下客 stay distinct after merge.
    def merge_stop_route!(list, entry)
      existing = list.find { |row| row["id"] == entry["id"] }
      return Geojson::BusStopClustering.merge_route!(list, entry.dup) unless existing

      towards = Array(existing["toward"]) | Array(entry["toward"])
      towards_en = Array(existing["toward_en"]) | Array(entry["toward_en"])
      Geojson::BusStopClustering.merge_route!(list, entry.except("toward", "toward_en", "terminus", "board", "alight"))
      existing["toward"] = towards if towards.any?
      existing["toward_en"] = towards_en if towards_en.any?
      existing["terminus"] = true if existing["terminus"] || entry["terminus"]
      existing["board"] = true if existing["board"] || entry["board"]
      existing["alight"] = true if existing["alight"] || entry["alight"]
    end

    def relative_subdir(path)
      relative = Pathname.new(path).relative_path_from(@bus_root)
      relative.each_filename.first
    rescue ArgumentError
      nil
    end

    # Stop groups (TDX StationID, or the lat/lon cluster when a pole has none)
    # with their mean position and every route's StopUID, so the map can offer
    # nearby same-name groups and ask TDX for exactly one group's arrivals.
    def add_to_group!(groups, key, name:, lon:, lat:, stop_uid:, platform: nil, toward: nil, heading: nil)
      return if key.blank? || name.blank? || lon.nil? || lat.nil?

      group = groups[key] ||= {
        "name" => name, "platform" => platform, "lon_sum" => 0.0, "lat_sum" => 0.0, "count" => 0, "stops" => [],
        "toward" => Hash.new(0), "heading_x" => 0.0, "heading_y" => 0.0
      }
      group["lon_sum"] += lon
      group["lat_sum"] += lat
      group["count"] += 1
      group["stops"] << stop_uid.to_s if stop_uid.present? && !group["stops"].include?(stop_uid.to_s)
      group["toward"][toward] += 1 if toward.present? && toward != name
      if heading
        group["heading_x"] += Math.sin(heading * Math::PI / 180)
        group["heading_y"] += Math.cos(heading * Math::PI / 180)
      end
    end

    # Each group also gets the street it stands on and the stop most of its
    # buses head for next, so riders can tell same-name poles apart.
    def finalize_groups!(payload)
      payload["groups"].transform_values! do |group|
        lon = (group["lon_sum"] / group["count"]).round(6)
        lat = (group["lat_sum"] / group["count"]).round(6)
        heading = if group["heading_x"].abs + group["heading_y"].abs > 1e-6
          (Math.atan2(group["heading_x"], group["heading_y"]) * 180 / Math::PI) % 360
        end
        road = @road_names&.road_at(lon, lat, heading)
        # OSM's bay names at 新北板橋公車站 disagree with TDX (and the signs).
        road = nil if group["platform"] && road.to_s.include?("月台")
        road = Geojson::RareHan.display(road) if road
        toward = group["toward"].max_by { |stop_name, count| [ count, stop_name ] }&.first
        {
          "name" => Geojson::RareHan.display(group["name"]),
          "name_en" => stop_names_en[group["name"]],
          "platform" => group["platform"],
          "platform_en" => self.class.platform_en(group["platform"]),
          "lat" => lat,
          "lon" => lon,
          "stops" => group["stops"].sort,
          "road" => road,
          "road_en" => english_road(road),
          "toward" => toward && Geojson::RareHan.display(toward),
          "toward_en" => stop_names_en[toward]
        }.compact
      end
    end

    def stop_names_en
      @stop_names_en ||= {}
    end

    def english_road(road)
      return if road.blank?

      english = Geojson::BusNamesEn.translate(road)
      english unless english.match?(Geojson::BusNamesEn::HAN)
    end

    def add_english_towards!(payload)
      payload.values_at("stations", "clusters").compact.each do |index|
        index.each_value do |routes|
          routes.each do |route|
            towards = Array(route["toward"])
            next if towards.empty?
            next if Array(route["toward_en"]).any?

            route["toward_en"] = towards.map { |stop| stop_names_en[stop] || stop }
          end
        end
      end
    end

    # Travel bearing of the route line at its closest segment to the stop.
    def heading_along(line, lon, lat)
      return nil unless line.is_a?(Array) && line.length >= 2

      lon_scale = Math.cos(lat * Math::PI / 180)
      a, b = line.each_cons(2).min_by do |p, q|
        dx = (q[0] - p[0]) * lon_scale
        dy = q[1] - p[1]
        px = (lon - p[0]) * lon_scale
        py = lat - p[1]
        length_sq = (dx * dx) + (dy * dy)
        t = length_sq.zero? ? 0.0 : (((px * dx) + (py * dy)) / length_sq).clamp(0.0, 1.0)
        ((px - (t * dx))**2) + ((py - (t * dy))**2)
      end
      return nil if a == b

      Geojson::OsmRoadNames.bearing(a, b)
    end

    def sort_routes!(payload)
      payload["stations"].each_value { |routes| routes.sort_by! { |row| [ row["ref"].to_s, row["id"].to_s ] } }
      payload["clusters"].each_value { |routes| routes.sort_by! { |row| [ row["ref"].to_s, row["id"].to_s ] } }
    end
  end
end
