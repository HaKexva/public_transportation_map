# frozen_string_literal: true

require "test_helper"

class GeojsonBusLayoutTest < ActiveSupport::TestCase
  test "maps city ids to sidebar folders" do
    assert_equal "kaohsiung_bus", Geojson::BusLayout.subdir_for("Kaohsiung")
    assert_equal "taipei_new_taipei_bus", Geojson::BusLayout.subdir_for("Taipei")
    assert_equal "taoyuan_bus", Geojson::BusLayout.subdir_for("Taoyuan")
    assert_equal "intercity_bus", Geojson::BusLayout.subdir_for("InterCity")
  end

  test "builds keelung band subfolders from route ref" do
    path = Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_301", ref: "301")
    assert_equal "public/geojson/bus/keelung_bus/300-399/keelung_301.geojson", path.relative_path_from(Rails.root).to_s

    four_digit = Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_1717", ref: "1717")
    assert_equal "public/geojson/bus/keelung_bus/1000+/keelung_1717.geojson", four_digit.relative_path_from(Rails.root).to_s

    tourist = Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_r66", ref: "R66")
    assert_includes tourist.to_s, "/keelung_bus/r-t/"
  end

  test "skips band subfolders for counties with fewer than ten routes" do
    skip "needs sparse county data" unless Geojson::BusLayout.route_counts["MiaoliCounty"].to_i < Geojson::BusLayout::MIN_ROUTES_FOR_BANDS

    path = Geojson::BusLayout.geojson_path(city_id: "MiaoliCounty", slug: "miaoli_county_101", ref: "101")
    assert_equal "public/geojson/bus/miaoli_bus/miaoli_county_101.geojson", path.relative_path_from(Rails.root).to_s
  end

  test "uses color band folders for larger cities" do
    skip "needs taichung data" unless Geojson::BusLayout.route_counts["Taichung"].to_i >= Geojson::BusLayout::MIN_ROUTES_FOR_BANDS

    path = Geojson::BusLayout.geojson_path(city_id: "Taichung", slug: "taichung_huang1", ref: "黃1")
    assert_includes path.to_s, "/taichung_bus/huang/"
  end

  test "infers city id from slug prefix" do
    assert_equal "Kaohsiung", Geojson::BusLayout.city_id_for_slug("kaohsiung_huang1")
    assert_equal "NewTaipei", Geojson::BusLayout.city_id_for_slug("new_taipei_920")
    assert_equal "InterCity", Geojson::BusLayout.city_id_for_slug("inter_city_1820")
  end

  test "with_bus_root isolates path resolution and restores afterward" do
    root = Rails.root.join("tmp/bus_layout_root_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root)
    default_root = Geojson::BusLayout.bus_root

    Geojson::BusLayout.with_bus_root(root, route_counts: Hash.new(0).merge("Keelung" => 50)) do
      path = Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901")
      assert_equal root.join("keelung_bus/900-999/keelung_901.geojson"), path
      assert Geojson::BusLayout.uses_bands?("Keelung")
    end

    assert_equal default_root, Geojson::BusLayout.bus_root
  ensure
    FileUtils.rm_rf(root) if root
  end

  test "compute_route_counts skips files deleted mid-scan" do
    root = Rails.root.join("tmp/bus_layout_counts_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(root)
    ghost = root.join("miaoli_bus/miaoli_county_ghost.geojson")
    FileUtils.mkdir_p(ghost.dirname)
    File.symlink("/nonexistent/bus-ghost-#{SecureRandom.hex(4)}", ghost)

    Geojson::BusLayout.with_bus_root(root) do
      assert_equal 0, Geojson::BusLayout.compute_route_counts["MiaoliCounty"]
    end
  ensure
    FileUtils.rm_rf(root) if root
  end
end
