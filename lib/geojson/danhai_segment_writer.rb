# frozen_string_literal: true

require "json"

module Geojson
  # Splits the combined danhai_lrt.geojson into separate Green Mountain (綠山)
  # and Blue Coast (藍海) map layers, matching airport_mrt / airport_mrt_express.
  class DanhaiSegmentWriter
    SEGMENTS = {
      "lushan" => {
        id: "danhai_lushan",
        name: "淡海輕軌綠山線",
        name_en: "Danhai LRT Green Mountain Line",
        include_depot: true
      },
      "lanhai" => {
        id: "danhai_lanhai",
        name: "淡海輕軌藍海線",
        name_en: "Danhai LRT Blue Coast Line",
        include_depot: false
      }
    }.freeze

    def self.write!(source_path: Rails.root.join("public/geojson/new_taipei_metro/danhai_lrt.geojson"))
      new(source_path: source_path).write!
    end

    def initialize(source_path:)
      @source_path = Pathname(source_path)
    end

    def write!
      raise "Missing #{@source_path}" unless @source_path.exist?

      source = JSON.parse(@source_path.read)
      features = Array(source["features"])

      SEGMENTS.each do |segment, meta|
        selected = features.select { |feature| include_feature?(feature, segment, meta) }
        raise "No #{segment} features in #{@source_path}" if selected.empty?

        collection = {
          type: "FeatureCollection",
          name: meta[:name],
          properties: {
            source: "Split from #{@source_path.basename} (segment=#{segment}).",
            network: "淡海輕軌",
            ref: "V",
            segment: segment
          },
          features: selected
        }

        output_path = @source_path.dirname.join("#{meta[:id]}.geojson")
        File.write(output_path, JSON.pretty_generate(collection))
        puts "Wrote #{output_path} (#{selected.length} features)"
      end
    end

    private

    def include_feature?(feature, segment, meta)
      props = feature["properties"] || {}
      feature_type = props["feature_type"]

      return meta[:include_depot] if feature_type == "depot_spur"
      return props["segment"] == segment if feature_type == "route" || feature_type == "station"

      false
    end
  end
end
