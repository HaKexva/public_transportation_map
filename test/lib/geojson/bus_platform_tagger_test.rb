# frozen_string_literal: true

require "test_helper"

class Geojson::BusPlatformTaggerTest < ActiveSupport::TestCase
  test "reads the platform out of a TDX stop address" do
    {
      "縣民大道公車專用月台第四月台(向東)" => "第四月台",
      "林口區文化三路一段6號第1月台(向北)" => "第1月台",
      "臺北國際航空站1號2號月台候車亭右邊(向西)" => "1號2號月台",
      "臺北市中正區忠孝西路1段72號對面(交6月台站區)(向西)" => "交6月台"
    }.each do |address, platform|
      assert_equal platform, Geojson::BusPlatformTagger.platform_from(address), address
    end
    assert_nil Geojson::BusPlatformTagger.platform_from("北新路一段捷運站接駁月台(向南)")
  end

  test "tags matching stops and skips names that already carry a platform" do
    data = {
      "features" => [
        { "properties" => { "feature_type" => "station", "ref" => "NWT1", "name" => "新北板橋公車站" } },
        { "properties" => { "feature_type" => "station", "ref" => "TXG1", "name" => "臺中車站(A月台)" } },
        { "properties" => { "feature_type" => "route" } }
      ]
    }

    assert Geojson::BusPlatformTagger.tag_collection!(data, { "NWT1" => "第四月台", "TXG1" => "第1月台" })
    assert_equal "第四月台", data["features"][0]["properties"]["platform"]
    assert_nil data["features"][1]["properties"]["platform"]
    assert_not Geojson::BusPlatformTagger.tag_collection!(data, { "NWT1" => "第四月台" })
  end
end
