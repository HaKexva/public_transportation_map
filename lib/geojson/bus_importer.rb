# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Geojson
  class BusImporter
    OUTPUT_SUBDIR = "bus"
    Result = Data.define(:routes, :skipped)

    PALETTE = %w[
      #0B7A3E #2563eb #dc2626 #d97706 #7c3aed #0891b2 #db2777
      #4f46e5 #ea580c #0f766e #9333ea #be123c #0369a1
      #65a30d #c2410c #1d4ed8 #a21caf #0e7490 #b91c1c
      #15803d #7c2d12 #1e3a8a #6b21a8 #155e75 #9f1239
      #3f6212 #92400e #3730a3 #701a75 #134e4a #9f1239
      #166534 #b45309 #1e40af #86198f #115e59 #9a3412
    ].freeze

    def self.import!(city_id:, series: nil, client: nil, rewrite_manifest: true, prune_stale: false, only_slugs: nil)
      new(
        city_id: city_id,
        series: series,
        client: client,
        rewrite_manifest: rewrite_manifest,
        prune_stale: prune_stale,
        only_slugs: only_slugs
      ).import!
    end

    # Import specific RouteUID rows via PTX (or any TdxClient-compatible client).
    # ROUTE_UIDS=NWT18288,TXG2513 bin/rails geojson:bus_route_uids CITY=NewTaipei
    def self.import_route_uids!(city_id:, route_uids:, client: nil, rewrite_manifest: true)
      new(city_id:, client:, rewrite_manifest:, prune_stale: false).import_route_uids!(route_uids)
    end

    def initialize(city_id:, series: nil, client: nil, rewrite_manifest: true, prune_stale: false, only_slugs: nil)
      @city = Geojson::BusCatalog.find(city_id)
      raise ArgumentError, "Unknown bus city: #{city_id}" unless @city

      @series = series.to_s.presence
      @client = client
      @rewrite_manifest = rewrite_manifest
      @prune_stale = prune_stale && only_slugs.nil?
      @only_slugs = only_slugs&.map(&:to_s)&.to_set
    end

    def import!
      client = @client || Transit::TdxClient.new(ignore_breaker: true)
      if client.respond_to?(:configured?) && !client.configured?
        raise Transit::TdxClient::ConfigurationError, "TDX_CLIENT_ID and TDX_CLIENT_SECRET are required"
      end

      @client = client
      routes = @client.fetch_all(self.class.route_path_for(@city))
      shapes = @client.fetch_all(self.class.shape_path_for(@city))
      stop_of_routes = @client.fetch_all(self.class.stop_of_route_path_for(@city))

      skipped = []
      built = []
      shapes_by_uid = Array(shapes).group_by { |shape| shape["RouteUID"].to_s }
      stops_by_uid = Array(stop_of_routes).group_by { |row| row["RouteUID"].to_s }

      self.class.grouped_routes(routes, city: @city, series: @series).each do |slug, group, distinguish_via, unlabeled_via|
        next if @only_slugs && !@only_slugs.include?(slug)

        collections = group.filter_map do |route|
          uid = route["RouteUID"].to_s
          shape_rows = filter_variant_rows(shapes_by_uid[uid] || [], route)
          stop_rows = filter_variant_rows(stops_by_uid[uid] || [], route)
          build_collection(
            route,
            shape_rows,
            stop_rows,
            distinguish_via:,
            unlabeled_via:
          )
        end
        if collections.empty?
          skipped.concat(group.map { |route| route_label(route) })
          next
        end

        collection = merge_collections(collections, slug)
        built << slug
        write_collection!(collection)
      end

      prune_stale_city_files!(built) if @prune_stale
      merge_night_routes!
      rewrite_bus_indexes! if @rewrite_manifest && built.any?
      Result.new(routes: built, skipped: skipped)
    end

    def import_route_uids!(route_uids)
      client = @client || Transit::PtxClient.new
      @client = client

      skipped = []
      built = []

      Array(route_uids).map(&:to_s).reject(&:blank?).uniq.each do |uid|
        filter = "RouteUID eq '#{uid}'"
        routes = @client.fetch_all(self.class.route_path_for(@city), query: { "$filter" => filter })
        if routes.empty?
          skipped << uid
          next
        end

        shapes = @client.fetch_all(self.class.shape_path_for(@city), query: { "$filter" => filter })
        stop_of_routes = @client.fetch_all(self.class.stop_of_route_path_for(@city), query: { "$filter" => filter })
        shapes_by_uid = Array(shapes).group_by { |shape| shape["RouteUID"].to_s }
        stops_by_uid = Array(stop_of_routes).group_by { |row| row["RouteUID"].to_s }

        self.class.grouped_routes(routes, city: @city).each do |slug, group, distinguish_via, unlabeled_via|
          collections = group.filter_map do |route|
            route_uid = route["RouteUID"].to_s
            shape_rows = filter_variant_rows(shapes_by_uid[route_uid] || [], route)
            stop_rows = filter_variant_rows(stops_by_uid[route_uid] || [], route)
            build_collection(
              route,
              shape_rows,
              stop_rows,
              distinguish_via:,
              unlabeled_via:
            )
          end
          if collections.empty?
            skipped.concat(group.map { |route| route_label(route) })
            next
          end

          collection = merge_collections(collections, slug)
          built << slug
          write_collection!(collection)
        end
      end

      merge_night_routes!
      rewrite_bus_indexes! if @rewrite_manifest && built.any?
      Result.new(routes: built.uniq, skipped: skipped)
    end

    def merge_night_routes!
      subdir = Geojson::BusLayout.subdir_for(@city.id)
      return if subdir.blank?

      dir = Geojson::BusLayout.bus_root.join(subdir)
      Geojson::BusNightMerger.process_city_dir!(dir) if dir.exist?
    end

    def rewrite_bus_indexes!
      Geojson::RoutesManifestWriter.write!
      Geojson::BusStopIndexWriter.write!
      Geojson::BusDepotWriter.write!
    end

    def self.route_path_for(city)
      return "v2/Bus/Route/InterCity" if city.kind == :intercity

      "v2/Bus/Route/City/#{city.tdx_city}"
    end

    def self.shape_path_for(city)
      return "v2/Bus/Shape/InterCity" if city.kind == :intercity

      "v2/Bus/Shape/City/#{city.tdx_city}"
    end

    def self.stop_of_route_path_for(city)
      return "v2/Bus/StopOfRoute/InterCity" if city.kind == :intercity

      "v2/Bus/StopOfRoute/City/#{city.tdx_city}"
    end

    # Yields [slug, routes, distinguish_via, unlabeled_via] for each import group.
    def self.grouped_routes(routes, city:, series: nil)
      return grouped_intercity_routes(routes, series:) if city.kind == :intercity

      collapse_extra_digits = true
      selected = Array(routes).select { |route|
        name = route_name_zh(route)
        series_match?(name, series: series, city:) && !test_route_name?(name)
      }
      groups = []

      selected.group_by { |route|
        public_ref(route_name_zh(route).presence || route["RouteID"].to_s, collapse_extra_digits:, city:)
      }.each do |_ref, numbered|
        numbered = select_listed_routes(numbered, collapse_extra_digits:)
        via_labels = numbered.map { |route| variant_label(route).to_s }
        distinguish_via = via_labels.uniq.size > 1
        unlabeled_via = distinguish_via ? unlabeled_trunk_via(via_labels) : nil

        numbered.flat_map { |route| detour_variants(route) }
          .group_by { |route| slug_for(route, city:, distinguish_via:, unlabeled_via:) }.each do |slug, group|
          groups << [ slug, group, distinguish_via, unlabeled_via ]
        end
      end

      groups
    end

    DETOUR_PATTERN = /繞駛|繞經/
    # SubRoutes to draw as their own variant that the 繞駛/繞經 pattern misses,
    # by full SubRouteName: trip extensions (237經政大校區 loops through the
    # campus; 237不經政大校區 is the base, shown as 本線), 經/不經 detours
    # (903經三總 / 903不經三總), short detour labels (249繞崁頂) and branches
    # run by another operator (306(大都會) ends at 舊莊 instead of 凌雲五村).
    # main_label names the remaining plain variant.
    SUBROUTE_SPLITS = {
      "237經政大校區" => { label: "延駛政大校區", main_label: "本線" },
      "249繞崁頂" => { label: "繞駛崁頂" },
      "306(大都會)" => { label: "往舊莊", operator_id: "800" },
      "903經三總" => { label: "繞駛三總", main_label: "不繞駛三總" },
      "521經三總" => { label: "繞駛三總", main_label: "不繞駛三總" },
      "藍20經三總" => { label: "繞駛三總", main_label: "不繞駛三總" }
    }.freeze
    NAMED_LABEL_PATTERN = /繞駛|繞經|延駛|\A本線\z|\A往/

    def self.subroute_split(label)
      SUBROUTE_SPLITS.find { |_name, split| split[:label] == label }
    end

    # SubRouteNames split away from the plain variant named main_label.
    def self.split_names_for_main(main_label)
      SUBROUTE_SPLITS.select { |_name, split| split[:main_label] == main_label }.keys
    end

    # City routes that run a 繞駛 detour on some trips publish it as a separate
    # SubRoute (e.g. 33 / 33繞駛大道路). Draw each as its own route so the
    # detour does not get merged into the plain path.
    def self.detour_variants(route)
      subs = Array(route["SubRoutes"])
      detours = subs.select { |sub| detour_label(sub, route) }
      return [ route ] if detours.empty?

      # When the unlabelled SubRoutes don't run both ways (e.g. a one-way
      # side service), the single "不繞駛" label is the plain route.
      directions = ->(rows) { rows.map { |sub| sub["Direction"].to_s }.uniq.sort }
      if directions.(subs - detours) != directions.(subs)
        plain = detours.select { |sub| detour_label(sub, route).match?(/\A[不無]/) }
        plain_labels = plain.map { |sub| detour_label(sub, route) }.uniq
        detours -= plain if plain_labels.length == 1
      end

      main_uids = (subs - detours).map { |sub| sub["SubRouteUID"].to_s }.reject(&:blank?).uniq
      variants = []
      if main_uids.any?
        main = route.merge("_import_sub_uids" => main_uids, "_import_blank_sub" => true)
        main_label = detours.filter_map { |sub| subroute_split(detour_label(sub, route))&.last&.dig(:main_label) }.first
        main["_import_main_label"] = main_label if main_label
        variants << main
      end
      detours.group_by { |sub| detour_label(sub, route) }.each do |label, rows|
        variants << route.merge(
          "_import_sub_uids" => rows.map { |row| row["SubRouteUID"].to_s }.reject(&:blank?).uniq,
          "_import_detour" => label
        )
      end
      variants
    end

    def self.detour_label(sub, route)
      name = route_name_zh(sub.merge("RouteName" => sub["SubRouteName"])).strip
      parent = route_name_zh(route).strip
      return unless name.start_with?(parent) && name != parent
      return SUBROUTE_SPLITS.dig(name, :label) if SUBROUTE_SPLITS.key?(name)

      label = name.delete_prefix(parent).strip
      label = label[/[(（]([^()（）]*#{DETOUR_PATTERN}[^()（）]*)[)）]/, 1] || label
      label = label.sub(/(?:去程|返程|往程|回程)半?\z/, "").strip

      # Timetable notes ("平0550 假0600無繞駛") are not a separate path.
      label if label.match?(DETOUR_PATTERN) && !label.match?(/[平假]\s*\d{3,4}/)
    end

    # Highway coaches often encode A–J detours as SubRoutes with their own shapes.
    def self.grouped_intercity_routes(routes, series: nil)
      selected = Array(routes).select { |route| series_match?(route_name_zh(route), series: series) }
      groups = []

      selected.each do |route|
        intercity_variant_specs(route).each do |spec|
          next unless series.blank? || series_match?(spec[:ref], series: series) ||
            series_match?(route_name_zh(route), series: series)

          enriched = route.merge(
            "_import_ref" => spec[:ref],
            "_import_sub_uids" => spec[:sub_uids],
            "_import_headsign" => spec[:headsign]
          )
          slug = slug_for(enriched, city: Geojson::BusCatalog.find("InterCity"))
          groups << [ slug, [ enriched ], false, nil ]
        end
      end

      groups
    end

    def self.intercity_variant_specs(route)
      subs = Array(route["SubRoutes"])
      return [ { ref: route_name_zh(route).presence || route["RouteID"].to_s, sub_uids: nil, headsign: nil } ] if subs.empty?

      grouped = subs.group_by { |sub| intercity_subroute_ref(sub, route) }
      grouped.map do |ref, rows|
        {
          ref: ref,
          sub_uids: rows.map { |row| row["SubRouteUID"].to_s }.reject(&:blank?).uniq,
          headsign: rows.filter_map { |row| row["Headsign"].to_s.presence }.first
        }
      end.sort_by { |spec| [ spec[:ref].to_s.length, spec[:ref].to_s ] }
    end

    def self.intercity_subroute_ref(sub, route)
      name = route_name_zh(sub.merge("RouteName" => sub["SubRouteName"]))
      return name if name.present?

      uid = sub["SubRouteUID"].to_s
      parent = route_name_zh(route).presence || route["RouteID"].to_s
      if (match = uid.match(/#{Regexp.escape(parent)}([A-J])\d*\z/i))
        return "#{parent}#{match[1].upcase}"
      end

      parent
    end

    # Planned slug groups for coverage audits (does not require shapes).
    def self.plan_import(routes, city:, series: nil)
      collapse_extra_digits = city.kind != :intercity
      grouped_routes(routes, city:, series:).map do |slug, group, distinguish_via, unlabeled_via|
        {
          slug: slug,
          uids: group.map { |route| route["RouteUID"].to_s },
          gaps: group.map do |route|
            ref = route["_import_ref"].presence ||
              public_ref(route_name_zh(route).presence || route["RouteID"].to_s, collapse_extra_digits:, city:)
            via = if distinguish_via
              via_label = variant_label(route).presence || "其他"
              (unlabeled_via.present? && via_label == unlabeled_via) ? nil : via_label
            end
            label = [ route["RouteUID"], ref, via ].compact.join(" ").strip
            {
              city_id: city.id,
              route_uid: route["RouteUID"].to_s,
              ref: ref,
              label: label,
              slug: slug
            }
          end
        }
      end
    end

    def self.slug_for(route, city:, distinguish_via: false, unlabeled_via: nil)
      collapse_extra_digits = city.kind != :intercity
      raw_ref = route["_import_ref"].presence ||
        public_ref(route_name_zh(route).presence || route["RouteID"].to_s, collapse_extra_digits:, city:)
      ref = ref_slug(raw_ref)
      via = if distinguish_via
        via_label = variant_label(route).presence || "其他"
        (unlabeled_via.present? && via_label == unlabeled_via) ? nil : via_label
      end
      via_slug = variant_slug(via)
      detour = route["_import_detour"].to_s
      detour_slug = Digest::SHA1.hexdigest(detour)[0, 10] if detour.present?
      [ city.id.underscore, ref, via_slug, detour_slug ].compact_blank.join("_")
    end

    VIA_EN = {
      "祥豐街" => "Xiangfeng St.",
      "中正路" => "Zhongzheng Rd.",
      "大道路" => "Dadao Rd.",
      "本線" => "Main Line",
      "崁頂" => "Kanding",
      "往舊莊" => "to Jiuzhuang",
      "不繞駛三總" => "skips Tri-Service General Hospital",
      "三總" => "Tri-Service General Hospital",
      "延駛政大校區" => "extended to NCCU Campus"
    }.freeze

    def self.series_match?(route_name, series:, city: nil)
      return true if series.blank?

      public_ref(route_name, collapse_extra_digits: true, city:).match?(/\A#{Regexp.escape(series.to_s)}\d{2}/) ||
        route_name.to_s.match?(/\A#{Regexp.escape(series.to_s)}\d{2}/)
    end

    def self.test_route_name?(route_name)
      name = route_name.to_s
      name.include?("測試") || name.include?("煙火專車")
    end

    def self.public_ref(route_name, collapse_extra_digits: true, city: nil)
      raw = route_name.to_s.strip
      return raw unless collapse_extra_digits
      # Only Keelung TDX names use extra trailing digits (3014 → 301). Everywhere
      # else keep 5014 / 1717 intact so browse bands stay in 1000+.
      return raw unless city&.id == "Keelung"
      # 17xx–19xx are standalone four-digit routes, not 1xx detours.
      return raw if raw.match?(/\A1[7-9]\d{2}\z/)
      return raw unless (match = raw.match(/\A(\d{3})\d+\z/))

      match[1]
    end

    def self.extra_digit_name?(route_name)
      route_name.to_s.strip.match?(/\A\d{3}\d+\z/)
    end

    # TDX encodes some Keelung detours as extra-digit names (3014, 3063). Prefer the
    # public 3-digit listings when they already distinguish multiple paths; otherwise
    # keep extras that add a new via (and drop extras that only duplicate the parent).
    # Highway coaches keep their full route numbers (e.g. 1820).
    def self.select_listed_routes(routes, collapse_extra_digits: true)
      routes = Array(routes)
      return routes unless collapse_extra_digits

      listed = routes.reject { |route| extra_digit_name?(route_name_zh(route)) }
      extras = routes - listed
      return routes if listed.empty?
      return listed if extras.empty?

      listed_vias = listed.map { |route| variant_label(route).to_s }.uniq
      return listed if listed_vias.size > 1

      listed + extras.reject { |route| listed_vias.include?(variant_label(route).to_s) }
    end

    def self.route_name_zh(route)
      value = route["RouteName"]
      return value.to_s if value.is_a?(String)

      value&.[]("Zh_tw").to_s.presence || value&.[](:Zh_tw).to_s.presence.to_s
    end

    # When one via is a trunk street and the others are place detours (市場 / 新村),
    # treat the street as the unlabeled original route.
    def self.unlabeled_trunk_via(via_labels)
      unique = Array(via_labels).map(&:to_s).uniq
      unique.find { |via| trunk_via?(via, unique - [ via ]) }
    end

    def self.trunk_via?(via, sibling_vias)
      via = via.to_s
      return false if via.blank? || !via.match?(/[路街巷]\z/)

      Array(sibling_vias).none? { |other| other.to_s.match?(/[路街巷]/) }
    end

    def self.variant_label(route)
      headsigns = Array(route["SubRoutes"] || route["SubRoutes"]).filter_map { |sub| sub["Headsign"].to_s.presence }
      vias = headsigns.flat_map { |sign| via_tokens(sign) }.uniq

      if (via = vias.find { |value| value.include?("祥豐") })
        return via.include?("街") ? via : "祥豐街"
      end
      if (via = vias.find { |value| value.include?("中正") })
        return via.include?("路") ? via : "中正路"
      end
      return vias.join("、") if vias.any?

      compact_headsign(headsigns.first)
    end

    def self.via_tokens(sign)
      sign.to_s.scan(/經\s*([^經)）（(]+)/).flatten.flat_map { |chunk|
        chunk.split(/[、，,]/)
      }.map { |token| token.gsub(/[\s()（）]+/, "") }.compact_blank.uniq
    end

    # ActiveSupport parameterize strips Han characters, so 紅32 and 32 both
    # become "32". Map common Taipei/New Taipei tokens before slugifying.
    REF_TOKEN_MAP = {
      "內科" => "neike",
      "專車" => "zhuanche",
      "通勤" => "tongqin",
      "幹線" => "ganxian",
      "先導" => "xiandao",
      "快速" => "kuaisu",
      "跳蛙" => "tiaowa",
      "貓空" => "maokong",
      "市民" => "shimin",
      "紅" => "hong",
      "藍" => "lan",
      "綠" => "lu",
      "棕" => "zong",
      "橘" => "ju",
      "桔" => "ju",
      "黃" => "huang",
      "小" => "xiao",
      "副" => "fu",
      "區" => "qu"
    }.freeze

    def self.ref_slug(ref)
      raw = ref.to_s.strip
      return "unknown_#{Digest::SHA1.hexdigest("empty")[0, 8]}" if raw.blank?

      labeled = REF_TOKEN_MAP.sort_by { |token, _| -token.length }.reduce(raw.dup) do |text, (zh, en)|
        text.gsub(zh, en)
      end

      if labeled.match?(/\p{Han}/)
        base = labeled.gsub(/\p{Han}+/, "_").parameterize(separator: "_").presence
        digest = Digest::SHA1.hexdigest(raw)[0, 10]
        return [ base, digest ].compact_blank.join("_")
      end

      labeled.parameterize(separator: "_").presence || Digest::SHA1.hexdigest(raw)[0, 10]
    end

    def self.variant_slug(via)
      return if via.blank?
      return "xiangfeng" if via.include?("祥豐")
      return "zhongzheng" if via.include?("中正")

      latin = via.parameterize(separator: "_").presence
      return latin if latin.present?

      Digest::SHA1.hexdigest(via)[0, 10]
    end

    def self.variant_label_en(via)
      via.to_s.split("、").map { |part|
        VIA_EN[part] || VIA_EN.find { |zh, _en| part.include?(zh) }&.last || part
      }.join(", ")
    end

    def self.compact_headsign(sign)
      return if sign.blank?

      text = sign.to_s.gsub(/[→←—–\-／\/]+/, " ").squeeze(" ").strip
      parts = text.split(/\s+/).reject { |part| part.match?(/車站|火車站|總站/) }
      parts.first.presence || text.presence
    end

    def self.parse_wkt_lines(wkt)
      return [] if wkt.blank?
      return geojson_lines(wkt) if wkt.is_a?(Hash)

      text = wkt.to_s.strip
      if text.upcase.start_with?("MULTILINESTRING")
        inner = text.sub(/\AMULTILINESTRING\s*/i, "")
        split_line_groups(inner).filter_map { |group| parse_coordinate_list(group) }
      elsif text.upcase.start_with?("LINESTRING")
        coords = parse_coordinate_list(text.sub(/\ALINESTRING\s*/i, ""))
        coords ? [ coords ] : []
      else
        []
      end
    end

    def self.geojson_lines(geometry)
      type = geometry["type"] || geometry[:type]
      coordinates = geometry["coordinates"] || geometry[:coordinates]
      case type
      when "LineString" then [ coordinates ]
      when "MultiLineString" then Array(coordinates)
      else []
      end
    end

    def self.split_line_groups(wkt_inner)
      groups = []
      depth = 0
      start = nil
      wkt_inner.each_char.with_index do |char, index|
        if char == "("
          start = index + 1 if depth.zero?
          depth += 1
        elsif char == ")"
          depth -= 1
          groups << wkt_inner[start...index] if depth.zero? && start
        end
      end
      groups
    end

    def self.parse_coordinate_list(text)
      pairs = text.to_s.scan(/(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)/)
      return nil if pairs.length < 2

      pairs.map { |lon, lat| [ lon.to_f, lat.to_f ] }
    end

    private_class_method :geojson_lines, :split_line_groups, :parse_coordinate_list

    private

    def build_collection(route, shapes, stop_of_routes, distinguish_via: false, unlabeled_via: nil)
      ref = route_ref(route)
      via = variant_via(route, distinguish_via:, unlabeled_via:) || intercity_detour_via(route) ||
        route["_import_detour"].presence || route["_import_main_label"]
      slug = route_slug(route, distinguish_via:, unlabeled_via:)
      operator = operator_for(route)
      color = Geojson::BusOperatorColors.for_route(ref: ref, name: operator[:name], id: operator[:id]) ||
        route_color(operator[:name].presence || operator[:id].presence || slug)
      name = display_name(ref, via)
      name_en = Geojson::BusNamesEn.name_en(display_name_en(ref, via), ref: ref, city_id: @city.id)
      official_map_url = official_map_url_for(route)

      if @city.kind != :intercity || route["_import_blank_sub"] || route["_import_detour"]
        shapes, stop_of_routes = primary_subroute_rows(Array(shapes), Array(stop_of_routes), name: zh_name(route["RouteName"]))
      end

      # shapes / stop_of_routes are already scoped to this RouteUID by the caller.
      line_features = Array(shapes).filter_map do |shape|
        lines = self.class.parse_wkt_lines(shape["Geometry"] || shape["geometry"])
        next if lines.empty?

        coordinates = Geojson::BusLoopCloser.merge_line_strings(lines)
        next if coordinates.length < 2

        loop_stops = loop_stops_for_shape?(Array(stop_of_routes), shape["Direction"])
        coordinates = Geojson::BusShapeSharpener.sharpen(coordinates)
        unless loop_stops
          opposite_direction = Array(stop_of_routes).map { |row| row["Direction"] }.uniq
            .find { |value| value.to_s != shape["Direction"].to_s }
          coordinates = Geojson::BusShapeTrimmer.trim_to_stops(
            coordinates,
            stop_points_for_direction(Array(stop_of_routes), shape["Direction"]),
            end_point: stop_points_for_direction(Array(stop_of_routes), opposite_direction).first
          )
          if route["_import_detour"]
            coordinates = clip_to_terminals(coordinates, stop_points_for_direction(Array(stop_of_routes), shape["Direction"]))
          end
        end
        coordinates = Geojson::BusLoopCloser.close_loop_coordinates(coordinates, force: loop_stops)

        properties = {
          feature_type: "route",
          ref: ref,
          name: name,
          name_en: name_en,
          color: color,
          direction: shape["Direction"]
        }
        properties[:loop] = true if loop_stops || Geojson::BusLoopCloser.nearly_closed?(coordinates)

        {
          type: "Feature",
          properties: properties,
          geometry: {
            type: "LineString",
            coordinates: coordinates
          }
        }
      end

      return nil if line_features.empty?

      line_features = snap_corridor_line_features(line_features)
      if line_features.length == 2
        joined = Geojson::BusShapeTrimmer.join_termini(*line_features.map { |feature| feature.dig(:geometry, :coordinates) })
        line_features.zip(joined).each { |feature, coords| feature[:geometry][:coordinates] = coords }
      end
      station_features = station_features_for(Array(stop_of_routes), name: name, color: color)

      properties = {
        id: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        city_id: @city.id,
        source: "TDX Bus Shape / StopOfRoute"
      }
      properties[:loop] = true if line_features.any? { |feature| feature.dig(:properties, :loop) || feature.dig("properties", "loop") }
      if via.present?
        properties[:via] = via
        properties[:via_en] = Geojson::BusNamesEn.translate(via)
      end
      properties[:official_map_url] = official_map_url if official_map_url.present?
      unless keelung?
        properties[:operator_id] = operator[:id] if operator[:id].present?
        properties[:operator] = operator[:name] if operator[:name].present?
        operator_en = operator[:name_en].presence || Geojson::BusNamesEn.operator_en(operator[:name])
        properties[:operator_en] = operator_en if operator_en.present?
      end

      {
        id: slug,
        type: "FeatureCollection",
        name: name,
        properties: properties,
        features: line_features + station_features
      }
    end

    # A split variant still spans several SubRoutes (short turns, extensions,
    # duplicate shapes without a SubRouteUID). Draw one path per direction: the
    # SubRoute with the most stops, with its own shape or the best-fitting one.
    def primary_subroute_rows(shapes, stop_of_routes, name: nil)
      shape_km = shapes.to_h { |shape|
        line = Geojson::BusLoopCloser.merge_line_strings(self.class.parse_wkt_lines(shape["Geometry"] || shape["geometry"]))
        [ [ shape["SubRouteUID"].to_s, shape["Direction"].to_s ], Geojson::BusShapeTrimmer.path_length(line) ]
      }
      stop_rows = stop_of_routes.group_by { |row| row["Direction"].to_s }.values.map { |rows|
        exact = rows.select { |row| name.present? && zh_name(row["SubRouteName"]).to_s.strip == name.strip }
        (exact.presence || rows).max_by { |row|
          [ Array(row["Stops"]).length, shape_km[[ row["SubRouteUID"].to_s, row["Direction"].to_s ]] || 0 ]
        }
      }
      shape_rows = shapes.group_by { |shape| shape["Direction"].to_s }.map { |direction, rows|
        primary = stop_rows.find { |row| row["Direction"].to_s == direction }
        next rows.first unless primary

        own = rows.find { |shape| shape["SubRouteUID"].to_s.present? && shape["SubRouteUID"].to_s == primary["SubRouteUID"].to_s }
        own || rows.min_by { |shape| shape_stop_misfit(shape, primary) }
      }
      [ shape_rows, stop_rows ]
    end

    TERMINAL_OVERSHOOT_METERS = 300
    TERMINAL_SNAP_METERS = 150

    # A short-turn variant can borrow the full route's shape; cut whatever
    # runs past its first / last stop.
    def clip_to_terminals(line, stops)
      return line if line.length < 3 || stops.length < 2

      nearest = ->(point, range) {
        range.min_by { |index| Geojson::BusLoopCloser.meters_between(line[index], point) }
      }
      half = line.length / 2
      if Geojson::BusLoopCloser.meters_between(line.last, stops.last) > TERMINAL_OVERSHOOT_METERS
        index = nearest.(stops.last, half...line.length)
        line = line[0..index] if Geojson::BusLoopCloser.meters_between(line[index], stops.last) <= TERMINAL_SNAP_METERS
      end
      if Geojson::BusLoopCloser.meters_between(line.first, stops.first) > TERMINAL_OVERSHOOT_METERS
        index = nearest.(stops.first, 0...[ half, line.length - 2 ].min)
        line = line[index..] if Geojson::BusLoopCloser.meters_between(line[index], stops.first) <= TERMINAL_SNAP_METERS
      end
      line
    end

    def shape_stop_misfit(shape, stop_row)
      line = Geojson::BusLoopCloser.merge_line_strings(self.class.parse_wkt_lines(shape["Geometry"] || shape["geometry"]))
      return Float::INFINITY if line.length < 2

      stops = stop_points_for_direction([ stop_row ], stop_row["Direction"])
      return Float::INFINITY if stops.empty?

      distances = stops.map { |stop|
        line.each_cons(2).map { |a, b| Geojson::BusShapeTrimmer.project(stop, a, b)[:distance] }.min
      }
      misfit = distances.sum / distances.length
      misfit + (Geojson::BusShapeTrimmer.path_length(line) / 1_000_000.0)
    end

    def merge_collections(collections, slug)
      first = collections.first
      features = collections.flat_map { |collection| collection[:features] }
      seen_stops = {}
      merged_features = features.select do |feature|
        next true unless feature.dig(:properties, :feature_type) == "station"

        key = "#{feature.dig(:properties, :ref)}:#{feature.dig(:properties, :direction)}"
        next false if seen_stops[key]

        seen_stops[key] = true
      end

      first.merge(id: slug, features: snap_corridor_line_features(merged_features))
    end

    def snap_corridor_line_features(features)
      # Previously dropped inbound vertices within 50m of outbound so shared
      # corridors were drawn once. That left inbound as disconnected spur stubs
      # at junctions ("斷在路口"). Direction banding now separates outbound /
      # inbound on screen, so keep both full polylines.
      features
    end

    def loop_stops_for_shape?(stop_of_routes, direction)
      rows = Array(stop_of_routes).select { |row| row["Direction"].to_s == direction.to_s }
      rows = Array(stop_of_routes) if rows.empty?
      stops = rows.flat_map { |row| Array(row["Stops"]) }
      return false if stops.length < 2

      first = stop_identity(stops.first)
      last = stop_identity(stops.last)
      first.present? && first == last
    end

    def stop_points_for_direction(stop_of_routes, direction)
      rows = stop_of_routes.select { |row| row["Direction"].to_s == direction.to_s }
      rows.flat_map { |row| Array(row["Stops"]) }.filter_map do |stop|
        position = stop["StopPosition"] || {}
        lon = position["PositionLon"] || position["lon"]
        lat = position["PositionLat"] || position["lat"]
        [ lon.to_f, lat.to_f ] if lon.present? && lat.present?
      end
    end

    def stop_identity(stop)
      stop["StopUID"].to_s.presence ||
        stop["StopID"].to_s.presence ||
        zh_name(stop["StopName"]).presence
    end

    def station_features_for(stop_rows, name:, color:)
      seen = {}

      stop_rows.flat_map do |row|
        direction = row["Direction"]
        Array(row["Stops"]).map { |stop| [ stop, direction ] }
      end.filter_map do |stop, direction|
        uid = stop["StopUID"].to_s.presence || stop["StopID"].to_s
        key = "#{uid}:#{direction}"
        next if uid.blank? || seen[key]

        position = stop["StopPosition"] || {}
        lon = position["PositionLon"] || position["lon"]
        lat = position["PositionLat"] || position["lat"]
        next if lon.blank? || lat.blank?

        seen[key] = true
        stop_name = zh_name(stop["StopName"]).presence || uid
        properties = {
          feature_type: "station",
          ref: uid,
          name: stop_name,
          name_en: en_name(stop["StopName"]).presence,
          line: name,
          color: color
        }
        properties[:direction] = direction unless direction.nil?
        station_id = stop["StationID"].to_s.presence || stop["StationUID"].to_s.presence
        properties[:station_id] = station_id if station_id.present?
        properties[:stop_role] = "depot" if self.class.depot_stop_name?(stop_name)

        {
          type: "Feature",
          properties: properties,
          geometry: { type: "Point", coordinates: [ lon.to_f, lat.to_f ] }
        }
      end
    end

    # Bus dispatch yards / operator terminals that appear as StopOfRoute poles.
    # Never treat rail/metro 「機廠」 passenger-stop names as bus dispatch sites.
    def self.depot_stop_name?(name)
      text = name.to_s
      return false if text.blank?
      return false if text.match?(/立體停車場|公有市場|公有停車場|寺停車場|博物館|藝文園區|花鐘|林務局|招呼站/)
      return false if rail_or_metro_yard_stop_name?(text)

      text.include?("調度站") ||
        text.include?("調度場") ||
        text.match?(/客運.{0,24}停車場/) ||
        text.match?(/客運.{0,24}車場/) ||
        text.match?(/客運.{0,24}場站/) ||
        text.match?(/(?:\A|[\(（])調度/) ||
        text.match?(/調車場\z/) ||
        bus_operator_station_name?(text) ||
        bus_terminal_name?(text) ||
        bus_substation_name?(text)
    end

    def self.rail_or_metro_yard_stop_name?(name)
      text = name.to_s
      text.include?("機廠") || text.match?(/高鐵總/)
    end

    def self.bus_terminal_name?(name)
      text = name.to_s
      return false if text.blank? || text == "總站"
      return false if text.match?(/捷運|輕軌|高鐵/)

      text.include?("總站")
    end

    def self.bus_substation_name?(name)
      text = name.to_s
      return false if text.blank? || text.match?(/林務/)

      text.include?("分站")
    end

    def self.bus_operator_station_name?(name)
      text = name.to_s
      text.include?("客運站") || text.match?(/客運.{0,20}站\z/)
    end

    def write_collection!(collection)
      slug = collection.delete(:id)
      ref = collection.dig(:properties, :ref)
      path = Geojson::BusLayout.geojson_path(
        city_id: @city.id,
        slug:,
        ref:,
        operator_id: collection.dig(:properties, :operator_id),
        operator_name: collection.dig(:properties, :operator)
      )
      collection = collection.deep_stringify_keys
      Geojson::BusTerminalAccess.process_collection!(collection)
      Geojson::BusShapePatches.process_collection!(collection)
      Geojson::BusRoundabouts.process_collection!(collection)
      Geojson::BusRoadSnapper.process_collection!(collection)
      Geojson::BusTerminusHandoff.process_collection!(collection)
      Geojson::BusCornerRounder.process_collection!(collection)
      if path.exist?
        previous = JSON.parse(path.read)["properties"] || {}
        %w[merged_refs off_days service_window].each do |key|
          collection["properties"][key] = previous[key] if previous[key].present?
        end
      end
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "#{JSON.pretty_generate(collection)}\n")
      puts "Wrote #{path}"
    end

    def route_slug(route, distinguish_via: false, unlabeled_via: nil)
      self.class.slug_for(route, city: @city, distinguish_via:, unlabeled_via:)
    end

    def variant_via(route, distinguish_via:, unlabeled_via: nil)
      return nil unless distinguish_via

      via = self.class.variant_label(route).presence || "其他"
      return nil if unlabeled_via.present? && via == unlabeled_via

      via
    end

    def route_ref(route)
      return route["_import_ref"].to_s if route["_import_ref"].present?

      self.class.public_ref(
        zh_name(route["RouteName"]).presence || route["RouteID"].to_s,
        collapse_extra_digits: @city.kind != :intercity,
        city: @city
      )
    end

    def display_name(ref, via)
      return ref if via.blank?

      label = via.to_s.sub(/\A經/, "")
      return "#{ref}（#{label}）" if @city.kind == :intercity || label.match?(NAMED_LABEL_PATTERN)

      "#{ref}（經#{label}）"
    end

    def display_name_en(ref, via)
      return ref if via.blank?

      if (detour = via.to_s[/\A(?:繞駛|繞經)(.+)\z/, 1])
        return "#{ref} (detour via #{self.class.variant_label_en(detour)})"
      end

      label = self.class.variant_label_en(via)
      return "#{ref} (#{label})" if @city.kind == :intercity || via.to_s.match?(NAMED_LABEL_PATTERN)

      "#{ref} (via #{label})"
    end

    def route_label(route)
      "#{route['RouteUID']} #{route_ref(route)}".strip
    end

    def route_color(seed)
      index = Digest::SHA1.hexdigest(seed.to_s)[0, 8].to_i(16)
      PALETTE[index % PALETTE.length]
    end

    def official_map_url_for(route)
      explicit = route["RouteMapImageUrl"].to_s.presence || route["RouteMapUrl"].to_s.presence
      if explicit.present?
        # TDX often gives HTML portal pages (ebus MapOverview); resolve to a direct image for <img>.
        resolved = Geojson::BusOfficialMapFetcher.new(
          city_ids: [ @city.id ],
          resolve_portals: false,
          rewrite_manifest: false,
          sync_tdx: false
        ).resolve_direct_image_url(explicit)
        return resolved if resolved.present?
        return nil if Geojson::BusOfficialMapFetcher::PORTAL_HINT.match?(explicit)

        return explicit
      end

      intercity_schematic_url(route)
    end

    def intercity_schematic_url(route)
      return unless @city.kind == :intercity

      ref = route_ref(route).to_s
      base = ref.sub(/[A-J]\z/i, "")
      return if base.blank?

      "https://web.taiwanbus.tw/MISUploadData/Schematic/file/#{base}.jpg"
    end

    def filter_variant_rows(rows, route)
      uids = Array(route["_import_sub_uids"]).map(&:to_s).reject(&:blank?)
      return rows if uids.empty? && !route["_import_blank_sub"]

      kept = rows.select { |row|
        uid = row["SubRouteUID"].to_s
        uids.include?(uid) || (route["_import_blank_sub"] && uid.blank?)
      }
      return kept unless route["_import_detour"]

      # Detour shapes may only be published without a SubRouteUID. That is
      # only safe when the other SubRoutes carry their own shapes; otherwise
      # the blank shapes are the plain route.
      others = rows.any? { |row| row["SubRouteUID"].to_s.present? && !uids.include?(row["SubRouteUID"].to_s) }
      return kept unless others

      covered = kept.map { |row| row["Direction"].to_s }
      kept + rows.select { |row| row["SubRouteUID"].to_s.blank? && !covered.include?(row["Direction"].to_s) }
    end

    # e.g. "臺北→竹東[繞駛關西市區]" → "繞駛關西市區"
    def intercity_detour_via(route)
      return unless @city.kind == :intercity

      headsign = route["_import_headsign"].to_s
      return if headsign.blank?

      if (match = headsign.match(/\[([^\]]+)\]/))
        return match[1].strip
      end

      tokens = self.class.via_tokens(headsign)
      tokens.join("、").presence
    end

    def prune_stale_city_files!(kept_slugs)
      city_key = @city.id.underscore
      sibling_prefixes = Geojson::BusCatalog.cities
        .map { |entry| entry.id.underscore }
        .reject { |key| key == city_key }
        .select { |key| key.start_with?("#{city_key}_") }
      prefix = "#{city_key}_"
      search_roots = [ Geojson::BusLayout.bus_root ]
      subdir = Geojson::BusLayout.subdir_for(@city.id)
      search_roots << Geojson::BusLayout.bus_root.join(subdir) if subdir.present?

      search_roots.each do |root|
        next unless root.exist?

        Dir.glob(root.join("**/*.geojson")).each do |path|
          slug = File.basename(path, ".geojson")
          next unless slug == city_key || slug.start_with?(prefix)
          next if sibling_prefixes.any? { |sibling| slug == sibling || slug.start_with?("#{sibling}_") }
          next if kept_slugs.include?(slug)

          File.delete(path)
        end
      end
    end

    def keelung?
      @city.id == "Keelung"
    end

    def operator_for(route)
      operators = Array(route["Operators"])
      split_operator = self.class.subroute_split(route["_import_detour"])&.last&.dig(:operator_id)
      operator = operators.find { |row| split_operator && row["OperatorID"].to_s == split_operator } || operators.first || {}
      {
        id: operator["OperatorID"].to_s.presence,
        name: zh_name(operator["OperatorName"]).presence || operator["OperatorID"].to_s,
        name_en: en_name(operator["OperatorName"])
      }
    end

    def zh_name(value)
      return value.to_s if value.is_a?(String)

      value&.[]("Zh_tw").to_s.presence || value&.[](:Zh_tw).to_s.presence
    end

    def en_name(value)
      return nil if value.is_a?(String)

      value&.[]("En").to_s.presence || value&.[](:En).to_s.presence
    end
  end
end
