# frozen_string_literal: true

require "test_helper"

class GeojsonBusManualImporterTest < ActiveSupport::TestCase
  setup do
    @route_file = Rails.root.join("public/geojson/bus/kaohsiung_bus/kaohsiung_h21.geojson")
    @backup = @route_file.exist? ? @route_file.read : nil
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

    @annotations = Rails.root.join("docs/bus_data_gaps/missing_official_maps.md")
    @annotations_backup = @annotations.read if @annotations.exist?
    File.write(
      @annotations,
      <<~MARKDOWN
        # test
        - `H21` H21 (`kaohsiung_h21`)      <- https://example.test/h21.png
      MARKDOWN
    )
  end

  teardown do
    if @backup
      File.write(@route_file, @backup)
    else
      FileUtils.rm_f(@route_file)
    end

    if @annotations_backup
      File.write(@annotations, @annotations_backup)
    else
      FileUtils.rm_f(@annotations)
    end
  end

  test "applies annotated official map urls to on-disk geojson" do
    result = Geojson::BusManualImporter.import!(rewrite_manifest: false)

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

    result = Geojson::BusManualImporter.import!(rewrite_manifest: false)

    assert_includes result.updated_slugs, "kaohsiung_h21"
    data = JSON.parse(@route_file.read)
    assert_equal "https://example.test/h21-nospace.png", data.dig("properties", "official_map_url")
  end
end
