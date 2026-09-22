# frozen_string_literal: true

module Geojson
  # Resolves on-disk paths for city bus GeoJSON and official schematic maps.
  module BusLayout
    ROOT = "bus"
    MIN_ROUTES_FOR_BANDS = 10

    CITY_SUBDIRS = {
      "Keelung" => "keelung_bus",
      "Taipei" => "taipei_new_taipei_bus",
      "NewTaipei" => "taipei_new_taipei_bus",
      "Taoyuan" => "taoyuan_bus",
      "Hsinchu" => "hsinchu_city_bus",
      "HsinchuCounty" => "hsinchu_county_bus",
      "MiaoliCounty" => "miaoli_bus",
      "Taichung" => "taichung_bus",
      "ChanghuaCounty" => "changhua_bus",
      "NantouCounty" => "nantou_bus",
      "YunlinCounty" => "yunlin_bus",
      "Chiayi" => "chiayi_city_bus",
      "ChiayiCounty" => "chiayi_county_bus",
      "Tainan" => "tainan_bus",
      "Kaohsiung" => "kaohsiung_bus",
      "PingtungCounty" => "pingtung_bus",
      "YilanCounty" => "yilan_bus",
      "HualienCounty" => "hualian_bus",
      "TaitungCounty" => "taitung_bus",
      "PenghuCounty" => "penghu_bus",
      "KinmenCounty" => "kinmen_bus",
      "InterCity" => "intercity_bus"
    }.freeze

    SLUG_CITY_PREFIXES = [
      %w[new_taipei NewTaipei],
      %w[chiayi_county ChiayiCounty],
      %w[hsinchu_county HsinchuCounty],
      %w[miaoli_county MiaoliCounty],
      %w[changhua_county ChanghuaCounty],
      %w[nantou_county NantouCounty],
      %w[yunlin_county YunlinCounty],
      %w[chiayi Chiayi],
      %w[pingtung_county PingtungCounty],
      %w[yilan_county YilanCounty],
      %w[hualien_county HualienCounty],
      %w[taitung_county TaitungCounty],
      %w[penghu_county PenghuCounty],
      %w[kinmen_county KinmenCounty],
      %w[inter_city InterCity],
      %w[keelung Keelung],
      %w[taipei Taipei],
      %w[taoyuan Taoyuan],
      %w[hsinchu Hsinchu],
      %w[taichung Taichung],
      %w[tainan Tainan],
      %w[kaohsiung Kaohsiung]
    ].freeze

    module_function

    def bus_root
      @bus_root_override || Rails.root.join("public/geojson", ROOT)
    end

    def bus_root=(path)
      @bus_root_override = path && Pathname.new(path)
      reset_route_counts!
    end

    # Temporarily redirect on-disk bus GeoJSON (for isolated parallel tests).
    # Pass route_counts: to seed uses_bands? without scanning the temp tree.
    def with_bus_root(path, route_counts: nil)
      previous_root = @bus_root_override
      previous_counts = @route_counts
      self.bus_root = path
      @route_counts = route_counts unless route_counts.nil?
      yield
    ensure
      @bus_root_override = previous_root
      @route_counts = previous_counts
    end

    def subdir_for(city_id)
      CITY_SUBDIRS[city_id.to_s]
    end

    def city_id_for_slug(slug)
      text = slug.to_s
      SLUG_CITY_PREFIXES.each do |prefix, city_id|
        return city_id if text.start_with?("#{prefix}_") || text == prefix
      end

      nil
    end

    def reset_route_counts!
      @route_counts = nil
    end

    def route_counts
      @route_counts ||= compute_route_counts
    end

    def compute_route_counts
      counts = Hash.new(0)
      Dir.glob(bus_root.join("**/*.geojson")).each do |path|
        data = JSON.parse(File.read(path))
        city = data.dig("properties", "city_id")
        counts[city] += 1 if city.present?
      rescue Errno::ENOENT, JSON::ParserError
        # Parallel tests may delete files between Dir.glob and File.read.
        nil
      end
      counts
    end

    def uses_bands?(city_id)
      route_counts[city_id.to_s].to_i >= MIN_ROUTES_FOR_BANDS
    end

    def intercity_operator_dir(operator_id:, operator_name: nil)
      raw = operator_id.presence || operator_name.presence || "unknown"
      raw.to_s.parameterize(separator: "_").presence || "unknown"
    end

    def band_dir(city_id:, ref:, slug: nil)
      Geojson::BusCatalog.browse_band_dir(ref.presence || ref_from_slug(slug), city_id:)
    end

    def geojson_relative_parts(city_id:, slug:, ref: nil, operator_id: nil, operator_name: nil)
      subdir = subdir_for(city_id)
      filename = "#{slug}.geojson"
      return [ filename ] if subdir.blank?

      parts = [ subdir ]
      case city_id.to_s
      when "InterCity"
        parts << intercity_operator_dir(operator_id:, operator_name:)
      else
        parts << band_dir(city_id:, ref:, slug:) if uses_bands?(city_id)
      end
      parts << filename
    end

    def geojson_path(city_id:, slug:, ref: nil, operator_id: nil, operator_name: nil)
      bus_root.join(*geojson_relative_parts(city_id:, slug:, ref:, operator_id:, operator_name:))
    end

    def find_geojson(slug)
      matches = Dir.glob(bus_root.join("**/#{slug}.geojson"))
      return nil if matches.empty?

      Pathname.new(matches.min_by { |path| path.count("/") })
    end

    def maps_dir(city_id:)
      subdir = subdir_for(city_id)
      return bus_root.join("maps") if subdir.blank?

      bus_root.join(subdir, "maps")
    end

    def public_url(path)
      relative = Pathname.new(path).relative_path_from(Rails.root.join("public"))
      "/#{relative}"
    end

    def ref_from_slug(slug)
      slug.to_s.sub(/\A[a-z0-9_]+_/, "").tr("_", " ")
    end
  end
end
