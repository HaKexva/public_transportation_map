# frozen_string_literal: true

require "test_helper"

class MetroLineBuilderTraTest < ActiveSupport::TestCase
  WESTERN_MAIN_SLUGS = %w[western_trunk_north mountain_line sea_line western_trunk_south].freeze
  EASTERN_MAIN_SLUGS = %w[south_link taidong_line beihui_line yilan_line].freeze
  BRANCH_SLUGS = Geojson::TraCatalog::BRANCH_SLUGS

  test "tra catalog lists western eastern main lines and branches separately" do
    slugs = Geojson::TraCatalog::LINES.map(&:slug)

    WESTERN_MAIN_SLUGS.each { |slug| assert_includes slugs, slug }
    EASTERN_MAIN_SLUGS.each { |slug| assert_includes slugs, slug }
    BRANCH_SLUGS.each { |slug| assert_includes slugs, slug }

    refute_includes slugs, "western_trunk"
    refute_includes slugs, "mountain_sea_line"
  end

  test "tra station features use transfer refs at interchange stations" do
    line = Geojson::TraCatalog::LINES.find { |entry| entry.slug == "western_trunk_north" }
    builder = Geojson::MetroLineBuilder.new(line)
    stations = [
      { name: "板橋", ref: "1020", lon: 121.46, lat: 25.01, line: line.name },
      { name: "竹南", ref: "1250", lon: 120.87, lat: 24.69, line: line.name },
      { name: "三坑", ref: "910", lon: 121.74, lat: 25.12, line: line.name }
    ]

    features = builder.send(:station_features, stations)
    refs = features.map { |feature| feature.dig(:properties, :ref) }

    assert_includes refs, "1020;BL07;03"
    assert_includes refs, "1250"
    refute_includes refs, "1250-WN;1250-M;1250-S"
    assert_includes refs, "910"
  end

  test "western trunk north and south meet at changhua junction" do
    junction_lat = Geojson::TraCatalog::WESTERN_TRUNK_JUNCTION_LAT

    %w[western_trunk_north western_trunk_south].each do |slug|
      path = Rails.root.join("public/geojson/tra/#{slug}.geojson")
      skip "run bin/rails geojson:tra first" unless path.exist?

      route = JSON.parse(path.read)["features"].find { |f| f.dig("properties", "feature_type") == "route" }
      coords = route.dig("geometry", "coordinates")

      near_changhua = coords.any? do |lon, lat|
        Geojson::TrackGeometry.planar_distance_meters(
          lon, lat,
          Geojson::TraCatalog::WESTERN_TRUNK_JUNCTION_LON,
          junction_lat
        ) < 500
      end

      lats = coords.map { |coord| coord[1] }
      if slug == "western_trunk_north"
        refute near_changhua, "north section should end at 竹南, not 彰化"
        assert lats.max > 24.5, "north section should reach north of 竹南"
        assert lats.min <= 24.71, "north section should reach 竹南 area"
      else
        assert near_changhua, "#{slug} should pass through 彰化 junction"
        assert lats.min < 23.0, "south section should reach south of 彰化"
        assert lats.max >= junction_lat - 0.02
      end
    end
  end

  test "sea and neiwan lines follow station order along route geometry" do
    {
      "sea_line" => 18,
      "neiwan_line" => 13
    }.each do |slug, station_count|
      path = Rails.root.join("public/geojson/tra/#{slug}.geojson")
      skip "run bin/rails geojson:tra first" unless path.exist?

      data = JSON.parse(path.read)
      coords = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
        .dig("geometry", "coordinates")
      stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }

      assert_equal station_count, stations.length

      previous_index = -1
      stations.each do |station|
        lon, lat = station.dig("geometry", "coordinates")
        index = coords.each_with_index.min_by do |point, _idx|
          Geojson::TrackGeometry.planar_distance_meters(lon, lat, point[0], point[1])
        end[1]

        assert index >= previous_index,
               "#{station.dig("properties", "name")} on #{slug} should follow route direction"
        previous_index = index
      end
    end
  end

  test "western trunk north geojson is continuous from keelung to zhunan" do
    path = Rails.root.join("public/geojson/tra/western_trunk_north.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 36, names.length
    assert_equal "基隆", names.first
    assert_equal "竹南", names.last
    refute_includes names, "彰化"
    refute_includes names, "談文"

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    finish_station = stations.last
    start_coords = start_station.dig("geometry", "coordinates")
    finish_coords = finish_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1], finish_coords[0], finish_coords[1]
    ) < 500
  end

  test "western trunk south geojson is continuous from changhua to sankuai" do
    path = Rails.root.join("public/geojson/tra/western_trunk_south.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 46, names.length
    assert_equal "彰化", names.first
    assert_equal "三塊厝", names[-2]
    assert_equal "高雄", names.last
    refute_includes names, "竹南"

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    start_coords = start_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
  end

  test "mountain line geojson is continuous from zhunan to changhua" do
    path = Rails.root.join("public/geojson/tra/mountain_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 23, names.length
    assert_equal "竹南", names.first
    assert_equal "彰化", names.last
    refute_includes names, "談文"

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    finish_station = stations.last
    start_coords = start_station.dig("geometry", "coordinates")
    finish_coords = finish_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1], finish_coords[0], finish_coords[1]
    ) < 500
  end

  test "sea line geojson is one continuous corridor from zhunan to changhua" do
    path = Rails.root.join("public/geojson/tra/sea_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal "竹南", names.first
    assert_equal "彰化", names.last
    assert_equal 18, names.length

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    finish_station = stations.last
    start_coords = start_station.dig("geometry", "coordinates")
    finish_coords = finish_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1], finish_coords[0], finish_coords[1]
    ) < 500

    assert coords.first[1] > coords.last[1], "sea line should run north to south"

    near_changhua = Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1],
      Geojson::TraCatalog::WESTERN_TRUNK_JUNCTION_LON,
      Geojson::TraCatalog::WESTERN_TRUNK_JUNCTION_LAT
    ) < 500
    assert near_changhua
  end

  test "neiwan line geojson is continuous from hsinchu to neiwan" do
    path = Rails.root.join("public/geojson/tra/neiwan_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal "新竹", names.first
    assert_equal "內灣", names.last

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    finish_station = stations.last
    start_coords = start_station.dig("geometry", "coordinates")
    finish_coords = finish_station.dig("geometry", "coordinates")

    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1], finish_coords[0], finish_coords[1]
    ) < 500
  end

  test "jiji line geojson is continuous from ershui to checheng" do
    path = Rails.root.join("public/geojson/tra/jiji_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 6, names.length
    assert_equal "二水", names.first
    assert_equal "車埕", names.last
    assert_equal %w[二水 源泉 濁水 龍泉 集集 車埕], names

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    previous_index = -1
    stations.each do |station|
      lon, lat = station.dig("geometry", "coordinates")
      index = coords.each_with_index.min_by do |point, _idx|
        Geojson::TrackGeometry.planar_distance_meters(lon, lat, point[0], point[1])
      end[1]

      assert index >= previous_index,
             "#{station.dig("properties", "name")} on jiji line should follow route direction"
      previous_index = index
    end
  end

  test "tra branch junction stations are marked shared in geojson" do
    {
      "liujia_line" => [ "1193", "竹中" ],
      "neiwan_line" => [ "1210", "新竹" ],
      "chengzhui_line" => [ "3350", "成功" ],
      "chengzhui_line:2260" => [ "2260", "追分" ]
    }.each do |slug, (ref, name)|
      slug = slug.split(":").first
      path = Rails.root.join("public/geojson/tra/#{slug}.geojson")
      skip "run bin/rails geojson:refresh_tra_stations first" unless path.exist?

      station = JSON.parse(path.read)["features"].find do |feature|
        next unless feature.dig("properties", "feature_type") == "station"

        station_ref = feature.dig("properties", "ref").to_s.split(";").first[/\A(\d+)/, 1]
        station_ref == ref
      end

      assert station, "expected #{name} on #{slug}"
      assert station.dig("properties", "shared_junction"), "#{name} should be a shared junction on #{slug}"
    end
  end

  test "tra main line junction stations are marked shared in geojson" do
    {
      "mountain_line" => [ "3350", "成功" ],
      "sea_line" => [ "2260", "追分" ]
    }.each do |slug, (ref, name)|
      path = Rails.root.join("public/geojson/tra/#{slug}.geojson")
      skip "run bin/rails geojson:tra_offline first" unless path.exist?

      station = JSON.parse(path.read)["features"].find do |feature|
        next unless feature.dig("properties", "feature_type") == "station"

        station_ref = feature.dig("properties", "ref").to_s.split(";").first[/\A(\d+)/, 1]
        station_ref == ref
      end

      assert station, "expected #{name} on #{slug}"
      assert station.dig("properties", "shared_junction"), "#{name} should be a shared junction on #{slug}"
    end
  end

  test "taichung port line geojson is continuous from taichung port to pier one" do
    path = Rails.root.join("public/geojson/tra/taichung_port_line.geojson")
    skip "run bin/rails geojson:tra_offline first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 2, names.length
    assert_equal %w[台中港 一號碼頭], names

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    stations.each do |station|
      lon, lat = station.dig("geometry", "coordinates")
      distance = Geojson::TrackGeometry.nearest_on_line_strings(
        lon,
        lat,
        [ coords ]
      ).last

      assert_operator distance, :<=, 100, "#{station.dig('properties', 'name')} should sit on the route"
    end
  end

  test "hualien port line geojson is continuous from beipu to hualien port" do
    path = Rails.root.join("public/geojson/tra/hualien_port_line.geojson")
    skip "run bin/rails geojson:tra_offline first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 2, names.length
    assert_equal %w[北埔 花蓮港], names

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    stations.each do |station|
      lon, lat = station.dig("geometry", "coordinates")
      distance = Geojson::TrackGeometry.nearest_on_line_strings(
        lon,
        lat,
        [ coords ]
      ).last

      assert_operator distance, :<=, 25, "#{station.dig('properties', 'name')} should sit on the route"
    end
  end

  test "shenao line geojson is continuous from ruifang to badouzi" do
    path = Rails.root.join("public/geojson/tra/shenao_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 3, names.length
    assert_equal "瑞芳", names.first
    assert_equal "八斗子", names.last
    assert_equal %w[瑞芳 海科館 八斗子], names

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    start_coords = start_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
  end

  test "shenao line geojson aligns stations on track from ruifang to badouzi" do
    path = Rails.root.join("public/geojson/tra/shenao_line.geojson")
    skip "run bin/rails geojson:tra_offline first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }

    assert coords.length > 100, "expected OSM corridor track, got #{coords.length} points"

    stations.each do |station|
      station_coords = station.dig("geometry", "coordinates")
      snap = coords.map do |point|
        Geojson::TrackGeometry.planar_distance_meters(
          station_coords[0], station_coords[1], point[0], point[1]
        )
      end.min
      assert snap < 100, "expected #{station.dig("properties", "name")} on track, snap=#{snap.round}m"
    end
  end

  test "chengzhui line geojson is continuous from chenggong to zhuifen" do
    path = Rails.root.join("public/geojson/tra/chengzhui_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 2, names.length
    assert_equal "成功", names.first
    assert_equal "追分", names.last

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    finish_station = stations.last
    start_coords = start_station.dig("geometry", "coordinates")
    finish_coords = finish_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1], finish_coords[0], finish_coords[1]
    ) < 500
  end

  test "shalun line geojson is continuous from zhongzhou to shalun" do
    path = Rails.root.join("public/geojson/tra/shalun_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 3, names.length
    assert_equal "中洲", names.first
    assert_equal "沙崙", names.last
    assert_equal %w[中洲 長榮大學 沙崙], names

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    start_coords = start_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
  end

  test "pingxi line geojson aligns stations on track from sandiaoling to jingtong" do
    path = Rails.root.join("public/geojson/tra/pingxi_line.geojson")
    skip "run bin/rails geojson:tra_offline first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 7, names.length
    assert_equal %w[三貂嶺 大華 十分 望古 嶺腳 平溪 菁桐], names

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    stations.each do |station|
      station_coords = station.dig("geometry", "coordinates")
      snap = coords.map do |point|
        Geojson::TrackGeometry.planar_distance_meters(
          station_coords[0], station_coords[1], point[0], point[1]
        )
      end.min
      assert snap < 100, "expected #{station.dig("properties", "name")} on track, snap=#{snap.round}m"
    end
  end

  test "liujia line geojson is continuous from liujia to zhuzhong" do
    path = Rails.root.join("public/geojson/tra/liujia_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal "六家", names.first
    assert_equal "竹中", names.last

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_coords = stations.first.dig("geometry", "coordinates")
    finish_coords = stations.last.dig("geometry", "coordinates")

    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1], finish_coords[0], finish_coords[1]
    ) < 500
  end

  test "south link geojson is continuous from jialu to taitung" do
    path = Rails.root.join("public/geojson/tra/south_link.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 10, names.length
    assert_equal "加祿", names.first
    assert_equal "臺東", names.last
    assert_equal "內獅", names[1]
    assert_equal "康樂", names[8]
    refute_includes names, "枋寮"

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    start_coords = start_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
  end

  test "pingtung line geojson is continuous from kaohsiung to fangliao" do
    path = Rails.root.join("public/geojson/tra/pingtung_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 21, names.length
    assert_equal "高雄", names.first
    assert_equal "枋寮", names.last
    assert_equal "民族", names[1]
    assert_equal "屏東", names[8]
    assert_equal "林邊", names[17]

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    start_coords = start_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
  end

  test "taidong line geojson is continuous from taitung to hualien" do
    path = Rails.root.join("public/geojson/tra/taidong_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 23, names.length
    assert_equal "臺東", names.first
    assert_equal "花蓮", names.last
    assert_equal "山里", names[1]
    assert_equal "海端", names[6]

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    start_coords = start_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
  end

  test "yilan line geojson is continuous from badu to suao" do
    path = Rails.root.join("public/geojson/tra/yilan_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 24, names.length
    assert_equal "八堵", names.first
    assert_equal "蘇澳", names.last
    assert_equal "暖暖", names[1]
    assert_equal "冬山", names[22]
    refute_includes names, "新馬"
    refute_includes names, "蘇澳新"

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    finish_station = stations.last
    start_coords = start_station.dig("geometry", "coordinates")
    finish_coords = finish_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1], finish_coords[0], finish_coords[1]
    ) < 500
  end

  test "beihui line geojson is continuous from hualien to suaoxin" do
    path = Rails.root.join("public/geojson/tra/beihui_line.geojson")
    skip "run bin/rails geojson:tra first" unless path.exist?

    data = JSON.parse(path.read)
    route = data["features"].find { |f| f.dig("properties", "feature_type") == "route" }
    coords = route.dig("geometry", "coordinates")
    stations = data["features"].select { |f| f.dig("properties", "feature_type") == "station" }
    names = stations.map { |feature| feature.dig("properties", "name") }

    assert_equal 13, names.length
    assert_equal "花蓮", names.first
    assert_equal "蘇澳新", names.last
    assert_equal "北埔", names[1]
    assert_equal "永樂", names[11]
    refute_includes names, "新馬"

    gaps = coords.each_cons(2).count do |(start, finish)|
      Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
    end
    assert_equal 0, gaps

    start_station = stations.first
    finish_station = stations.last
    start_coords = start_station.dig("geometry", "coordinates")
    finish_coords = finish_station.dig("geometry", "coordinates")
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.first[0], coords.first[1], start_coords[0], start_coords[1]
    ) < 500
    assert Geojson::TrackGeometry.planar_distance_meters(
      coords.last[0], coords.last[1], finish_coords[0], finish_coords[1]
    ) < 500
  end

  test "each tra line geojson has no gaps larger than 2km" do
    slugs = Geojson::TraCatalog::LINES.map(&:slug)

    slugs.each do |slug|
      path = Rails.root.join("public/geojson/tra/#{slug}.geojson")
      skip "run bin/rails geojson:tra first" unless path.exist?

      route = JSON.parse(path.read)["features"].find { |f| f.dig("properties", "feature_type") == "route" }
      coords = route.dig("geometry", "coordinates")
      gaps = coords.each_cons(2).count do |(start, finish)|
        Geojson::TrackGeometry.planar_distance_meters(start[0], start[1], finish[0], finish[1]) > 2_000
      end

      assert_equal 0, gaps, "expected no large gaps on #{slug}"
    end
  end

  test "marks keelung origin and branch line terminals in geojson" do
    {
      "western_trunk_north" => [ [ "基隆", "origin" ] ],
      "yilan_line" => [ [ "八堵", "origin" ], [ "蘇澳", "destination" ] ],
      "jiji_line" => [ [ "車埕", "destination" ] ],
      "neiwan_line" => [ [ "內灣", "destination" ] ],
      "shenao_line" => [ [ "八斗子", "destination" ] ]
    }.each do |slug, expectations|
      path = Rails.root.join("public/geojson/tra/#{slug}.geojson")
      skip "run bin/rails geojson:tra_offline first" unless path.exist?

      stations = JSON.parse(path.read)["features"].select { |f| f.dig("properties", "feature_type") == "station" }

      expectations.each do |name, role|
        station = stations.find { |feature| feature.dig("properties", "name") == name }
        assert station, "expected #{name} on #{slug}"
        assert_equal role, station.dig("properties", "station_role"), "#{name} on #{slug}"
      end
    end
  end

  test "each tra main line geojson has one continuous route when built" do
    (WESTERN_MAIN_SLUGS + EASTERN_MAIN_SLUGS).each do |slug|
      path = Rails.root.join("public/geojson/tra/#{slug}.geojson")
      skip "run bin/rails geojson:tra first" unless path.exist?

      routes = JSON.parse(path.read)["features"].select { |f| f.dig("properties", "feature_type") == "route" }
      assert_equal 1, routes.length, "expected one route for #{slug}"
      assert routes.first.dig("geometry", "coordinates").length >= 2
    end
  end
end
