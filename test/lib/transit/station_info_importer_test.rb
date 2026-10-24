# frozen_string_literal: true

require "test_helper"

class Transit::StationInfoImporterTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :paths

    def initialize(responses)
      @responses = responses
      @paths = []
    end

    def fetch_all(path)
      @paths << path
      response = @responses.fetch(path, [])
      raise response if response.is_a?(Exception)

      response
    end
  end

  test "stores one row per station with one request per system and dataset" do
    client = FakeClient.new(
      "v2/Rail/Metro/StationExit/TRTC" => [ { "StationID" => "BL01", "ExitID" => "1" }, { "StationID" => "BL01", "ExitID" => "2" } ],
      "v2/Rail/Metro/StationFacility/TRTC" => [ { "StationID" => "BL02", "Toilets" => [] } ]
    )

    result = Transit::StationInfoImporter.import!(client:, systems: %w[TRTC])

    assert_equal({ stations: 2, failed: [] }, result)
    assert_equal %w[v2/Rail/Metro/StationExit/TRTC v2/Rail/Metro/StationFacility/TRTC], client.paths
    assert_equal %w[1 2], StationInfo.find_by!(system: "TRTC", station_id: "BL01").exits.map { |row| row["ExitID"] }
    assert_equal 1, StationInfo.find_by!(system: "TRTC", station_id: "BL02").facilities.size
  end

  test "keeps previous rows for a system whose download fails or comes back empty" do
    Transit::StationInfoImporter.store_system!("TRA", exits: [ { "StationID" => "1000" } ], facilities: [])
    Transit::StationInfoImporter.store_system!("KRTC", exits: [ { "StationID" => "R10" } ], facilities: [])
    client = FakeClient.new("v3/Rail/TRA/StationExit" => Transit::TdxClient::RequestError.new("TDX 500"))

    result = Transit::StationInfoImporter.import!(client:, systems: %w[TRA KRTC])

    assert_equal %w[TRA KRTC], result[:failed]
    assert StationInfo.exists?(system: "TRA", station_id: "1000")
    assert StationInfo.exists?(system: "KRTC", station_id: "R10")
  end

  test "drops stations a refresh no longer lists" do
    Transit::StationInfoImporter.store_system!("TRTC", exits: [ { "StationID" => "BL01" }, { "StationID" => "BL99" } ], facilities: [])
    Transit::StationInfoImporter.store_system!("TRTC", exits: [ { "StationID" => "BL01" } ], facilities: [])

    assert_equal %w[BL01], StationInfo.where(system: "TRTC").pluck(:station_id)
  end
end
