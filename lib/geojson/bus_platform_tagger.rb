# frozen_string_literal: true

module Geojson
  # Tags stops at multi-platform terminals (新北板橋公車站, 林口轉運站, …) with
  # their platform. TDX keeps it only in StopAddress, e.g.
  # 「縣民大道公車專用月台第四月台(向東)」; Taichung already puts it in StopName.
  module BusPlatformTagger
    PLATFORM_PATTERN = /(?:第|交)?[0-9０-９一二三四五六七八九十A-Z]+(?:號[0-9０-９]+)*號?月台/

    module_function

    def platform_from(address)
      address.to_s.scan(PLATFORM_PATTERN).last
    end

    # { StopUID => platform } for every city whose TDX stops mention one.
    def fetch_platforms(client: Transit::TdxClient.new(ignore_breaker: true))
      Geojson::BusCatalog::CITIES.each_with_object({}) do |city, platforms|
        path = city.kind == :intercity ? "v2/Bus/Stop/InterCity" : "v2/Bus/Stop/City/#{city.tdx_city}"
        rows = Transit::ResponseDecoder.list(client.get_json(path, query: {
          "$filter" => "StopAddress ne null and contains(StopAddress,'月台')",
          "$select" => "StopUID,StopAddress",
          "$format" => "JSON"
        }))
        rows.each do |row|
          platform = platform_from(row["StopAddress"])
          platforms[row["StopUID"]] = platform if platform && row["StopUID"].present?
        end
      rescue Transit::TdxClient::Error => error
        Rails.logger.warn("BusPlatformTagger: #{city.id} skipped (#{error.message.first(120)})")
      end
    end

    def tag_collection!(data, platforms)
      changed = false
      Array(data["features"]).each do |feature|
        properties = feature["properties"] || {}
        next unless properties["feature_type"] == "station"

        platform = platforms[properties["ref"]]
        platform = nil if properties["name"].to_s.include?("月台")
        next if properties["platform"] == platform

        platform ? properties["platform"] = platform : properties.delete("platform")
        changed = true
      end
      changed
    end

    def refresh!(platforms: fetch_platforms, root: Rails.root.join("public/geojson/bus"))
      Dir.glob(root.join("**/*.geojson")).sort.count do |path|
        next false if File.basename(path).start_with?("_")

        data = JSON.parse(File.read(path))
        next false unless tag_collection!(data, platforms)

        File.write(path, "#{JSON.pretty_generate(data)}\n")
        true
      rescue JSON::ParserError
        false
      end
    end
  end
end
