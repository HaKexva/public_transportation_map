# frozen_string_literal: true

require "test_helper"

class Geojson::RoutesManifestWriterTest < ActiveSupport::TestCase
  test "rail entries carry a bounding box for nearby lookups" do
    Dir.mktmpdir do |dir|
      path = Pathname.new(dir).join("routes.json")
      capture_io { Geojson::RoutesManifestWriter.write!(path: path, bus_path: nil) }
      manifest = JSON.parse(path.read)

      hsr = manifest.fetch("hsr").find { |entry| entry["id"] == "taiwan_hsr" }
      min_lng, min_lat, max_lng, max_lat = hsr.fetch("bbox")
      assert_operator min_lng, :<, max_lng
      assert_operator min_lat, :<, max_lat
      assert_in_delta 120.3, min_lng, 0.3
      assert_in_delta 25.05, max_lat, 0.1
    end
  end
end
