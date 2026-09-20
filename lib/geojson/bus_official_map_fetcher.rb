# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Geojson
  # Fills missing official_map_url from TDX Route metadata and operator portals.
  # TDX often returns HTML portal pages (MapOverview / route-map); those are resolved
  # to direct image URLs so the sidebar <img> can display them.
  class BusOfficialMapFetcher
    Result = Data.define(:updated, :skipped, :still_missing)

    TAICHUNG_CITYBUS = "https://citybus.taichung.gov.tw/ebus/route-map/"
    TAICHUNG_TCBUS = "https://www.tcbus.com.tw/image/lineimage.php?imagetest="
    TAOYUAN_EBUS = "https://ebus.tycg.gov.tw/ebus/driving-map/"
    UBUS_TAOYUAN = "https://www.ubus.com.tw/UrbanBus/TaoyuanBus/"

    IMAGE_EXT = /\.(?:jpe?g|png|gif|webp|pdf)(?:\?|#|$)/i
    DIRECT_IMAGE_HINT = %r{
      /File/Get/|
      /strapi/uploads/|
      /(?:cms/)?api/route/.+/(?:map/.+/)?image|
      /cms/api/.+/image|
      /cms/api/route/.+/map/|
      /MISUploadData/Schematic/|
      /resources/PathPic/|
      /Upload/LineImages/|
      /files/bus/
    }ix

    PORTAL_HINT = %r{
      MapOverview|
      /ebus/route-map/|
      lineimage\.php|
      /ebus/driving-map/|
      routemap\.php|
      matsutransit\.com/?$|
      /ebus/strapi/?$|
      traffic\.taichung\.gov\.tw/form/
    }ix

    USELESS_PORTAL = %r{
      ebus\.tycg\.gov\.tw/ebus/driving-map/|
      \Ahttps?://www\.matsutransit\.com/?\z|
      citybus\.taichung\.gov\.tw/ebus/strapi/?\z|
      traffic\.taichung\.gov\.tw/form/
    }ix

    OPERATOR_BUILDERS = {
      "台中客運" => :tcbus_map,
      "中鹿客運" => :tcbus_map,
      "豐原客運" => :fuyuan_map,
      "中台灣客運" => :tcbus_map,
      "巨業交通" => :tcbus_map,
      "全航客運" => :tcbus_map,
      "國光客運" => :kokuang_map,
      "統聯客運" => :ubus_taoyuan_map,
      "桃園客運" => :taoyuan_ebus_map,
      "捷乘客運" => :taoyuan_ebus_map,
      "亞通客運" => :taoyuan_ebus_map,
      "台灣真好" => :taoyuan_ebus_map,
      "九億租車" => :taoyuan_ebus_map
    }.freeze

    def self.sync!(city_ids: nil, resolve_portals: true, rewrite_manifest: true, sync_tdx: true)
      new(city_ids:, resolve_portals:, rewrite_manifest:, sync_tdx:).sync!
    end

    def initialize(city_ids: nil, resolve_portals: true, rewrite_manifest: true, sync_tdx: true)
      @city_ids = Array(city_ids).map(&:to_s).reject(&:blank?)
      @resolve_portals = resolve_portals
      @rewrite_manifest = rewrite_manifest
      @sync_tdx = sync_tdx
      @resolve_cache = {}
      @resolve_cache_mutex = Mutex.new
    end

    def sync!
      updated = []
      skipped = []

      # Convert stored HTML portal pages first — this is what makes the sidebar <img> work.
      rewrite_existing_portal_urls!(updated, skipped)
      sync_tdx_routes!(updated, skipped) if @sync_tdx
      resolve_portal_maps!(updated, skipped) if @resolve_portals

      Geojson::RoutesManifestWriter.write! if @rewrite_manifest && updated.any?
      still_missing = missing_slugs
      Result.new(updated: updated.uniq, skipped: skipped, still_missing: still_missing)
    end

    # Public so importers / tests can convert a TDX portal URL to an <img>-safe URL.
    def resolve_direct_image_url(url)
      text = url.to_s.strip
      return if text.blank?

      @resolve_cache_mutex.synchronize do
        return @resolve_cache[text] if @resolve_cache.key?(text)
      end

      resolved =
        if direct_image_url?(text)
          text
        elsif text.match?(%r{ebus\.gov\.taipei/MapOverview}i)
          resolve_taipei_map_overview(text)
        elsif text.match?(%r{citybus\.taichung\.gov\.tw/ebus/route-map/}i)
          resolve_taichung_route_map(text)
        elsif text.match?(%r{tcbus\.com\.tw/image/lineimage\.php}i)
          resolve_tcbus_lineimage(text)
        elsif text.match?(%r{ebus\.kinmen\.gov\.tw/.+routemap\.php}i)
          resolve_kinmen_routemap(text)
        elsif text.match?(USELESS_PORTAL)
          nil
        elsif text.match?(%r{ebus\.tycg\.gov\.tw/ebus/driving-map/}i)
          nil # SPA shell; TDX cms /image URLs are used instead
        else
          text
        end

      @resolve_cache_mutex.synchronize { @resolve_cache[text] = resolved }
      resolved
    end

    private

    def selected_cities
      cities = Geojson::BusCatalog.cities
      return cities if @city_ids.empty?

      cities.select { |city| @city_ids.include?(city.id) }
    end

    def client
      @client ||= Transit::TdxClient.new
    end

    def sync_tdx_routes!(updated, skipped)
      return unless client.configured?

      selected_cities.each do |city|
        Geojson::BusImporter.grouped_routes(client.fetch_all(Geojson::BusImporter.route_path_for(city)), city:, series: nil)
          .each do |slug, group, _distinguish_via, _unlabeled_via|
            route = group.first
            url = route["RouteMapImageUrl"].to_s.presence || route["RouteMapUrl"].to_s.presence
            next if url.blank?

            apply_url!(slug, url) ? updated << slug : skipped << "#{slug} (unresolved or file missing)"
          end
      end
    rescue Transit::TdxClient::ConfigurationError
      skipped << "TDX credentials missing"
    end

    def resolve_portal_maps!(updated, skipped)
      missing_slugs.each do |slug|
        path = Geojson::BusLayout.find_geojson(slug)
        next unless path

        data = JSON.parse(path.read)
        properties = data["properties"] || {}
        next if properties["official_map_url"].present?

        city_id = properties["city_id"]
        ref = properties["ref"]
        operator = properties["operator"]
        url = portal_url_for(city_id:, ref:, operator:)
        next if url.blank?

        apply_url!(slug, url) ? updated << slug : skipped << "#{slug} (apply failed)"
      rescue JSON::ParserError
        skipped << slug
      end
    end

    def rewrite_existing_portal_urls!(updated, skipped)
      jobs = Dir.glob(Rails.root.join("public/geojson/bus/**/*.geojson")).filter_map do |path|
        data = JSON.parse(File.read(path))
        properties = data["properties"] || {}
        current = properties["official_map_url"].to_s
        next if current.blank? || !portal_url?(current)

        slug = properties["id"].presence || File.basename(path, ".geojson")
        [ slug, current, properties["ref"], properties["city_id"] ]
      rescue JSON::ParserError
        skipped << path
        nil
      end

      mutex = Mutex.new
      jobs.each_slice(24) do |batch|
        threads = batch.map do |slug, current, ref, city_id|
          Thread.new do
            url = rewrite_source_url(current, ref:, city_id:)
            ok = apply_url!(slug, url, allow_clear: true)
            mutex.synchronize do
              if ok
                updated << slug
              else
                skipped << "#{slug} (portal unresolved)"
              end
            end
          end
        end
        threads.each(&:join)
        puts "  resolved portal maps: #{updated.size} updated so far (#{jobs.size} candidates)"
      end
    end

    def rewrite_source_url(current, ref:, city_id:)
      return current unless current.match?(%r{citybus\.taichung\.gov\.tw/ebus/strapi/?\z}i)
      return current unless city_id.to_s == "Taichung"

      taichung_citybus_url(ref).presence || current
    end

    def portal_url_for(city_id:, ref:, operator:)
      case city_id.to_s
      when "InterCity"
        return intercity_schematic_url(ref)
      end

      builder = OPERATOR_BUILDERS[operator.to_s]
      return send(builder, ref) if builder

      case city_id.to_s
      when "Taichung"
        taichung_citybus_url(ref)
      when "Taoyuan"
        nil # driving-map is an SPA; rely on TDX cms image URLs
      when "Kaohsiung"
        kaohsiung_operator_url(ref, operator)
      end
    end

    # 公路總局台灣好行／公路客運示意圖（業者官網常連到同一來源）。
    def intercity_schematic_url(ref)
      text = ref.to_s.strip
      return if text.blank?

      candidates = [ text, text.sub(/[A-J]\z/i, "") ].uniq
      candidates.each do |candidate|
        next if candidate.blank?

        url = "https://web.taiwanbus.tw/MISUploadData/Schematic/file/#{candidate}.jpg"
        return url if http_ok?(url)
      end
      nil
    end

    def tcbus_map(ref)
      num = ref[/\d+/]
      return if num.blank?

      url = "#{TAICHUNG_TCBUS}#{num}"
      resolve_tcbus_lineimage(url) || (url if tcbus_map_exists?(url))
    end

    def fuyuan_map(ref)
      num = ref[/\d+/]
      return if num.blank?

      url = "https://www.fybus.com.tw/Upload/LineImages/#{num}.jpg"
      url if http_ok?(url)
    end

    def kokuang_map(ref)
      num = ref.to_s[/\d+/]
      return if num.blank?

      intercity_schematic_url(num)
    end

    def ubus_taoyuan_map(ref)
      token = ref.to_s.gsub(/\s+/, "")
      url = "#{UBUS_TAOYUAN}#{token}/#{token}.png"
      url if http_ok?(url)
    end

    def taoyuan_ebus_map(_ref)
      nil
    end

    def tcbus_map_exists?(url)
      body = http_get_body(url)
      body&.include?("lineimage") || body&.include?(".gif") || body&.include?(".jpg")
    rescue StandardError
      false
    end

    def http_ok?(url)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5) do |http|
        http.head(uri.request_uri)
      end
      response.code.to_i < 400
    rescue StandardError
      false
    end

    def taichung_citybus_url(ref)
      candidates_for(ref).find { |id| taichung_map_exists?(id) }&.then { |id| "#{TAICHUNG_CITYBUS}#{id}" }
    end

    def candidates_for(ref)
      text = ref.to_s
      list = []
      if (match = text.match(/\A黃(\d+)/))
        n = match[1].to_i
        list.concat([ n, 4000 + (n * 10) + 1, 4010 + (n * 10), 5000 + n ])
      elsif (match = text.match(/\A綠(\d+)/))
        n = match[1].to_i
        list << (4010 + (n * 10))
      elsif (match = text.match(/\A市民小巴(\d+)/))
        n = match[1].to_i
        list.concat([ 9000 + n, 8000 + n, n ])
      elsif text.match?(/\A梨山1路/)
        list << 1
      elsif (num = text[/\A(\d+)/, 1])
        list << num.to_i
        list << "#{num}1" if text.match?(/延|副/)
        list << "#{num}2" if text.match?(/副2|區2/)
        list << "#{num}3" if text.match?(/區3/)
        list << "#{num}qu" if text.match?(/區/)
      end
      list.map(&:to_s).uniq
    end

    def taichung_map_exists?(id)
      body = http_get_body("#{TAICHUNG_CITYBUS}#{id}")
      body&.include?("uploads/")
    rescue StandardError
      false
    end

    def kaohsiung_operator_url(ref, operator)
      case operator.to_s
      when /福倫/
        return "https://www.kstaxi.com.tw/files/bus/H51_20211006_%E5%B7%A5%E4%BD%9C%E5%8D%80%E5%9F%9F%201.jpg?1639367194" if ref.start_with?("T5")
      when /高雄客運/
        return nil if ref.include?("測試")
      end
      nil
    end

    def apply_url!(slug, url, allow_clear: false)
      path = Geojson::BusLayout.find_geojson(slug)
      return false unless path&.exist?

      resolved = resolve_direct_image_url(url)
      data = JSON.parse(path.read)
      properties = data["properties"] ||= {}
      current = properties["official_map_url"].to_s

      if resolved.present?
        return true if current == resolved

        properties["official_map_url"] = resolved
      elsif allow_clear && (useless_portal?(url) || portal_url?(url))
        return true if current.blank?

        properties.delete("official_map_url")
      else
        return false
      end

      path.write("#{JSON.pretty_generate(data)}\n")
      true
    rescue JSON::ParserError
      false
    end

    def useless_portal?(url)
      url.match?(USELESS_PORTAL)
    end

    def missing_slugs
      Geojson::RoutesManifestWriter.bus_entries.select { |route|
        route["official_map_url"].to_s.empty?
      }.map { |route| route["id"] }
    end

    def direct_image_url?(url)
      url.match?(IMAGE_EXT) || url.match?(DIRECT_IMAGE_HINT)
    end

    def portal_url?(url)
      url.match?(PORTAL_HINT)
    end

    def resolve_taipei_map_overview(url)
      body = http_get_body(url)
      return unless body

      match = body.match(%r{src=["']?(\./File/Get/[^"'>\s]+)}i) ||
        body.match(%r{src=["']?(https?://ebus\.gov\.taipei/File/Get/[^"'>\s]+)}i)
      return unless match

      src = match[1]
      return if src.blank? || src.match?(%r{\.(?:undefined)?(?:\?|$)}i) || src == "."

      src = URI.join("https://ebus.gov.taipei/", src).to_s if src.start_with?(".")
      return unless src.include?("/File/Get/")

      src
    end

    def resolve_taichung_route_map(url)
      body = http_get_body(url)
      return unless body

      match = body.match(%r{src=["']?(https?://citybus\.taichung\.gov\.tw/ebus/strapi/uploads/[^"'>\s]+)}i) ||
        body.match(%r{src=["']?([^"'>\s]*strapi/uploads/[^"'>\s]+)}i)
      return unless match

      src = match[1]
      src = URI.join("https://citybus.taichung.gov.tw/", src).to_s unless src.start_with?("http")
      src
    end

    def resolve_tcbus_lineimage(url)
      body = http_get_body(url)
      return unless body

      match = body.match(%r{src=["']?(\d+\.gif)}i) ||
        body.match(%r{src=["']?(https?://www\.tcbus\.com\.tw/image/\d+\.gif)}i)
      return unless match

      src = match[1]
      src = "https://www.tcbus.com.tw/image/#{src}" unless src.start_with?("http")
      src
    end

    def resolve_kinmen_routemap(url)
      body = http_get_body(url)
      return unless body

      match = body.match(%r{src=["']?(https?://ebus\.kinmen\.gov\.tw/[^"'>\s]+)}i) ||
        body.match(%r{src=["']?(/cms/api/route/[^"'>\s]+/image)}i) ||
        body.match(%r{src=["']?(/extend/[^"'>\s]+\.(?:png|jpe?g|gif))}i)
      return unless match

      src = match[1]
      src = URI.join("https://ebus.kinmen.gov.tw/", src).to_s unless src.start_with?("http")
      return unless src.match?(IMAGE_EXT) || src.include?("/image")

      src
    end

    def http_get_body(url)
      uri = encode_uri(url)
      return unless uri

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 8, read_timeout: 12) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "PublicTransportationMap/1.0"
        response = http.request(request)
        return unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s.force_encoding("UTF-8")
      end
    rescue StandardError
      nil
    end

    def encode_uri(url)
      uri = URI.parse(url)
      if uri.query
        pairs = URI.decode_www_form(uri.query)
        uri.query = URI.encode_www_form(pairs)
      end
      uri
    rescue ArgumentError, URI::InvalidURIError
      match = url.to_s.match(/\A(https?:\/\/[^?]+\?)(.+)\z/)
      return unless match

      encoded_query = match[2].split("&").map { |part|
        key, value = part.split("=", 2)
        "#{key}=#{URI.encode_www_form_component(value.to_s)}"
      }.join("&")
      URI.parse("#{match[1]}#{encoded_query}")
    rescue StandardError
      nil
    end
  end
end
