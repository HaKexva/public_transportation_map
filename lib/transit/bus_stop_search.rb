# frozen_string_literal: true

require "json"

module Transit
  # Sidebar lookup over `public/geojson/bus/_stop_search.json`.
  class BusStopSearch
    LIMIT = 15
    Stop = Data.define(
      :name, :name_en, :lat, :lon, :group_id, :platform, :platform_en,
      :road, :road_en, :toward, :toward_en, :stop_uid, :cities,
      :norm_name, :norm_en, :norm_extra
    )

    def self.normalize(text)
      text.to_s.unicode_normalize(:nfkc).tr("臺", "台").downcase.gsub(/[[:space:]]+/, "")
    end

    def self.ready?(needle)
      return false if needle.length < 2
      return false if needle.match?(/\A[a-z0-9]+\z/) && needle.length < 3

      true
    end

    def self.reset_cache!
      @index_lock ||= Mutex.new
      @index_lock.synchronize { @index_cache = {} }
    end

    def self.index(bus_root: nil)
      root = bus_root || Geojson::BusLayout.bus_root
      path = Geojson::BusStopSearchIndex.path(bus_root: root)
      return [] unless path.exist?

      key = [ path.to_s, path.mtime.to_f ]
      @index_lock ||= Mutex.new
      @index_cache ||= {}
      @index_lock.synchronize do
        return @index_cache[key] if @index_cache.key?(key)

        @index_cache.clear
        @index_cache[key] = load_index(path)
      end
    end

    def self.load_index(path)
      payload = JSON.parse(path.read)
      rows = payload.is_a?(Hash) ? payload["stops"] : payload
      Array(rows).filter_map { |row| stop_from(row) }
    rescue JSON::ParserError
      []
    end

    def self.stop_from(row)
      return unless row.is_a?(Array) && row.length >= 13

      name, name_en, lat, lon, group_id, platform, platform_en, road, road_en, toward, toward_en, stop_uid, cities = row
      cities = Array(cities).map(&:to_s).reject(&:blank?)
      return if name.blank? || cities.empty?

      extra = [ road, road_en, toward, toward_en, platform, platform_en ].map { |field| normalize(field) }.reject(&:blank?).join("\u0001")
      Stop.new(
        name: name.to_s,
        name_en: name_en.to_s,
        lat: lat.to_f,
        lon: lon.to_f,
        group_id: group_id.to_s,
        platform: platform.to_s.presence,
        platform_en: platform_en.to_s.presence,
        road: road.to_s.presence,
        road_en: road_en.to_s.presence,
        toward: toward.to_s.presence,
        toward_en: toward_en.to_s.presence,
        stop_uid: stop_uid.to_s.presence,
        cities: cities,
        norm_name: normalize(name),
        norm_en: normalize(name_en),
        norm_extra: extra
      )
    end

    def initialize(query:, city_id: nil, bus_root: nil)
      @query = query.to_s
      @city_id = city_id.to_s.presence
      @bus_root = bus_root
    end

    def call
      needle = self.class.normalize(@query)
      return [] unless self.class.ready?(needle)

      named = []
      mentioned = []
      self.class.index(bus_root: @bus_root).each do |stop|
        next unless city_match?(stop)

        rank = rank_for(stop, needle)
        next unless rank

        row = [ rank, stop.name.length, stop.name, stop.group_id, stop ]
        if rank <= 3
          named << row
        else
          mentioned << row
        end
      end
      # A stop name wins over poles that only head toward it or stand on a
      # street with the same words. Street and "toward" matches fill in when
      # nothing is actually called that.
      ranked = named.presence || mentioned
      ranked.sort_by! { |rank, length, name, id, _stop| [ rank, length, name, id ] }
      ranked.first(LIMIT).map { |(_rank, _length, _name, _id, stop)| serialize(stop) }
    end

    private

    # Sidebar browse uses GreaterTaipei as a fold over Taipei + NewTaipei.
    # Stop poles store the concrete city ids, never the fold name.
    def city_match?(stop)
      return true if @city_id.blank?
      return stop.cities.intersect?(Geojson::BusCatalog::GREATER_TAIPEI_CITY_IDS) if @city_id == "GreaterTaipei"

      stop.cities.include?(@city_id)
    end

    def rank_for(stop, needle)
      return 0 if stop.norm_name == needle || (stop.norm_en.present? && stop.norm_en == needle)
      return 1 if stop.norm_name.start_with?(needle) || stop.norm_en.start_with?(needle)
      return 2 if stop.norm_name.include?(needle)
      return 3 if stop.norm_en.present? && stop.norm_en.include?(needle)
      return 4 if stop.norm_extra.include?(needle)

      nil
    end

    def serialize(stop)
      english = I18n.locale.to_s.start_with?("en")
      platform = english && stop.platform_en.present? ? stop.platform_en : stop.platform
      {
        "name" => stop.name,
        "label" => english && stop.name_en.present? ? stop.name_en : stop.name,
        "name_en" => stop.name_en.presence,
        "place" => place(stop, english),
        "city" => city_label(stop.cities.first),
        "city_id" => stop.cities.first,
        "city_ids" => stop.cities,
        "lat" => stop.lat,
        "lon" => stop.lon,
        "group_id" => stop.group_id,
        "station_id" => station_id(stop),
        "platform" => stop.platform,
        "platform_en" => stop.platform_en,
        "platform_label" => platform,
        "stop_uid" => stop.stop_uid
      }.compact
    end

    def place(stop, english)
      road = localized(stop.road, stop.road_en, english)
      toward = localized(stop.toward, stop.toward_en, english)
      platform = localized(stop.platform, stop.platform_en, english)
      where = if road.present? && toward.present?
        I18n.t("js.bus.stop_group_road_toward", road: road, toward: toward)
      elsif toward.present?
        I18n.t("js.bus.stop_group_toward", toward: toward)
      else
        road
      end
      [ platform, where ].compact_blank.join(" · ")
    end

    def localized(zh, en, english)
      english && en.present? ? en : zh
    end

    def city_label(city_id)
      I18n.t("map.bus.cities.#{city_id}", default: city_id.to_s)
    end

    # Cluster keys look like "25.1318|121.7394|站名". Station ids do not.
    def station_id(stop)
      key = stop.group_id
      return if key.blank? || key.include?("|")

      stop.platform.present? && key.include?("@") ? key.split("@", 2).first : key
    end
  end
end
