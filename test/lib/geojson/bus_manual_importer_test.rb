# frozen_string_literal: true

require "test_helper"

class GeojsonBusManualImporterTest < ActiveSupport::TestCase
  setup do
    token = "#{Process.pid}_#{SecureRandom.hex(4)}"
    @isolated_bus_root = Rails.root.join("tmp/bus_manual_importer_#{token}")
    FileUtils.mkdir_p(@isolated_bus_root)
    @previous_bus_root = Geojson::BusLayout.instance_variable_get(:@bus_root_override)
    @previous_route_counts = Geojson::BusLayout.instance_variable_get(:@route_counts)
    Geojson::BusLayout.bus_root = @isolated_bus_root

    @route_file = Geojson::BusLayout.geojson_path(
      city_id: "Kaohsiung",
      slug: "kaohsiung_h21",
      ref: "H21"
    )
    FileUtils.mkdir_p(@route_file.dirname)
    File.write(
      @route_file,
      JSON.pretty_generate(
        {
          "type" => "FeatureCollection",
          "properties" => {
            "id" => "kaohsiung_h21",
            "ref" => "H21",
            "city_id" => "Kaohsiung"
          },
          "features" => []
        }
      )
    )

    @annotations = Rails.root.join("tmp/bus_manual_annotations_#{token}.md")
    File.write(
      @annotations,
      <<~MARKDOWN
        # test
        - `H21` H21 (`kaohsiung_h21`)      <- https://example.test/h21.png
      MARKDOWN
    )
  end

  teardown do
    Geojson::BusLayout.instance_variable_set(:@bus_root_override, @previous_bus_root)
    Geojson::BusLayout.instance_variable_set(:@route_counts, @previous_route_counts)
    FileUtils.rm_rf(@isolated_bus_root) if @isolated_bus_root
    FileUtils.rm_f(@annotations) if @annotations
  end

  test "applies annotated official map urls to on-disk geojson" do
    result = Geojson::BusManualImporter.import!(rewrite_manifest: false, annotations: @annotations)

    assert_includes result.updated_slugs, "kaohsiung_h21"
    data = JSON.parse(@route_file.read)
    assert_equal "https://example.test/h21.png", data.dig("properties", "official_map_url")
  end

  test "accepts annotation arrow without space before url" do
    File.write(
      @annotations,
      <<~MARKDOWN
        # test
        - `H21` H21 (`kaohsiung_h21`)      <-https://example.test/h21-nospace.png
      MARKDOWN
    )

    result = Geojson::BusManualImporter.import!(rewrite_manifest: false, annotations: @annotations)

    assert_includes result.updated_slugs, "kaohsiung_h21"
    data = JSON.parse(@route_file.read)
    assert_equal "https://example.test/h21-nospace.png", data.dig("properties", "official_map_url")
  end
end
