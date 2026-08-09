# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderTaipeiTransfersTest < ActiveSupport::TestCase
  test "injects missing 忠孝復興 transfer station for taipei metro lines" do
    line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "wenhu_line" }
    builder = Geojson::MetroLineBuilder.new(line)
    stations = []

    builder.send(:apply_taipei_in_station_transfers!, stations)

    station = stations.find { |entry| entry[:name] == "忠孝復興" }
    assert station, "expected 忠孝復興 to be injected when missing from OSM"
    assert_equal "BR10;BL15", station[:ref]
    assert_in_delta 121.543333, station[:lon], 0.0001
    assert_in_delta 25.041389, station[:lat], 0.0001
    assert_nil stations.find { |entry| entry[:name] == "古亭" }
    assert_nil stations.find { |entry| entry[:name] == "景安" }
  end

  test "injects 板橋 three-line transfer on bannan but not circular" do
    bannan = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "bannan" }
    circular = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "circular" }

    bannan_builder = Geojson::MetroLineBuilder.new(bannan)
    bannan_stations = []
    bannan_builder.send(:apply_taipei_in_station_transfers!, bannan_stations)

    station = bannan_stations.find { |entry| entry[:name] == "板橋" }
    assert station, "expected 板橋 on 板南線"
    assert_equal "BL07", station[:ref]

    circular_builder = Geojson::MetroLineBuilder.new(circular)
    circular_stations = []
    circular_builder.send(:apply_taipei_in_station_transfers!, circular_stations)
    assert_nil circular_stations.find { |entry| entry[:name] == "板橋" }
  end

  test "banqiao stations are separate on bannan and circular geojson" do
    bannan = JSON.parse(Rails.root.join("public/geojson/taipei_metro/bannan.geojson").read)
    circular = JSON.parse(Rails.root.join("public/geojson/taipei_metro/circular.geojson").read)

    bannan_station = bannan.fetch("features").find do |feature|
      feature.dig("properties", "feature_type") == "station" &&
        feature.dig("properties", "name") == "板橋"
    end
    circular_station = circular.fetch("features").find do |feature|
      feature.dig("properties", "feature_type") == "station" &&
        feature.dig("properties", "name") == "板橋"
    end

    assert_equal "BL07", bannan_station.dig("properties", "ref")
    assert_equal "Y16", circular_station.dig("properties", "ref")
    refute_includes circular_station.dig("properties", "ref"), ";"
  end

  test "injects 忠孝復興 on bannan when missing from OSM" do
    line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "bannan" }
    builder = Geojson::MetroLineBuilder.new(line)
    stations = []

    builder.send(:apply_taipei_in_station_transfers!, stations)

    station = stations.find { |entry| entry[:name] == "忠孝復興" }
    assert station, "expected 忠孝復興 on 板南線"
    assert_equal "BR10;BL15", station[:ref]
    assert_nil stations.find { |entry| entry[:name] == "古亭" }
  end

  test "injects transfer stations on both intersecting lines" do
    %w[songshan_xindian zhonghe_xinlu].each do |slug|
      line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == slug }
      builder = Geojson::MetroLineBuilder.new(line)
      stations = []

      builder.send(:apply_taipei_in_station_transfers!, stations)

      guting = stations.find { |entry| entry[:name] == "古亭" }
      assert guting, "expected 古亭 on #{slug}"
      assert_equal "O05;G09", guting[:ref]
    end
  end

  test "injects missing 東門 transfer station for taipei metro lines" do
    line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "tamsui_xinyi" }
    builder = Geojson::MetroLineBuilder.new(line)
    stations = []

    builder.send(:apply_taipei_in_station_transfers!, stations)

    station = stations.find { |entry| entry[:name] == "東門" }
    assert station, "expected 東門 to be injected when missing from OSM"
    assert_equal "O06;R07", station[:ref]
  end

  test "injects missing 古亭 and 中正紀念堂 transfer stations" do
    line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == "songshan_xindian" }
    builder = Geojson::MetroLineBuilder.new(line)
    stations = []

    builder.send(:apply_taipei_in_station_transfers!, stations)

    guting = stations.find { |entry| entry[:name] == "古亭" }
    cks = stations.find { |entry| entry[:name] == "中正紀念堂" }

    assert guting, "expected 古亭 to be injectable when missing"
    assert_equal "O05;G09", guting[:ref]
    assert cks, "expected 中正紀念堂 to be injectable when missing"
    assert_equal "R08;G10", cks[:ref]
  end

  test "songshan xindian geojson lists 古亭 and 中正紀念堂 between 台電大樓 and 小南門" do
    data = JSON.parse(Rails.root.join("public/geojson/taipei_metro/songshan_xindian.geojson").read)
    stations = data.fetch("features").select do |feature|
      feature.dig("properties", "feature_type") == "station"
    end

    names = stations.map { |feature| feature.dig("properties", "name") }
    assert_includes names, "古亭"
    assert_includes names, "中正紀念堂"
    assert_includes names, "台電大樓"
    assert_includes names, "小南門"
  end

  test "zhonghe xinlu geojson includes 古亭" do
    data = JSON.parse(Rails.root.join("public/geojson/taipei_metro/zhonghe_xinlu.geojson").read)
    names = data.fetch("features")
      .select { |feature| feature.dig("properties", "feature_type") == "station" }
      .map { |feature| feature.dig("properties", "name") }

    assert_includes names, "古亭"
    assert_not_includes names, "中正紀念堂"
  end

  test "each transfer station appears on every line it serves" do
    expected = {
      "忠孝復興" => %w[wenhu_line bannan],
      "古亭" => %w[songshan_xindian zhonghe_xinlu],
      "松江南京" => %w[songshan_xindian zhonghe_xinlu],
      "南京復興" => %w[wenhu_line songshan_xindian],
      "東門" => %w[zhonghe_xinlu tamsui_xinyi],
      "中正紀念堂" => %w[songshan_xindian tamsui_xinyi],
      "中山" => %w[songshan_xindian tamsui_xinyi],
      "大坪林" => %w[songshan_xindian circular],
      "景安" => %w[zhonghe_xinlu circular],
      "頭前庄" => %w[zhonghe_xinlu circular],
      "南港展覽館" => %w[wenhu_line bannan],
      "大安" => %w[wenhu_line tamsui_xinyi]
    }

    expected.each do |name, slugs|
      slugs.each do |slug|
        data = JSON.parse(Rails.root.join("public/geojson/taipei_metro/#{slug}.geojson").read)
        station = data.fetch("features").find do |feature|
          feature.dig("properties", "feature_type") == "station" &&
            feature.dig("properties", "name") == name
        end

        assert station, "expected #{name} on #{slug}"
        assert station.dig("properties", "ref").include?(";"), "expected combined ref for #{name} on #{slug}"
      end
    end
  end

  test "tamsui xinyi geojson includes 大安 and 中正紀念堂 but not 古亭" do
    data = JSON.parse(Rails.root.join("public/geojson/taipei_metro/tamsui_xinyi.geojson").read)
    names = data.fetch("features")
      .select { |feature| feature.dig("properties", "feature_type") == "station" }
      .map { |feature| feature.dig("properties", "name") }

    assert_includes names, "大安"
    assert_includes names, "中正紀念堂"
    assert_not_includes names, "古亭"
  end

  test "tamsui xinyi geojson extends past 象山 to 廣慈/奉天宮 with eastern tail" do
    data = JSON.parse(Rails.root.join("public/geojson/taipei_metro/tamsui_xinyi.geojson").read)
    stations = data.fetch("features").select { |feature| feature.dig("properties", "feature_type") == "station" }
    route = data.fetch("features").find { |feature| feature.dig("properties", "feature_type") == "route" }
    guangci = stations.find { |feature| feature.dig("properties", "ref") == "R01" }
    xiangshan = stations.find { |feature| feature.dig("properties", "ref") == "R02" }

    assert guangci, "expected R01 廣慈/奉天宮"
    assert_equal "廣慈/奉天宮", guangci.dig("properties", "name")
    assert_in_delta 121.58188, guangci.dig("geometry", "coordinates", 0), 0.0005
    assert_in_delta 25.03747, guangci.dig("geometry", "coordinates", 1), 0.0005

    coords = route.dig("geometry", "coordinates")
    max_lon = coords.map { |point| point[0] }.max
    assert_operator max_lon, :>, 121.584, "expected eastern tail beyond 廣慈 toward 玉成公園"

    nearest = coords.min_by do |point|
      Geojson::TrackGeometry.planar_distance_meters(
        point[0], point[1],
        guangci.dig("geometry", "coordinates", 0),
        guangci.dig("geometry", "coordinates", 1)
      )
    end
    dist = Geojson::TrackGeometry.planar_distance_meters(
      nearest[0], nearest[1],
      guangci.dig("geometry", "coordinates", 0),
      guangci.dig("geometry", "coordinates", 1)
    )
    assert_operator dist, :<, 30

    # Corridor: 象山 → 信義路六段(~25.033) → 福德街 → 中坡南路北行(~121.585)
    xs = xiangshan.dig("geometry", "coordinates")
    xs_idx = coords.each_with_index.min_by { |point, _|
      Geojson::TrackGeometry.planar_distance_meters(point[0], point[1], xs[0], xs[1])
    }.last
    gc_idx = coords.each_with_index.min_by { |point, _|
      Geojson::TrackGeometry.planar_distance_meters(
        point[0], point[1],
        guangci.dig("geometry", "coordinates", 0),
        guangci.dig("geometry", "coordinates", 1)
      )
    }.last
    assert_operator gc_idx, :<, xs_idx, "廣慈 should lie east of 象山 on the coordinate array"

    # Between 象山 and 廣慈, stay near 信義路六段 / 福德街 (not a straight NE chord).
    mid = coords[((gc_idx + xs_idx) / 2)]
    assert_operator mid[1], :<, 25.0365, "Xiangshan–Guangci segment should follow 信義路六段/福德街"
    assert_operator mid[1], :>, 25.0325

    # Tail along 中坡南路, ending at 玉成公園外側 (not through park interior).
    tip = coords.first
    assert_in_delta 121.58548, tip[0], 0.0015
    assert_in_delta 25.04156, tip[1], 0.0015
    assert_operator tip[1], :<, 25.0425, "tail must not cross into 玉成公園"
    assert_operator tip[1], :>, 25.0405

    # Tail should follow 中坡南路 with multiple vertices, not a single chord.
    gc_lon = guangci.dig("geometry", "coordinates", 0)
    tail_pts = coords.take_while { |point| point[0] > gc_lon + 0.001 }
    assert_operator tail_pts.length, :>=, 10, "expected detailed 中坡南路 tail east of 廣慈"

    # Just east of 象山, stay on 信義路六段 (~25.033), matching the pre-extension OSM stub.
    near_xs = coords[xs_idx - 1]
    assert_in_delta 25.03292, near_xs[1], 0.00035
    assert_operator near_xs[0], :>, xs[0]
    assert_operator near_xs[0], :<, 121.573
  end

  test "songshan xindian geojson lists 中山 松江南京 南京復興 on the green line" do
    data = JSON.parse(Rails.root.join("public/geojson/taipei_metro/songshan_xindian.geojson").read)
    stations = data.fetch("features").select do |feature|
      feature.dig("properties", "feature_type") == "station"
    end

    names = stations.map { |feature| feature.dig("properties", "name") }
    refs = stations.map { |feature| feature.dig("properties", "ref") }

    assert_includes names, "中山"
    assert_includes names, "松江南京"
    assert_includes names, "南京復興"
    assert_includes refs, "R11;G14"
    assert_not_includes names, "忠孝復興"
    assert_not_includes names, "景安"
  end

  test "injects 大安 transfer on wenhu and tamsui xinyi lines" do
    %w[wenhu_line tamsui_xinyi].each do |slug|
      line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == slug }
      builder = Geojson::MetroLineBuilder.new(line)
      stations = []

      builder.send(:apply_taipei_in_station_transfers!, stations)

      station = stations.find { |entry| entry[:name] == "大安" }
      assert station, "expected 大安 on #{slug}"
      assert_equal "BR09;R05", station[:ref]
    end
  end

  test "injects 台北車站 transfer on tamsui xinyi and bannan lines" do
    %w[tamsui_xinyi bannan].each do |slug|
      line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == slug }
      builder = Geojson::MetroLineBuilder.new(line)
      stations = []

      builder.send(:apply_taipei_in_station_transfers!, stations)

      station = stations.find { |entry| entry[:name] == "台北車站" }
      assert station, "expected 台北車站 on #{slug}"
      assert_equal "R10;BL12", station[:ref]
    end
  end

  test "injects 南港展覽館 transfer on wenhu and bannan lines" do
    %w[wenhu_line bannan].each do |slug|
      line = Geojson::TaipeiMetroCatalog::LINES.find { |entry| entry.slug == slug }
      builder = Geojson::MetroLineBuilder.new(line)
      stations = []

      builder.send(:apply_taipei_in_station_transfers!, stations)

      station = stations.find { |entry| entry[:name] == "南港展覽館" }
      assert station, "expected 南港展覽館 on #{slug}"
      assert_equal "BR24;BL23", station[:ref]
    end
  end

  test "wenhu line geojson includes 忠孝復興 between BR09 and BR11" do
    data = JSON.parse(Rails.root.join("public/geojson/taipei_metro/wenhu_line.geojson").read)
    stations = data.fetch("features").select do |feature|
      feature.dig("properties", "feature_type") == "station"
    end

    refs = stations.map { |feature| feature.dig("properties", "ref") }
    assert_includes refs, "BR10;BL15"
    assert_includes stations.map { |feature| feature.dig("properties", "name") }, "忠孝復興"

    daan = stations.find { |feature| feature.dig("properties", "name") == "大安" }
    expected = Geojson::TaipeiMetroCatalog::IN_STATION_TRANSFERS_BY_NAME.fetch("大安")
    lon, lat = daan.dig("geometry", "coordinates")

    assert_in_delta expected[:lon], lon, 0.002, "大安 longitude"
    assert_in_delta expected[:lat], lat, 0.002, "大安 latitude"
  end
end
