# frozen_string_literal: true

require "test_helper"

class GeojsonBusImporterTest < ActiveSupport::TestCase
  class FakeTdxClient
    def initialize(payloads)
      @payloads = payloads
    end

    def configured?
      true
    end

    def fetch_all(path)
      @payloads.fetch(path)
    end
  end

  setup do
    @isolated_bus_root = Rails.root.join("tmp/bus_importer_test_#{Process.pid}_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@isolated_bus_root)
    @previous_bus_root = Geojson::BusLayout.instance_variable_get(:@bus_root_override)
    @previous_route_counts = Geojson::BusLayout.instance_variable_get(:@route_counts)
    # Isolate writes so parallel CI workers do not clobber keelung_901 / shared bus files.
    Geojson::BusLayout.bus_root = @isolated_bus_root
    seeded = Hash.new(0)
    seeded["Keelung"] = Geojson::BusLayout::MIN_ROUTES_FOR_BANDS
    Geojson::BusLayout.instance_variable_set(:@route_counts, seeded)
  end

  teardown do
    Geojson::BusLayout.instance_variable_set(:@bus_root_override, @previous_bus_root)
    Geojson::BusLayout.instance_variable_set(:@route_counts, @previous_route_counts)
    FileUtils.rm_rf(@isolated_bus_root) if @isolated_bus_root
  end

  test "matches 1xx and 2xx names including letter suffixes" do
    keelung = Geojson::BusCatalog.find("Keelung")
    assert Geojson::BusImporter.series_match?("101", series: "1", city: keelung)
    assert Geojson::BusImporter.series_match?("103區", series: "1", city: keelung)
    refute Geojson::BusImporter.series_match?("11", series: "1", city: keelung)
    refute Geojson::BusImporter.series_match?("201", series: "1", city: keelung)
    assert Geojson::BusImporter.series_match?("201", series: "2", city: keelung)
    assert Geojson::BusImporter.series_match?("205區", series: "2", city: keelung)
    refute Geojson::BusImporter.series_match?("21", series: "2", city: keelung)
    refute Geojson::BusImporter.series_match?("101", series: "2", city: keelung)
    assert Geojson::BusImporter.series_match?("301", series: "3", city: keelung)
    assert Geojson::BusImporter.series_match?("3014", series: "3", city: keelung)
    refute Geojson::BusImporter.series_match?("201", series: "3", city: keelung)
    assert_equal "301", Geojson::BusImporter.public_ref("3014", city: keelung)
    assert_equal "1717", Geojson::BusImporter.public_ref("1717", city: keelung)
    assert_equal "5014", Geojson::BusImporter.public_ref("5014", city: Geojson::BusCatalog.find("Taoyuan"))
    assert_equal "101", Geojson::BusImporter.public_ref("101", city: keelung)
    assert Geojson::BusImporter.extra_digit_name?("3014")
    refute Geojson::BusImporter.extra_digit_name?("301")
    assert_equal "中山一路", Geojson::BusImporter.unlabeled_trunk_via(%w[中山一路 成功市場 高遠新村])
    assert_nil Geojson::BusImporter.unlabeled_trunk_via(%w[祥豐街 中正路])
    assert_equal "祥豐街", Geojson::BusImporter.variant_label("SubRoutes" => [ { "Headsign" => "和平島—經祥豐街" } ])
    assert_equal "中正路", Geojson::BusImporter.variant_label("SubRoutes" => [ { "Headsign" => "和平島—經中正路" } ])
    assert_equal "美的世界、八斗山莊", Geojson::BusImporter.variant_label(
      "SubRoutes" => [ { "Headsign" => "八斗子—經美的世界(經八斗山莊)" } ]
    )
    assert Geojson::BusImporter.series_match?("4081", series: "4", city: keelung)
    assert Geojson::BusImporter.series_match?("4101", series: "4", city: keelung)
    refute Geojson::BusImporter.series_match?("4081", series: "1", city: keelung)
  end

  test "splits 繞駛 SubRoutes into their own route variant" do
    route = {
      "RouteUID" => "TPE11821",
      "RouteName" => { "Zh_tw" => "33" },
      "SubRoutes" => [
        { "SubRouteUID" => "TPE118210", "SubRouteName" => { "Zh_tw" => "33" }, "Direction" => 0 },
        { "SubRouteUID" => "TPE162167", "SubRouteName" => { "Zh_tw" => "33繞駛大道路" }, "Direction" => 0 }
      ]
    }

    main, detour = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("Taipei")

    assert_equal [ "TPE118210" ], main["_import_sub_uids"]
    assert main["_import_blank_sub"]
    assert_equal [ "TPE162167" ], detour["_import_sub_uids"]
    assert_equal "繞駛大道路", detour["_import_detour"]
    assert_equal "taipei_33", Geojson::BusImporter.slug_for(main, city:)
    assert_not_equal "taipei_33", Geojson::BusImporter.slug_for(detour, city:)
  end

  test "normalizes detour labels across directions and ignores timetable notes" do
    sub = ->(name) { { "SubRouteUID" => name, "SubRouteName" => { "Zh_tw" => name } } }
    route = ->(parent, *names) { { "RouteName" => { "Zh_tw" => parent }, "SubRoutes" => names.map(&sub) } }

    yellow = route.("黃2", "黃2", "黃2新營→王爺宮(繞駛工研院南分院)", "黃2王爺宮→新營(繞駛工研院南分院)")
    assert_equal [ nil, "繞駛工研院南分院" ], Geojson::BusImporter.detour_variants(yellow).map { |v| v["_import_detour"] }

    north = route.("北環幹線", "北環幹線繞駛士科路去程半", "北環幹線不繞駛士科路去程半", "北環幹線繞駛士科路返程半")
    main, detour = Geojson::BusImporter.detour_variants(north)
    assert_equal [ "北環幹線不繞駛士科路去程半" ], main["_import_sub_uids"]
    assert_equal "繞駛士科路", detour["_import_detour"]

    directed = ->(parent, pairs) {
      { "RouteName" => { "Zh_tw" => parent },
        "SubRoutes" => pairs.map { |name, direction| sub.(name).merge("Direction" => direction) } }
    }
    dog = directed.("北環幹線", [ [ "北環幹線狗狗公車去程半", 0 ], [ "北環幹線繞駛士科路去程半", 0 ],
      [ "北環幹線不繞駛士科路去程半", 0 ], [ "北環幹線不繞駛士科路返程半", 1 ] ])
    main, detour = Geojson::BusImporter.detour_variants(dog)
    assert_equal [ "北環幹線狗狗公車去程半", "北環幹線不繞駛士科路去程半", "北環幹線不繞駛士科路返程半" ], main["_import_sub_uids"]
    assert_equal "繞駛士科路", detour["_import_detour"]

    labelled = directed.("551", [ [ "551不繞駛行善路經金龍寺", 0 ], [ "551不繞駛行善路經金龍寺", 1 ],
      [ "551不繞駛行善路不經金龍寺", 0 ], [ "551不繞駛行善路不經金龍寺", 1 ] ])
    assert_equal [ "不繞駛行善路經金龍寺", "不繞駛行善路不經金龍寺" ], Geojson::BusImporter.detour_variants(labelled).map { |v| v["_import_detour"] }

    minibus = route.("小16", "小16", "小16平0550 假0600無繞駛")
    assert_equal 1, Geojson::BusImporter.detour_variants(minibus).size
  end

  test "splits a campus extension into 本線 and 延駛 variants" do
    sub = ->(name, direction) { { "SubRouteUID" => "#{name}#{direction}", "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "237" },
              "SubRoutes" => [ sub.("237不經政大校區", 0), sub.("237不經政大校區", 1), sub.("237經政大校區", 0), sub.("237經政大校區", 1) ] }
    main, extension = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("Taipei")

    assert_equal [ "237不經政大校區0", "237不經政大校區1" ], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal "延駛政大校區", extension["_import_detour"]
    assert_equal "taipei_237", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Ataipei_237_\h{10}\z/, Geojson::BusImporter.slug_for(extension, city:))
  end

  test "splits 559 繞駛陽明交大五舍 from the main line" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "559" },
              "SubRoutes" => [
                sub.("559路", 0, "TPE159150"), sub.("559路", 1, "TPE159150"),
                sub.("559繞駛男女五舍", 0, "TPE159435"), sub.("559繞駛男女五舍", 1, "TPE159435")
              ] }
    main, detour = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("Taipei")

    assert_equal %w[TPE159150], main["_import_sub_uids"]
    assert_equal "繞駛陽明交大五舍", detour["_import_detour"]
    assert_equal %w[TPE159435], detour["_import_sub_uids"]
    assert_equal "taipei_559", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Ataipei_559_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
  end

  test "splits 542 延駛民族西路 from the main line" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "542" },
              "SubRoutes" => [
                sub.("542路", 0, "TPE102770"), sub.("542路", 1, "TPE102770"),
                sub.("542預約公車", 0, "TPE159918"), sub.("542預約公車", 1, "TPE159918"),
                sub.("542路去程半", 0, "TPE160608"),
                sub.("542路延駛民族西路", 0, "TPE161077"), sub.("542路延駛民族西路", 1, "TPE161077")
              ] }
    main, extension = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("Taipei")

    assert_equal %w[TPE102770], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal "延駛民族西路", extension["_import_detour"]
    assert_equal %w[TPE161077], extension["_import_sub_uids"]
    assert_equal "taipei_542", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Ataipei_542_\h{10}\z/, Geojson::BusImporter.slug_for(extension, city:))
  end

  test "splits 576繞 into 繞駛 / 不繞駛民權路" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "576" },
              "SubRoutes" => [
                sub.("576", 0, "NWT159674"),
                sub.("576繞", 0, "NWT159675")
              ] }
    main, detour = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")

    assert_equal %w[NWT159674], main["_import_sub_uids"]
    assert_equal "不繞駛民權路", main["_import_main_label"]
    assert_equal "繞駛民權路", detour["_import_detour"]
    assert_equal %w[NWT159675], detour["_import_sub_uids"]
    assert_equal "new_taipei_576", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_576_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
  end

  test "splits 616經黎明 into 繞駛 / 不繞駛黎明技術學院" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "616" },
              "SubRoutes" => [
                sub.("616經黎明", 0, "TPE15581"), sub.("616經黎明", 1, "TPE15581"),
                sub.("616路", 0, "TPE159390"), sub.("616路", 1, "TPE159390")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("Taipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛黎明技術學院" }
    importer = Geojson::BusImporter.new(city_id: "Taipei")

    assert_equal 2, variants.size
    assert_equal %w[TPE159390], main["_import_sub_uids"]
    assert_equal "不繞駛黎明技術學院", main["_import_main_label"]
    assert_equal %w[TPE15581], detour["_import_sub_uids"]
    assert_equal "taipei_616", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Ataipei_616_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "616（不繞駛黎明技術學院）", importer.send(:display_name, "616", "不繞駛黎明技術學院")
    assert_equal "616（繞駛黎明技術學院）", importer.send(:display_name, "616", "繞駛黎明技術學院")
    assert_equal "616 (skips Lee-Ming Institute of Technology)", importer.send(:display_name_en, "616", "不繞駛黎明技術學院")
    assert_equal "616 (detour via Lee-Ming Institute of Technology)", importer.send(:display_name_en, "616", "繞駛黎明技術學院")
  end

  test "splits 紅19經天母國中 into 本線 / 繞駛天母國中" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "TPE15341",
      "RouteName" => { "Zh_tw" => "紅19" },
      "SubRoutes" => [
        sub.("紅19", 0, "TPE15341"), sub.("紅19", 1, "TPE15341"),
        sub.("紅19經天母國中", 0, "TPE161958"), sub.("紅19經天母國中", 1, "TPE161958")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("Taipei")
    importer = Geojson::BusImporter.new(city_id: "Taipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛天母國中" }

    assert_equal 2, variants.size
    assert_equal %w[TPE15341], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[TPE161958], detour["_import_sub_uids"]
    assert_equal "taipei_hong19", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Ataipei_hong19_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "紅19（本線）", importer.send(:display_name, "紅19", "本線")
    assert_equal "紅19（繞駛天母國中）", importer.send(:display_name, "紅19", "繞駛天母國中")
    assert_equal "紅19 (Main Line)", importer.send(:display_name_en, "紅19", "本線")
    assert_equal "紅19 (detour via Tianmu Junior High School)", importer.send(:display_name_en, "紅19", "繞駛天母國中")
  end

  test "splits 紅22台北港去／返 into 本線 / 繞駛台北港" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "NWT16674",
      "RouteName" => { "Zh_tw" => "紅22" },
      "SubRoutes" => [
        sub.("紅22", 0, "NWT157738"), sub.("紅22", 1, "NWT157738"),
        sub.("紅22去(車機)", 0, "NWT159331"), sub.("紅22返(車機)", 1, "NWT159332"),
        sub.("紅22台北港去", 0, "NWT161277"), sub.("紅22台北港去", 1, "NWT161277"),
        sub.("紅22台北港返", 0, "NWT161278"), sub.("紅22台北港返", 1, "NWT161278")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    port = variants.find { |row| row["_import_detour"] == "繞駛台北港" }

    assert_equal 2, variants.size
    assert_equal %w[NWT157738], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[NWT161277 NWT161278].sort, port["_import_sub_uids"].sort
    assert_equal "new_taipei_hong22", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_hong22_\h{10}\z/, Geojson::BusImporter.slug_for(port, city:))
    assert_equal "紅22（本線）", importer.send(:display_name, "紅22", "本線")
    assert_equal "紅22（繞駛台北港）", importer.send(:display_name, "紅22", "繞駛台北港")
    assert_equal "紅22 (Main Line)", importer.send(:display_name_en, "紅22", "本線")
    assert_equal "紅22 (detour via Taipei Port)", importer.send(:display_name_en, "紅22", "繞駛台北港")
  end

  test "splits 紅26未進漁人碼頭 into 本線 / 不經漁人碼頭" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "NWT16619",
      "RouteName" => { "Zh_tw" => "紅26" },
      "SubRoutes" => [
        sub.("紅26", 0, "NWT157667"), sub.("紅26", 1, "NWT157667"),
        sub.("紅26去(車機)", 0, "NWT159324"), sub.("紅26返(車機)", 1, "NWT159325"),
        sub.("紅26未進漁人碼頭去", 0, "NWT159327"), sub.("紅26未進漁人碼頭返", 1, "NWT159328"),
        sub.("紅26未進漁人碼頭", 0, "NWT159777"), sub.("紅26未進漁人碼頭", 1, "NWT159777")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    skip = variants.find { |row| row["_import_detour"] == "不經漁人碼頭" }

    assert_equal 2, variants.size
    assert_equal %w[NWT157667], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[NWT159327 NWT159328 NWT159777].sort, skip["_import_sub_uids"].sort
    assert_equal "new_taipei_hong26", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_hong26_\h{10}\z/, Geojson::BusImporter.slug_for(skip, city:))
    assert_equal "紅26（本線）", importer.send(:display_name, "紅26", "本線")
    assert_equal "紅26（不經漁人碼頭）", importer.send(:display_name, "紅26", "不經漁人碼頭")
    assert_equal "紅26 (Main Line)", importer.send(:display_name_en, "紅26", "本線")
    assert_equal "紅26 (skips Fisherman's Wharf)", importer.send(:display_name_en, "紅26", "不經漁人碼頭")
  end

  test "splits 紅50經復興北路 into 本線 / 繞駛復興北路" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "TPE16166",
      "RouteName" => { "Zh_tw" => "紅50" },
      "SubRoutes" => [
        sub.("紅50", 0, "TPE155935"), sub.("紅50", 1, "TPE155935"),
        sub.("紅50經復興北路", 0, "TPE159663"), sub.("紅50經復興北路", 1, "TPE159663")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("Taipei")
    importer = Geojson::BusImporter.new(city_id: "Taipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛復興北路" }

    assert_equal 2, variants.size
    assert_equal %w[TPE155935], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[TPE159663], detour["_import_sub_uids"]
    assert_equal "taipei_hong50", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Ataipei_hong50_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "紅50（本線）", importer.send(:display_name, "紅50", "本線")
    assert_equal "紅50（繞駛復興北路）", importer.send(:display_name, "紅50", "繞駛復興北路")
    assert_equal "紅50 (Main Line)", importer.send(:display_name_en, "紅50", "本線")
    assert_equal "紅50 (detour via Fuxing North Rd.)", importer.send(:display_name_en, "紅50", "繞駛復興北路")
  end

  test "splits 紅37 into 國家新都 / 繞駛淡水商工 / 繞駛海洋都心" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    main_route = {
      "RouteUID" => "NWT16431",
      "RouteName" => { "Zh_tw" => "紅37" },
      "SubRoutes" => [
        sub.("紅37", 0, "NWT157427"), sub.("紅37", 1, "NWT157427"),
        sub.("紅37新市站(車機)", 0, "NWT159380"), sub.("紅37捷運淡水站(車機)", 1, "NWT159381"),
        sub.("紅37繞淡水商工新市站", 0, "NWT160947"), sub.("紅37繞淡水商工捷運淡水站", 1, "NWT160948")
      ]
    }
    ocean = {
      "RouteUID" => "NWT19088",
      "RouteName" => { "Zh_tw" => "紅37行經海洋都心社區" },
      "SubRoutes" => [
        sub.("紅37行經海洋都心社區", 0, "NWT161387"), sub.("紅37行經海洋都心社區", 1, "NWT161387")
      ]
    }
    city = Geojson::BusCatalog.find("NewTaipei")
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    variants = Geojson::BusImporter.detour_variants(main_route)
    main = variants.find { |row| row["_import_blank_sub"] }
    school = variants.find { |row| row["_import_detour"] == "繞駛淡水商工" }
    aliased = Geojson::BusImporter.with_route_alias(ocean)
    plain = Geojson::BusImporter.with_alias_main_label(main_route)

    assert_equal 2, variants.size
    assert_equal %w[NWT157427], main["_import_sub_uids"]
    assert_equal "國家新都", main["_import_main_label"]
    assert_equal %w[NWT160947 NWT160948].sort, school["_import_sub_uids"].sort
    assert_equal "紅37", aliased["_import_ref"]
    assert_equal "繞駛海洋都心", aliased["_import_detour"]
    assert_equal "國家新都", plain["_import_main_label"]
    assert_equal "new_taipei_hong37", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_hong37_\h{10}\z/, Geojson::BusImporter.slug_for(school, city:))
    assert_match(/\Anew_taipei_hong37_\h{10}\z/, Geojson::BusImporter.slug_for(aliased, city:))
    assert_equal "紅37（國家新都）", importer.send(:display_name, "紅37", "國家新都")
    assert_equal "紅37（繞駛淡水商工）", importer.send(:display_name, "紅37", "繞駛淡水商工")
    assert_equal "紅37（繞駛海洋都心）", importer.send(:display_name, "紅37", "繞駛海洋都心")
    assert_equal "紅37 (Guojia Xindu)", importer.send(:display_name_en, "紅37", "國家新都")
    assert_equal "紅37 (detour via Tamsui Vocational High School)", importer.send(:display_name_en, "紅37", "繞駛淡水商工")
    assert_equal "紅37 (detour via Ocean Community)", importer.send(:display_name_en, "紅37", "繞駛海洋都心")
  end

  test "splits 631繞 into 繞駛 / 不繞駛興福寮66巷" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "631" },
              "SubRoutes" => [
                sub.("631", 0, "NWT158440"), sub.("631", 1, "NWT158440"),
                sub.("631繞", 0, "NWT159211"), sub.("631繞", 1, "NWT159211")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛興福寮66巷" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT158440], main["_import_sub_uids"]
    assert_equal "不繞駛興福寮66巷", main["_import_main_label"]
    assert_equal %w[NWT159211], detour["_import_sub_uids"]
    assert_equal "new_taipei_631", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_631_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "631（不繞駛興福寮66巷）", importer.send(:display_name, "631", "不繞駛興福寮66巷")
    assert_equal "631（繞駛興福寮66巷）", importer.send(:display_name, "631", "繞駛興福寮66巷")
    assert_equal "631 (skips Xingfuliao Ln. 66)", importer.send(:display_name_en, "631", "不繞駛興福寮66巷")
    assert_equal "631 (detour via Xingfuliao Ln. 66)", importer.send(:display_name_en, "631", "繞駛興福寮66巷")
  end

  test "splits 837副繞 into 繞駛 / 不繞駛竹林慈玄宮" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "837副" },
              "SubRoutes" => [
                sub.("837副", 0, "NWT159548"),
                sub.("837副繞", 0, "NWT159550")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛竹林慈玄宮" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT159548], main["_import_sub_uids"]
    assert_equal "不繞駛竹林慈玄宮", main["_import_main_label"]
    assert_equal %w[NWT159550], detour["_import_sub_uids"]
    assert_equal "new_taipei_837sub", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_837sub_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "837副（不繞駛竹林慈玄宮）", importer.send(:display_name, "837副", "不繞駛竹林慈玄宮")
    assert_equal "837副（繞駛竹林慈玄宮）", importer.send(:display_name, "837副", "繞駛竹林慈玄宮")
    assert_equal "837副 (skips Zhulin Cixuan Temple)", importer.send(:display_name_en, "837副", "不繞駛竹林慈玄宮")
    assert_equal "837副 (detour via Zhulin Cixuan Temple)", importer.send(:display_name_en, "837副", "繞駛竹林慈玄宮")
  end

  test "splits 837區 into 本線 / 竿蓁二街福德宮 / 紅樹林路" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "837區" },
              "SubRoutes" => [
                sub.("837區", 0, "NWT159549"),
                sub.("837區經竿蓁二街福德宮", 0, "NWT159551"),
                sub.("837區經紅樹林路", 0, "NWT159552")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    fude = variants.find { |row| row["_import_detour"] == "繞駛竿蓁二街福德宮" }
    hong = variants.find { |row| row["_import_detour"] == "繞駛紅樹林路" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 3, variants.size
    assert_equal %w[NWT159549], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[NWT159551], fude["_import_sub_uids"]
    assert_equal %w[NWT159552], hong["_import_sub_uids"]
    assert_equal "new_taipei_837sh", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_837sh_\h{10}\z/, Geojson::BusImporter.slug_for(fude, city:))
    assert_match(/\Anew_taipei_837sh_\h{10}\z/, Geojson::BusImporter.slug_for(hong, city:))
    assert_not_equal Geojson::BusImporter.slug_for(fude, city:), Geojson::BusImporter.slug_for(hong, city:)
    assert_equal "837區（本線）", importer.send(:display_name, "837區", "本線")
    assert_equal "837區（繞駛竿蓁二街福德宮）", importer.send(:display_name, "837區", "繞駛竿蓁二街福德宮")
    assert_equal "837區（繞駛紅樹林路）", importer.send(:display_name, "837區", "繞駛紅樹林路")
    assert_equal "837區 (Main Line)", importer.send(:display_name_en, "837區", "本線")
    assert_equal "837區 (detour via Qianzhen 2nd St. Fude Temple)", importer.send(:display_name_en, "837區", "繞駛竿蓁二街福德宮")
    assert_equal "837區 (detour via Hongshulin Rd.)", importer.send(:display_name_en, "837區", "繞駛紅樹林路")
  end

  test "splits 819副延 into 本線 / 延駛石碇" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "819副" },
              "SubRoutes" => [
                sub.("819副", 0, "NWT159400"), sub.("819副", 1, "NWT159400"),
                sub.("819副延", 0, "NWT158016"), sub.("819副延", 1, "NWT158016")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    extension = variants.find { |row| row["_import_detour"] == "延駛石碇" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT159400], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[NWT158016], extension["_import_sub_uids"]
    assert_equal "new_taipei_819sub", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_819sub_\h{10}\z/, Geojson::BusImporter.slug_for(extension, city:))
    assert_equal "819副（本線）", importer.send(:display_name, "819副", "本線")
    assert_equal "819副（延駛石碇）", importer.send(:display_name, "819副", "延駛石碇")
    assert_equal "819副 (Main Line)", importer.send(:display_name_en, "819副", "本線")
    assert_equal "819副 (extended to Shiding)", importer.send(:display_name_en, "819副", "延駛石碇")
  end

  test "splits 847繞 into 繞駛 / 不繞駛阿南坑、貴興路" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "847" },
              "SubRoutes" => [
                sub.("847", 0, "NWT157425"), sub.("847", 1, "NWT157425"),
                sub.("847繞", 0, "NWT159168"), sub.("847繞", 1, "NWT159168")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛阿南坑、貴興路" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157425], main["_import_sub_uids"]
    assert_equal "不繞駛阿南坑、貴興路", main["_import_main_label"]
    assert_equal %w[NWT159168], detour["_import_sub_uids"]
    assert_equal "new_taipei_847", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_847_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "847（不繞駛阿南坑、貴興路）", importer.send(:display_name, "847", "不繞駛阿南坑、貴興路")
    assert_equal "847（繞駛阿南坑、貴興路）", importer.send(:display_name, "847", "繞駛阿南坑、貴興路")
    assert_equal "847 (skips Anankeng & Guixing Rd.)", importer.send(:display_name_en, "847", "不繞駛阿南坑、貴興路")
    assert_equal "847 (detour via Anankeng & Guixing Rd.)", importer.send(:display_name_en, "847", "繞駛阿南坑、貴興路")
  end

  test "splits 847區繞 into 繞駛 / 不繞駛土城醫院" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "847區" },
              "SubRoutes" => [
                sub.("847區", 0, "NWT157783"), sub.("847區", 1, "NWT157783"),
                sub.("847區繞", 0, "NWT160487"), sub.("847區繞", 1, "NWT160487")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛土城醫院" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157783], main["_import_sub_uids"]
    assert_equal "不繞駛土城醫院", main["_import_main_label"]
    assert_equal %w[NWT160487], detour["_import_sub_uids"]
    assert_equal "new_taipei_847sh", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_847sh_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "847區（不繞駛土城醫院）", importer.send(:display_name, "847區", "不繞駛土城醫院")
    assert_equal "847區（繞駛土城醫院）", importer.send(:display_name, "847區", "繞駛土城醫院")
    assert_equal "847區 (skips Tucheng Hospital)", importer.send(:display_name_en, "847區", "不繞駛土城醫院")
    assert_equal "847區 (detour via Tucheng Hospital)", importer.send(:display_name_en, "847區", "繞駛土城醫院")
  end

  test "splits 851 into 本線 / 不經二甲 / 延駛邱厝巷" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "851" },
              "SubRoutes" => [
                sub.("851", 0, "NWT157729"), sub.("851", 1, "NWT157729"),
                sub.("851延駛邱厝巷", 0, "NWT159303"), sub.("851延駛邱厝巷", 1, "NWT159303"),
                sub.("851不經二甲", 0, "NWT159314"), sub.("851不經二甲", 1, "NWT159314")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    skip = variants.find { |row| row["_import_detour"] == "不經二甲" }
    ext = variants.find { |row| row["_import_detour"] == "延駛邱厝巷" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 3, variants.size
    assert_equal %w[NWT157729], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[NWT159314], skip["_import_sub_uids"]
    assert_equal %w[NWT159303], ext["_import_sub_uids"]
    assert_equal "new_taipei_851", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_851_\h{10}\z/, Geojson::BusImporter.slug_for(skip, city:))
    assert_match(/\Anew_taipei_851_\h{10}\z/, Geojson::BusImporter.slug_for(ext, city:))
    assert_equal "851（本線）", importer.send(:display_name, "851", "本線")
    assert_equal "851（不經二甲）", importer.send(:display_name, "851", "不經二甲")
    assert_equal "851（延駛邱厝巷）", importer.send(:display_name, "851", "延駛邱厝巷")
    assert_equal "851 (Main Line)", importer.send(:display_name_en, "851", "本線")
    assert_equal "851 (skips Erjia)", importer.send(:display_name_en, "851", "不經二甲")
    assert_equal "851 (extended to Qiucuo Lane)", importer.send(:display_name_en, "851", "延駛邱厝巷")
  end

  test "splits 918 三民路 and 黎明 variants from 本線" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "918" },
              "SubRoutes" => [
                sub.("918", 0, "NWT158700"), sub.("918", 1, "NWT158700"),
                sub.("918三民路", 0, "NWT158701"), sub.("918三民路", 1, "NWT158701"),
                sub.("918三民路不繞黎明", 0, "NWT159686"), sub.("918三民路不繞黎明", 1, "NWT159686"),
                sub.("918不繞黎明和三民路", 0, "NWT159687"), sub.("918不繞黎明和三民路", 1, "NWT159687"),
                sub.("918返程不繞黎明與三民路", 0, "NWT159492"), sub.("918返程不繞黎明與三民路", 1, "NWT159492"),
                sub.("918去(車機)", 0, "NWT160227"), sub.("918返(車機)", 1, "NWT162530")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    by_label = variants.select { |row| row["_import_detour"] }.to_h { |row| [ row["_import_detour"], row ] }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 5, variants.size
    assert_equal %w[NWT158700], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[NWT158701], by_label["繞駛三民路"]["_import_sub_uids"]
    assert_equal %w[NWT159686], by_label["繞駛三民路、不經黎明"]["_import_sub_uids"]
    assert_equal %w[NWT159687], by_label["不經黎明、不繞三民路"]["_import_sub_uids"]
    assert_equal %w[NWT159492], by_label["返程不經黎明、不繞三民路"]["_import_sub_uids"]
    assert_equal "new_taipei_918", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_918_\h{10}\z/, Geojson::BusImporter.slug_for(by_label["繞駛三民路"], city:))
    assert_equal "918（本線）", importer.send(:display_name, "918", "本線")
    assert_equal "918（繞駛三民路）", importer.send(:display_name, "918", "繞駛三民路")
    assert_equal "918（繞駛三民路、不經黎明）", importer.send(:display_name, "918", "繞駛三民路、不經黎明")
    assert_equal "918 (Main Line)", importer.send(:display_name_en, "918", "本線")
    assert_equal "918 (detour via Sanmin Rd.)", importer.send(:display_name_en, "918", "繞駛三民路")
  end

  test "splits 917 美術館發車 from 鶯歌車站發車" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "917" },
              "SubRoutes" => [
                sub.("917", 0, "NWT157205"), sub.("917", 1, "NWT157205"),
                sub.("917延", 0, "NWT159937"), sub.("917延", 1, "NWT159937"),
                sub.("917延活動專車(返程不停靠)", 0, "NWT162027")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    museum = variants.find { |row| row["_import_detour"] == "美術館發車" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157205], main["_import_sub_uids"]
    assert_equal "鶯歌車站發車", main["_import_main_label"]
    assert_equal %w[NWT159937 NWT162027].sort, museum["_import_sub_uids"].sort
    assert_equal "new_taipei_917", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_917_\h{10}\z/, Geojson::BusImporter.slug_for(museum, city:))
    assert_equal "917（鶯歌車站發車）", importer.send(:display_name, "917", "鶯歌車站發車")
    assert_equal "917（美術館發車）", importer.send(:display_name, "917", "美術館發車")
    assert_equal "917 (from Yingge Station)", importer.send(:display_name_en, "917", "鶯歌車站發車")
    assert_equal "917 (from Art Museum)", importer.send(:display_name_en, "917", "美術館發車")
  end

  test "splits 859寵物公車 from unlabeled main" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "859" },
              "SubRoutes" => [
                sub.("859", 0, "NWT157553"), sub.("859", 1, "NWT157553"),
                sub.("859寵物公車", 0, "NWT159611"), sub.("859寵物公車", 1, "NWT159611")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    pet = variants.find { |row| row["_import_detour"] == "寵物公車" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157553], main["_import_sub_uids"]
    assert_nil main["_import_main_label"]
    assert_equal %w[NWT159611], pet["_import_sub_uids"]
    assert_equal "new_taipei_859", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_859_\h{10}\z/, Geojson::BusImporter.slug_for(pet, city:))
    assert_equal "859", importer.send(:display_name, "859", nil)
    assert_equal "859（寵物公車）", importer.send(:display_name, "859", "寵物公車")
    assert_equal "859 (Pet Bus)", importer.send(:display_name_en, "859", "寵物公車")
  end

  test "872 path pairs split 經正德國中 / 直行中山北路" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "NWT16578",
      "RouteName" => { "Zh_tw" => "872經正德國中、直行中山北路" },
      "SubRoutes" => [
        sub.("872經正德國中", 0, "NWT157620"), sub.("872經正德國中", 1, "NWT157620"),
        sub.("872直行中山北路", 0, "NWT159595"), sub.("872直行中山北路", 1, "NWT159595")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    zhengde = variants.find { |row| row["_import_detour"] == "經正德國中" }
    zhongshan = variants.find { |row| row["_import_detour"] == "直行中山北路" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157620], zhengde["_import_sub_uids"]
    assert_equal %w[NWT159595], zhongshan["_import_sub_uids"]
    assert_equal "872", zhengde["_import_ref"]
    assert_equal "872經正德國中、直行中山北路", zhengde["_import_tdx_ref"]
    assert_equal "new_taipei_872", Geojson::BusImporter.slug_for(
      { "RouteName" => { "Zh_tw" => "872" } }, city:
    )
    assert_match(/\Anew_taipei_872_\h{10}\z/, Geojson::BusImporter.slug_for(zhengde, city:))
    assert_match(/\Anew_taipei_872_\h{10}\z/, Geojson::BusImporter.slug_for(zhongshan, city:))
    refute_equal Geojson::BusImporter.slug_for(zhengde, city:), Geojson::BusImporter.slug_for(zhongshan, city:)
    assert_equal "872（正德國中）", importer.send(:display_name, "872", "經正德國中")
    assert_equal "872（直行中山北路）", importer.send(:display_name, "872", "直行中山北路")
    assert_equal "872 (via Zhengde Junior High)", importer.send(:display_name_en, "872", "經正德國中")
    assert_equal "872 (Zhongshan N. Rd. (straight))", importer.send(:display_name_en, "872", "直行中山北路")
    assert_equal %w[872經正德國中 872經正德國中], Geojson::BusImporter.path_pair_subroute_names("經正德國中")
    assert_equal %w[872直行中山北路 872直行中山北路], Geojson::BusImporter.path_pair_subroute_names("直行中山北路")
  end

  test "splits 895寵物公車 from unlabeled main" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "895" },
              "SubRoutes" => [
                sub.("895", 0, "NWT157814"), sub.("895", 1, "NWT157814"),
                sub.("895寵物公車", 0, "NWT159608"), sub.("895寵物公車", 1, "NWT159608")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    pet = variants.find { |row| row["_import_detour"] == "寵物公車" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157814], main["_import_sub_uids"]
    assert_nil main["_import_main_label"]
    assert_equal %w[NWT159608], pet["_import_sub_uids"]
    assert_equal "new_taipei_895", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_895_\h{10}\z/, Geojson::BusImporter.slug_for(pet, city:))
    assert_equal "895（寵物公車）", importer.send(:display_name, "895", "寵物公車")
    assert_equal "895 (Pet Bus)", importer.send(:display_name_en, "895", "寵物公車")
  end

  test "splits 881行經台北灣 from unlabeled main" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "881" },
              "SubRoutes" => [
                sub.("881", 0, "NWT157557"), sub.("881", 1, "NWT157557"),
                sub.("881行經台北灣", 0, "NWT159493"), sub.("881行經台北灣", 1, "NWT159493")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛台北灣社區" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157557], main["_import_sub_uids"]
    assert_nil main["_import_main_label"]
    assert_equal %w[NWT159493], detour["_import_sub_uids"]
    assert_equal "new_taipei_881", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_881_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "881（繞駛台北灣社區）", importer.send(:display_name, "881", "繞駛台北灣社區")
    assert_equal "881 (detour via Taipei Bay Community)", importer.send(:display_name_en, "881", "繞駛台北灣社區")
  end

  test "splits 878延淡水商工 into 本線 / 延駛淡水商工" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "878" },
              "SubRoutes" => [
                sub.("878", 0, "NWT157562"), sub.("878", 1, "NWT157562"),
                sub.("878延淡水商工", 0, "NWT161057"), sub.("878延淡水商工", 1, "NWT161057")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    ext = variants.find { |row| row["_import_detour"] == "延駛淡水商工" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157562], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[NWT161057], ext["_import_sub_uids"]
    assert_equal "new_taipei_878", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_878_\h{10}\z/, Geojson::BusImporter.slug_for(ext, city:))
    assert_equal "878（本線）", importer.send(:display_name, "878", "本線")
    assert_equal "878（延駛淡水商工）", importer.send(:display_name, "878", "延駛淡水商工")
    assert_equal "878 (Main Line)", importer.send(:display_name_en, "878", "本線")
    assert_equal "878 (extended to Tamsui Vocational High School)", importer.send(:display_name_en, "878", "延駛淡水商工")
  end

  test "splits 868行經八勢路一段 from unlabeled main" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "868" },
              "SubRoutes" => [
                sub.("868", 0, "NWT157678"), sub.("868", 1, "NWT157678"),
                sub.("868行經八勢路一段", 0, "NWT160937"), sub.("868行經八勢路一段", 1, "NWT160937")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "繞駛八勢路" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT157678], main["_import_sub_uids"]
    assert_nil main["_import_main_label"]
    assert_equal %w[NWT160937], detour["_import_sub_uids"]
    assert_equal "new_taipei_868", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_868_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "868（繞駛八勢路）", importer.send(:display_name, "868", "繞駛八勢路")
    assert_equal "868 (detour via Bashi Rd.)", importer.send(:display_name_en, "868", "繞駛八勢路")
  end

  test "splits 705繞 into unlabeled main and 單向繞駛" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "705" },
              "SubRoutes" => [
                sub.("705", 0, "NWT101950"), sub.("705", 1, "NWT101950"),
                sub.("705繞", 0, "NWT162479"), sub.("705繞", 1, "NWT162479")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    detour = variants.find { |row| row["_import_detour"] == "單向繞駛" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT101950], main["_import_sub_uids"]
    assert_nil main["_import_main_label"]
    assert_equal %w[NWT162479], detour["_import_sub_uids"]
    assert_equal "new_taipei_705", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_705_\h{10}\z/, Geojson::BusImporter.slug_for(detour, city:))
    assert_equal "705（單向繞駛）", importer.send(:display_name, "705", "單向繞駛")
    assert_equal "705 (outbound detour via Dacheng Rd.)", importer.send(:display_name_en, "705", "單向繞駛")
  end

  test "aliases 790漁港 as 790 繞駛龜吼漁港" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    routes = [
      { "RouteUID" => "NWT16740", "RouteName" => { "Zh_tw" => "790" },
        "SubRoutes" => [ sub.("790", 0, "NWT157845"), sub.("790", 1, "NWT157845") ] },
      { "RouteUID" => "NWT17500", "RouteName" => { "Zh_tw" => "790漁港" },
        "SubRoutes" => [ sub.("790漁港", 0, "NWT158663"), sub.("790漁港", 1, "NWT158663") ] }
    ]
    city = Geojson::BusCatalog.find("NewTaipei")
    groups = Geojson::BusImporter.grouped_routes(routes, city:)
    by_slug = groups.to_h { |slug, group, _via, _unlabeled| [ slug, group.first ] }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    plain = by_slug["new_taipei_790"]
    harbor = by_slug.values.find { |row| row["_import_detour"] == "繞駛龜吼漁港" }

    assert_equal 2, groups.size
    assert_nil plain["_import_detour"]
    assert_equal "790", harbor["_import_ref"]
    assert_equal "790漁港", harbor["_import_tdx_ref"]
    assert_match(/\Anew_taipei_790_\h{10}\z/, Geojson::BusImporter.slug_for(harbor, city:))
    assert_equal "790（繞駛龜吼漁港）", importer.send(:display_name, "790", "繞駛龜吼漁港")
    assert_equal "790 (detour via Guihou Fishing Harbor)", importer.send(:display_name_en, "790", "繞駛龜吼漁港")
  end

  test "791 path pairs and Gongliao aliases stay off the shuttle slug" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    routes = [
      { "RouteUID" => "NWT16682", "RouteName" => { "Zh_tw" => "791" },
        "SubRoutes" => [
          sub.("791國家新城", 0, "NWT157746"), sub.("791福隆", 1, "NWT158906"),
          sub.("791延國家新城", 0, "NWT162614"), sub.("791延福隆", 1, "NWT162615")
        ] },
      { "RouteUID" => "NWT17692", "RouteName" => { "Zh_tw" => "791繞貢寮" },
        "SubRoutes" => [ sub.("791繞貢寮國家新城", 0, "NWT158874"), sub.("791繞貢寮福隆", 1, "NWT159191") ] },
      { "RouteUID" => "NWT17718", "RouteName" => { "Zh_tw" => "791經貢寮區衛生" },
        "SubRoutes" => [ sub.("791經貢寮區衛生國家新城", 0, "NWT158901"), sub.("791經貢寮區衛生福隆", 1, "NWT159190") ] },
      { "RouteUID" => "NWT19208", "RouteName" => { "Zh_tw" => "791區" },
        "SubRoutes" => [ sub.("791區國家新城", 0, "NWT161547"), sub.("791區區民廣場", 1, "NWT161548") ] }
    ]
    city = Geojson::BusCatalog.find("NewTaipei")
    groups = Geojson::BusImporter.grouped_routes(routes, city:)
    by_detour = groups.to_h { |slug, group, _via, _unlabeled| [ group.first["_import_detour"].to_s, [ slug, group.first ] ] }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    main_slug, main = by_detour["正線"]
    magang_slug, magang = by_detour["延駛馬崗"]
    gongliao_slug, gongliao = by_detour["繞駛貢寮"]
    health_slug, health = by_detour["貢寮衛生所"]
    shuttle_slug, = groups.find { |_slug, group, _via, _unlabeled|
      Geojson::BusImporter.route_name_zh(group.first) == "791區"
    }

    assert_equal 5, groups.size
    assert_equal %w[NWT157746 NWT158906], main["_import_sub_uids"]
    assert_equal %w[NWT162614 NWT162615], magang["_import_sub_uids"]
    assert_equal "791", gongliao["_import_ref"]
    assert_equal "791繞貢寮", gongliao["_import_tdx_ref"]
    assert_equal "791經貢寮區衛生", health["_import_tdx_ref"]
    assert_match(/\Anew_taipei_791_\h{10}\z/, main_slug)
    assert_match(/\Anew_taipei_791_\h{10}\z/, magang_slug)
    assert_match(/\Anew_taipei_791_\h{10}\z/, gongliao_slug)
    assert_match(/\Anew_taipei_791_\h{10}\z/, health_slug)
    refute_match(/_sh_/, health_slug)
    assert_equal "new_taipei_791sh", shuttle_slug
    assert_equal "791（正線）", importer.send(:display_name, "791", "正線")
    assert_equal "791（延駛馬崗）", importer.send(:display_name, "791", "延駛馬崗")
    assert_equal "791（繞駛貢寮）", importer.send(:display_name, "791", "繞駛貢寮")
    assert_equal "791（貢寮衛生所）", importer.send(:display_name, "791", "貢寮衛生所")
    assert_equal "791 (Main Line)", importer.send(:display_name_en, "791", "正線")
    assert_equal "791 (extended to Magang)", importer.send(:display_name_en, "791", "延駛馬崗")
    assert_equal "791 (detour via Gongliao)", importer.send(:display_name_en, "791", "繞駛貢寮")
    assert_equal "791 (Gongliao Health Center)", importer.send(:display_name_en, "791", "貢寮衛生所")
  end

  test "splits 657 into 本線、延和路 and 海山拖吊場" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    routes = [
      { "RouteUID" => "NWT10164", "RouteName" => { "Zh_tw" => "657" },
        "SubRoutes" => [
          sub.("657", 0, "NWT10164"), sub.("657", 1, "NWT10164"),
          sub.("657經海山拖吊場", 0, "NWT162088"), sub.("657經海山拖吊場", 1, "NWT162088")
        ] },
      { "RouteUID" => "NWT16685", "RouteName" => { "Zh_tw" => "657延" },
        "SubRoutes" => [
          sub.("657延", 0, "NWT157770"), sub.("657延", 1, "NWT157770")
        ] }
    ]
    city = Geojson::BusCatalog.find("NewTaipei")
    groups = Geojson::BusImporter.grouped_routes(routes, city:)
    by_slug = groups.to_h { |slug, group, _via, _unlabeled| [ slug, group.first ] }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    main = by_slug["new_taipei_657"]
    yard = by_slug.values.find { |row| row["_import_detour"] == "海山拖吊場" }
    yanhe = by_slug.values.find { |row| row["_import_detour"] == "延和路" }

    assert_equal 3, groups.size
    assert_equal %w[NWT10164], main["_import_sub_uids"]
    assert_equal "本線", main["_import_main_label"]
    assert_equal %w[NWT162088], yard["_import_sub_uids"]
    assert_equal "657", yanhe["_import_ref"]
    assert_equal "657延", yanhe["_import_tdx_ref"]
    assert_equal "new_taipei_657", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_657_\h{10}\z/, Geojson::BusImporter.slug_for(yard, city:))
    assert_match(/\Anew_taipei_657_\h{10}\z/, Geojson::BusImporter.slug_for(yanhe, city:))
    assert_not_equal Geojson::BusImporter.slug_for(yard, city:), Geojson::BusImporter.slug_for(yanhe, city:)
    assert_equal "657（本線）", importer.send(:display_name, "657", "本線")
    assert_equal "657（延和路）", importer.send(:display_name, "657", "延和路")
    assert_equal "657（海山拖吊場）", importer.send(:display_name, "657", "海山拖吊場")
    assert_equal "657 (Main Line)", importer.send(:display_name_en, "657", "本線")
    assert_equal "657 (Yanhe Rd.)", importer.send(:display_name_en, "657", "延和路")
    assert_equal "657 (Haishan Tow Yard)", importer.send(:display_name_en, "657", "海山拖吊場")
  end

  test "aliases 930延 as 大崎腳 and labels plain 930 as 青潭" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    routes = [
      { "RouteUID" => "NWT10105", "RouteName" => { "Zh_tw" => "930" },
        "SubRoutes" => [
          sub.("930", 0, "NWT10105"), sub.("930", 1, "NWT10105")
        ] },
      { "RouteUID" => "NWT10106", "RouteName" => { "Zh_tw" => "930延" },
        "SubRoutes" => [
          sub.("930延", 0, "NWT157771"), sub.("930延", 1, "NWT157771")
        ] }
    ]
    city = Geojson::BusCatalog.find("NewTaipei")
    groups = Geojson::BusImporter.grouped_routes(routes, city:)
    by_label = groups.to_h { |_slug, group, _via, _unlabeled|
      row = group.first
      [ row["_import_detour"] || row["_import_main_label"], row ]
    }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    qingtan = by_label["青潭"]
    daqijiao = by_label["大崎腳"]

    assert_equal 2, groups.size
    assert_equal "青潭", qingtan["_import_main_label"]
    assert_equal "930", daqijiao["_import_ref"]
    assert_equal "930延", daqijiao["_import_tdx_ref"]
    assert_equal "new_taipei_930", Geojson::BusImporter.slug_for(qingtan, city:)
    assert_match(/\Anew_taipei_930_\h{10}\z/, Geojson::BusImporter.slug_for(daqijiao, city:))
    assert_equal "930（青潭）", importer.send(:display_name, "930", "青潭")
    assert_equal "930（大崎腳）", importer.send(:display_name, "930", "大崎腳")
    assert_equal "930 (Qingtan)", importer.send(:display_name_en, "930", "青潭")
    assert_equal "930 (Daqijiao)", importer.send(:display_name_en, "930", "大崎腳")
  end

  test "loop routes use ref-destination board headsign like 593-沙崙" do
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    route = {
      "RouteName" => { "Zh_tw" => "593" },
      "DepartureStopNameZh" => "捷運淡水站",
      "DestinationStopNameZh" => "沙崙",
      "DestinationStopNameEn" => "Shalun"
    }
    # Real TDX poles at 捷運淡水站 use different StopUIDs for the two ends.
    stops = [ {
      "Direction" => 0,
      "Stops" => [
        { "StopUID" => "NWT157099", "StopName" => { "Zh_tw" => "捷運淡水站" } },
        { "StopUID" => "NWT1", "StopName" => { "Zh_tw" => "沙崙里" } },
        { "StopUID" => "NWT157133", "StopName" => { "Zh_tw" => "捷運淡水站" } }
      ]
    } ]

    assert_equal "593-沙崙", importer.send(:circular_board_name, "593", route, stops)
    assert_equal "593-Shalun", importer.send(:circular_board_name_en, "593", route, stops)
    assert_equal "593-沙崙（繞駛測試）", importer.send(:named_with_via, "593-沙崙", "593", "繞駛測試")
  end

  test "789 path pairs label 崁腳 and split 789區 北基新城 / 圳頭" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    main_route = {
      "RouteUID" => "NWT16739",
      "RouteName" => { "Zh_tw" => "789" },
      "SubRoutes" => [
        sub.("789國家新城", 0, "NWT157844"), sub.("789崁腳", 1, "NWT158920")
      ]
    }
    district = {
      "RouteUID" => "NWT17865",
      "RouteName" => { "Zh_tw" => "789區" },
      "SubRoutes" => [
        sub.("789區基隆轉運站", 0, "NWT159262"), sub.("789區北基新城", 1, "NWT159263"),
        sub.("789區延圳頭去", 0, "NWT161927"), sub.("789區延圳頭返", 1, "NWT161928")
      ]
    }
    city = Geojson::BusCatalog.find("NewTaipei")
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    main = Geojson::BusImporter.detour_variants(main_route).sole
    assert_equal "崁腳", main["_import_detour"]
    assert_equal %w[NWT157844 NWT158920], main["_import_sub_uids"]
    assert_equal "789（崁腳）", importer.send(:display_name, "789", "崁腳")
    assert_match(/\Anew_taipei_789_\h{10}\z/, Geojson::BusImporter.slug_for(main, city:))

    variants = Geojson::BusImporter.detour_variants(district)
    beiji = variants.find { |row| row["_import_detour"] == "北基新城" }
    zuntou = variants.find { |row| row["_import_detour"] == "圳頭" }
    assert_equal 2, variants.size
    assert_equal %w[NWT159262 NWT159263], beiji["_import_sub_uids"]
    assert_equal %w[NWT161927 NWT161928], zuntou["_import_sub_uids"]
    assert_equal "789區（北基新城）", importer.send(:display_name, "789區", "北基新城")
    assert_equal "789區（圳頭）", importer.send(:display_name, "789區", "圳頭")
    assert_equal "789區 (Beiji New Town)", importer.send(:display_name_en, "789區", "北基新城")
    assert_equal "789區 (Zuntou)", importer.send(:display_name_en, "789區", "圳頭")
  end

  test "886 path pairs split 本線 / 繞駛水湳洞 / 繞駛威遠廟" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "NWT16565",
      "RouteName" => { "Zh_tw" => "886" },
      "SubRoutes" => [
        sub.("886瑞芳", 0, "NWT157601"), sub.("886和美國小", 1, "NWT159117"),
        sub.("886繞水湳洞遊客中心瑞芳", 0, "NWT159187"), sub.("886繞水湳洞遊客中心和美國小", 1, "NWT159188"),
        sub.("886繞威遠廟瑞芳", 0, "NWT161217")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    main = variants.find { |row| row["_import_detour"] == "本線" }
    shuinandong = variants.find { |row| row["_import_detour"] == "繞駛水湳洞" }
    weiyuan = variants.find { |row| row["_import_detour"] == "繞駛威遠廟" }

    assert_equal 3, variants.size
    assert_equal %w[NWT157601 NWT159117], main["_import_sub_uids"]
    assert_equal %w[NWT159187 NWT159188], shuinandong["_import_sub_uids"]
    assert_equal %w[NWT161217 NWT159117], weiyuan["_import_sub_uids"]
    assert_match(/\Anew_taipei_886_\h{10}\z/, Geojson::BusImporter.slug_for(main, city:))
    assert_match(/\Anew_taipei_886_\h{10}\z/, Geojson::BusImporter.slug_for(shuinandong, city:))
    assert_match(/\Anew_taipei_886_\h{10}\z/, Geojson::BusImporter.slug_for(weiyuan, city:))
    refute_equal Geojson::BusImporter.slug_for(main, city:), Geojson::BusImporter.slug_for(shuinandong, city:)
    assert_equal "886（本線）", importer.send(:display_name, "886", "本線")
    assert_equal "886（繞駛水湳洞）", importer.send(:display_name, "886", "繞駛水湳洞")
    assert_equal "886（繞駛威遠廟）", importer.send(:display_name, "886", "繞駛威遠廟")
    assert_equal "886 (Main Line)", importer.send(:display_name_en, "886", "本線")
    assert_equal "886 (detour via Shuinandong)", importer.send(:display_name_en, "886", "繞駛水湳洞")
    assert_equal "886 (detour via Weiyuan Temple)", importer.send(:display_name_en, "886", "繞駛威遠廟")
  end

  test "紅5 path pairs split 本線 / 繞駛文化大學" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "TPE10821",
      "RouteName" => { "Zh_tw" => "紅5" },
      "SubRoutes" => [
        sub.("紅5", 0, "TPE10821"), sub.("紅5", 1, "TPE10821"),
        sub.("紅5往劍潭經文大", 0, "TPE157609"), sub.("紅5往陽明山經文大", 1, "TPE157610"),
        sub.("紅5往陽明山", 1, "TPE158419"), sub.("紅5往劍潭", 0, "TPE158420")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("Taipei")
    importer = Geojson::BusImporter.new(city_id: "Taipei")
    main = variants.find { |row| row["_import_detour"] == "本線" }
    campus = variants.find { |row| row["_import_detour"] == "繞駛文化大學" }

    assert_equal 2, variants.size
    assert_equal %w[TPE158420 TPE158419], main["_import_sub_uids"]
    assert_equal %w[TPE157609 TPE157610], campus["_import_sub_uids"]
    assert_equal "taipei_hong5_2441bedf1c", Geojson::BusImporter.slug_for(main, city:)
    assert_equal "taipei_hong5_312257b87e", Geojson::BusImporter.slug_for(campus, city:)
    assert_equal "紅5（本線）", importer.send(:display_name, "紅5", "本線")
    assert_equal "紅5（繞駛文化大學）", importer.send(:display_name, "紅5", "繞駛文化大學")
    assert_equal "紅5 (Main Line)", importer.send(:display_name_en, "紅5", "本線")
    assert_equal "紅5 (detour via Chinese Culture University)", importer.send(:display_name_en, "紅5", "繞駛文化大學")
    assert_equal %w[紅5往劍潭經文大 紅5往陽明山經文大], Geojson::BusImporter.path_pair_subroute_names("繞駛文化大學")
  end

  test "788 path pairs split 金瓜石 / 延駛水湳洞" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "NWT16641",
      "RouteName" => { "Zh_tw" => "788" },
      "SubRoutes" => [
        sub.("788去水湳洞", 0, "NWT157701"), sub.("788返水湳洞", 1, "NWT160828"),
        sub.("788基隆轉運站", 0, "NWT160829"), sub.("788金瓜石(黃金博物館)", 1, "NWT160830")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    main = variants.find { |row| row["_import_detour"] == "金瓜石" }
    extension = variants.find { |row| row["_import_detour"] == "延駛水湳洞" }

    assert_equal 2, variants.size
    assert_equal %w[NWT160829 NWT160830], main["_import_sub_uids"]
    assert_equal %w[NWT157701 NWT160828], extension["_import_sub_uids"]
    assert_match(/\Anew_taipei_788_\h{10}\z/, Geojson::BusImporter.slug_for(main, city:))
    assert_match(/\Anew_taipei_788_\h{10}\z/, Geojson::BusImporter.slug_for(extension, city:))
    assert_equal "788（金瓜石）", importer.send(:display_name, "788", "金瓜石")
    assert_equal "788（延駛水湳洞）", importer.send(:display_name, "788", "延駛水湳洞")
    assert_equal "788 (Jinguashi)", importer.send(:display_name_en, "788", "金瓜石")
    assert_equal "788 (extended to Shuinandong)", importer.send(:display_name_en, "788", "延駛水湳洞")
  end

  test "716 path pairs split 低地板 / 非低地板" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = {
      "RouteUID" => "NWT17530",
      "RouteName" => { "Zh_tw" => "716(台灣好行-皇冠北海岸線)" },
      "SubRoutes" => [
        sub.("716捷運淡水站", 0, "NWT158904"), sub.("716野柳地質公園", 1, "NWT159899"),
        sub.("716捷運淡水站不繞", 0, "NWT158698"), sub.("716野柳地質公園不繞", 1, "NWT159900")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    plain = variants.find { |row| row["_import_detour"] == "非低地板" }
    low = variants.find { |row| row["_import_detour"] == "低地板" }

    assert_equal 2, variants.size
    assert_equal %w[NWT158904 NWT159899], plain["_import_sub_uids"]
    assert_equal %w[NWT158698 NWT159900], low["_import_sub_uids"]
    assert_match(/\Anew_taipei_716_-_3190e34ee7_\h{10}\z/, Geojson::BusImporter.slug_for(plain, city:))
    assert_match(/\Anew_taipei_716_-_3190e34ee7_\h{10}\z/, Geojson::BusImporter.slug_for(low, city:))
    assert_equal "716(台灣好行-皇冠北海岸線)（非低地板）",
      importer.send(:display_name, "716(台灣好行-皇冠北海岸線)", "非低地板")
    assert_equal "716(台灣好行-皇冠北海岸線)（低地板）",
      importer.send(:display_name, "716(台灣好行-皇冠北海岸線)", "低地板")
    assert_equal "716(台灣好行-皇冠北海岸線) (non-low-floor)",
      importer.send(:display_name_en, "716(台灣好行-皇冠北海岸線)", "非低地板")
    assert_equal "716(台灣好行-皇冠北海岸線) (low-floor)",
      importer.send(:display_name_en, "716(台灣好行-皇冠北海岸線)", "低地板")
    assert_equal %w[716捷運淡水站 716野柳地質公園], Geojson::BusImporter.path_pair_subroute_names("非低地板")
    assert_equal %w[716捷運淡水站不繞 716野柳地質公園不繞], Geojson::BusImporter.path_pair_subroute_names("低地板")
    note = Geojson::BusImporter.service_note_for("716(台灣好行-皇冠北海岸線)")
    assert_equal "5–10月每日；11–4月僅假日", note["zh"]
  end

  test "notes reservation SubRoutes that need advance booking" do
    sub = ->(name, direction, uid) {
      { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction }
    }
    route = {
      "RouteName" => { "Zh_tw" => "紅68" },
      "SubRoutes" => [
        sub.("紅68", 0, "TPE159413"), sub.("紅68", 1, "TPE159413"),
        sub.("紅68預約公車", 0, "TPE162404"), sub.("紅68預約公車", 1, "TPE162404")
      ]
    }
    note = Geojson::BusImporter.service_note_for("紅68", route: route)
    only = Geojson::BusImporter.service_note_for("紅68預", route: { "RouteName" => { "Zh_tw" => "紅68預" }, "SubRoutes" => [] })

    assert_equal "部分班次須提前預約", note["zh"]
    assert_match(/advance booking/i, note["en"])
    assert_equal "預約公車，須提前預約", only["zh"]
  end

  test "595 path pairs mix 新民／新春 outbound and inbound" do
    sub = ->(name, direction, uid) {
      { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction }
    }
    route = {
      "RouteName" => { "Zh_tw" => "595" },
      "DepartureStopNameZh" => "捷運淡水站",
      "DestinationStopNameZh" => "淡海新市鎮",
      "DestinationStopNameEn" => "Danhai New Town",
      "SubRoutes" => [
        sub.("595新民去", 0, "NWT157895"), sub.("595新民返", 1, "NWT158972"),
        sub.("595新春去", 0, "NWT160677"), sub.("595新春返", 1, "NWT160678")
      ]
    }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    by_label = variants.index_by { |row| row["_import_detour"] }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    stops = [ {
      "Direction" => 0,
      "Stops" => [
        { "StopUID" => "A", "StopName" => { "Zh_tw" => "捷運淡水站" } },
        { "StopUID" => "B", "StopName" => { "Zh_tw" => "淡海新市鎮" } },
        { "StopUID" => "C", "StopName" => { "Zh_tw" => "捷運淡水站" } }
      ]
    } ]

    assert_equal %w[新民 新春 正新民反新春 正新春反新民], variants.map { |row| row["_import_detour"] }
    assert_equal %w[NWT157895 NWT158972], by_label["新民"]["_import_sub_uids"]
    assert_equal %w[NWT160677 NWT160678], by_label["新春"]["_import_sub_uids"]
    assert_equal %w[NWT157895 NWT160678], by_label["正新民反新春"]["_import_sub_uids"]
    assert_equal %w[NWT160677 NWT158972], by_label["正新春反新民"]["_import_sub_uids"]
    assert_equal "595-淡海新市鎮（新民）",
      importer.send(:named_with_via, importer.send(:circular_board_name, "595", route, stops), "595", "新民")
    assert_equal "595-Danhai New Town (Xinmin)",
      importer.send(:named_with_via_en, importer.send(:circular_board_name_en, "595", route, stops), "595", "新民")
    slugs = variants.map { |row| Geojson::BusImporter.slug_for(row, city:) }
    assert_equal 4, slugs.uniq.size
    assert(slugs.all? { |slug| slug.match?(/\Anew_taipei_595_\h{10}\z/) })
  end

  test "splits 596 short turns that only reach 崑崙里" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "596" },
              "DepartureStopNameZh" => "樹林",
              "DestinationStopNameZh" => "板橋",
              "SubRoutes" => [
                sub.("596樹林藝文綜合行政大樓", 0, "NWT158861"), sub.("596樹林藝文綜合行政大樓", 1, "NWT158861"),
                sub.("596崑崙里", 0, "NWT159569"), sub.("596崑崙里", 1, "NWT159569")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    short = variants.find { |row| row["_import_detour"] == "只到崑崙里" }

    assert_equal 2, variants.size
    assert_equal %w[NWT158861], main["_import_sub_uids"]
    assert_nil main["_import_main_label"]
    assert_equal %w[NWT159569], short["_import_sub_uids"]
    assert_equal "new_taipei_596", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_596_\h{10}\z/, Geojson::BusImporter.slug_for(short, city:))
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")
    short_stops = [
      { "Direction" => 0, "Stops" => [
        { "StopName" => { "Zh_tw" => "崑崙里(大觀路)" } },
        { "StopName" => { "Zh_tw" => "萬坪公園" } }
      ] },
      { "Direction" => 1, "Stops" => [
        { "StopName" => { "Zh_tw" => "新北板橋公車站" } },
        { "StopName" => { "Zh_tw" => "崑崙里(大觀路)" } }
      ] }
    ]
    assert_nil importer.send(:circular_board_name, "596", route, short_stops)
    assert_equal "596（只到崑崙里）", importer.send(:display_name, "596", "只到崑崙里")
    assert_equal "596 (to Kunlun Village only)", importer.send(:display_name_en, "596", "只到崑崙里")
  end

  test "splits 941區 short turns that only reach 捷運大坪林站" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "941" },
              "SubRoutes" => [
                sub.("941", 0, "NWT16726"), sub.("941", 1, "NWT16726"),
                sub.("941區", 0, "NWT16727")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    short = variants.find { |row| row["_import_detour"] == "只到捷運大坪林站" }
    importer = Geojson::BusImporter.new(city_id: "NewTaipei")

    assert_equal 2, variants.size
    assert_equal %w[NWT16726], main["_import_sub_uids"]
    assert_equal %w[NWT16727], short["_import_sub_uids"]
    assert_equal "new_taipei_941", Geojson::BusImporter.slug_for(main, city:)
    assert_equal "new_taipei_941_4c2a97a8ee", Geojson::BusImporter.slug_for(short, city:)
    assert_equal "941（只到捷運大坪林站）", importer.send(:display_name, "941", "只到捷運大坪林站")
    assert_equal "941 (to MRT Dapinglin Station only)", importer.send(:display_name_en, "941", "只到捷運大坪林站")
  end

  test "splits 592 繞惠國市場 and 延耕莘醫院" do
    sub = ->(name, direction, uid) { { "SubRouteUID" => uid, "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "592" },
              "SubRoutes" => [
                sub.("592", 0, "NWT158057"), sub.("592", 1, "NWT158057"),
                sub.("592繞惠國市場", 0, "NWT159897"), sub.("592繞惠國市場", 1, "NWT159897"),
                sub.("592延耕莘醫院", 0, "NWT159898"), sub.("592延耕莘醫院", 1, "NWT159898")
              ] }
    variants = Geojson::BusImporter.detour_variants(route)
    city = Geojson::BusCatalog.find("NewTaipei")
    main = variants.find { |row| row["_import_blank_sub"] }
    market = variants.find { |row| row["_import_detour"] == "繞駛惠國市場" }
    hospital = variants.find { |row| row["_import_detour"] == "延駛耕莘醫院" }

    assert_equal 3, variants.size
    assert_equal %w[NWT158057], main["_import_sub_uids"]
    assert_nil main["_import_main_label"]
    assert_equal %w[NWT159897], market["_import_sub_uids"]
    assert_equal %w[NWT159898], hospital["_import_sub_uids"]
    assert_equal "new_taipei_592", Geojson::BusImporter.slug_for(main, city:)
    assert_match(/\Anew_taipei_592_\h{10}\z/, Geojson::BusImporter.slug_for(market, city:))
    assert_match(/\Anew_taipei_592_\h{10}\z/, Geojson::BusImporter.slug_for(hospital, city:))
    assert_operator Geojson::BusImporter.slug_for(market, city:), :!=, Geojson::BusImporter.slug_for(hospital, city:)
  end

  test "splits 經三總 / 不經三總 into 繞駛 and 不繞駛 variants" do
    city = Geojson::BusCatalog.find("Taipei")
    sub = ->(name, direction) { { "SubRouteUID" => "#{name}#{direction}", "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "903" },
              "SubRoutes" => [ sub.("903不經三總", 0), sub.("903不經三總", 1), sub.("903經三總", 0), sub.("903經三總", 1) ] }
    main, detour = Geojson::BusImporter.detour_variants(route)
    rows = [ { "SubRouteName" => "903不經三總" }, { "SubRouteName" => "903經三總" } ]
    own = ->(name, via) { Geojson::BusServiceDays.own_rows(rows, ref: "903", name:, via:).map { |row| row["SubRouteName"] } }
    campus_hash = Digest::SHA1.hexdigest("繞駛三總")[0, 10]

    assert_nil main["_import_main_label"]
    assert_equal "不繞駛三總", detour["_import_detour"]
    assert_equal "taipei_903", Geojson::BusImporter.slug_for(detour, city:)
    assert_equal "taipei_903_#{campus_hash}", Geojson::BusImporter.slug_for(main, city:)
    assert_equal [ "903經三總" ], own.("903", nil)
    assert_equal [ "903不經三總" ], own.("903（不繞駛三總）", "不繞駛三總")
  end

  test "splits a branch run by another operator and keeps its operator" do
    sub = ->(name, direction) { { "SubRouteUID" => "#{name}#{direction}", "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "306" },
              "Operators" => [ { "OperatorID" => "400", "OperatorName" => { "Zh_tw" => "三重客運" } },
                               { "OperatorID" => "800", "OperatorName" => { "Zh_tw" => "大都會客運" } } ],
              "SubRoutes" => [ sub.("306(三重)", 0), sub.("306(三重)", 1), sub.("306(大都會)", 0), sub.("306(大都會)", 1) ] }
    main, branch = Geojson::BusImporter.detour_variants(route)
    importer = Geojson::BusImporter.new(city_id: "Taipei", client: Object.new)
    rows = [ { "SubRouteName" => "306(三重)" }, { "SubRouteName" => "306(大都會)" } ]

    assert_equal "往舊莊", branch["_import_detour"]
    assert_equal "三重客運", importer.send(:operator_for, main)[:name]
    assert_equal "大都會客運", importer.send(:operator_for, branch)[:name]
    assert_equal "#7CB342", Geojson::BusOperatorColors.second_color("三重客運", "大都會客運")
    assert_equal [ "306(三重)" ], Geojson::BusServiceDays.own_rows(rows, ref: "306", name: "306").map { |row| row["SubRouteName"] }
    assert_equal [ "306(大都會)" ], Geojson::BusServiceDays.own_rows(rows, ref: "306", name: "306（往舊莊）", via: "往舊莊").map { |row| row["SubRouteName"] }
  end

  test "two operators on the same subroutes are a joint pair" do
    route = {
      "RouteName" => { "Zh_tw" => "982" },
      "Operators" => [
        { "OperatorID" => "900", "OperatorName" => { "Zh_tw" => "首都客運", "En" => "Capital Bus" } },
        { "OperatorID" => "800", "OperatorName" => { "Zh_tw" => "大都會客運", "En" => "Metropolitan Bus" } }
      ],
      "SubRoutes" => [ { "SubRouteUID" => "NWT1", "SubRouteName" => { "Zh_tw" => "982" } } ]
    }
    operators = Geojson::BusImporter.operators_for_route(route)

    assert_equal %w[首都客運 大都會客運], operators.map { |row| row[:name] }
    assert_equal "Metropolitan Bus", operators.last[:name_en]
    assert_equal "#7CB342", Geojson::BusOperatorColors.second_color(operators[0][:name], operators[1][:name], ref: "982")
  end

  test "splits a short 繞 label listed as a detour" do
    sub = ->(name, direction) { { "SubRouteUID" => "#{name}#{direction}", "SubRouteName" => { "Zh_tw" => name }, "Direction" => direction } }
    route = { "RouteName" => { "Zh_tw" => "249" },
              "SubRoutes" => [ sub.("249", 0), sub.("249", 1), sub.("249繞崁頂", 0), sub.("249繞崁頂", 1) ] }
    main, detour = Geojson::BusImporter.detour_variants(route)

    assert_nil main["_import_main_label"]
    assert_equal "不繞崁頂", detour["_import_detour"]
    assert_equal [ "249" ], Geojson::BusServiceDays.own_rows([ { "SubRouteName" => "249" }, { "SubRouteName" => "249繞崁頂" } ],
      ref: "249", name: "249", via: nil).map { |row| row["SubRouteName"] }
    assert_equal [ "249繞崁頂" ], Geojson::BusServiceDays.own_rows([ { "SubRouteName" => "249" }, { "SubRouteName" => "249繞崁頂" } ],
      ref: "249", name: "249（不繞崁頂）", via: "不繞崁頂").map { |row| row["SubRouteName"] }
  end

  test "names 265中央 and 265明德 as the main lines" do
    central = Geojson::BusImporter.trunk_label("265經中央路")
    mingde = Geojson::BusImporter.trunk_label("265經明德路")

    assert_equal "265", central[:ref]
    assert_equal "265（中央主線）", central[:name]
    assert_equal "265 (Zhongyang Main Line)", central[:name_en]
    assert_equal "265（明德主線）", mingde[:name]
    assert_equal "265 (Mingde Main Line)", mingde[:name_en]
    assert_nil Geojson::BusImporter.trunk_label("265區")
    assert_equal "265經中央路", Geojson::BusImporter.schedule_ref("ref" => "265", "tdx_ref" => "265經中央路")
    assert_equal "265區", Geojson::BusImporter.schedule_ref("ref" => "265區")

    rows = [ { "SubRouteName" => "265經中央路" }, { "SubRouteName" => "265區" } ]
    assert_equal [ "265經中央路" ], Geojson::BusServiceDays.own_rows(
      rows, ref: "265經中央路", name: "265（中央主線）"
    ).map { |row| row["SubRouteName"] }
  end

  test "keeps one SubRoute path per direction for split variants" do
    stop = ->(lon) { { "StopPosition" => { "PositionLon" => lon, "PositionLat" => 25.0 } } }
    stops = [
      { "SubRouteUID" => "S1", "Direction" => 0, "Stops" => [ stop.(121.50), stop.(121.51) ] },
      { "SubRouteUID" => "S2", "Direction" => 0, "Stops" => [ stop.(121.50), stop.(121.51), stop.(121.52) ] }
    ]
    shapes = [
      { "SubRouteUID" => "S1", "Direction" => 0, "Geometry" => "LINESTRING(121.50 25.0, 121.51 25.0)" },
      { "SubRouteUID" => "", "Direction" => 0, "Geometry" => "LINESTRING(121.50 25.0, 121.52 25.0)" },
      { "SubRouteUID" => "", "Direction" => 0, "Geometry" => "LINESTRING(121.50 25.01, 121.52 25.01)" }
    ]

    kept_shapes, kept_stops = Geojson::BusImporter.new(city_id: "Taipei").send(:primary_subroute_rows, shapes, stops)

    assert_equal [ "S2" ], kept_stops.map { |row| row["SubRouteUID"] }
    assert_equal [ shapes[1] ], kept_shapes
  end

  test "clips a borrowed shape that runs past the variant's last stop" do
    line = (0..40).map { |i| [ 121.5 + (i * 0.001), 25.0 ] }
    stops = [ [ 121.5, 25.0 ], [ 121.51, 25.0 ], [ 121.52, 25.0 ] ]

    clipped = Geojson::BusImporter.new(city_id: "Taipei").send(:clip_to_terminals, line, stops)

    assert_equal line.first, clipped.first
    assert_equal [ 121.52, 25.0 ], clipped.last
  end

  test "ref_slug keeps color-coded and Chinese route names distinct" do
    assert_equal "32", Geojson::BusImporter.ref_slug("32")
    assert_equal "hong32", Geojson::BusImporter.ref_slug("紅32")
    assert_equal "lan1", Geojson::BusImporter.ref_slug("藍1")
    assert_equal "shimin1", Geojson::BusImporter.ref_slug("市民1")
    assert_equal "311sh", Geojson::BusImporter.ref_slug("311區")
    assert_equal "791sh", Geojson::BusImporter.ref_slug("791區")
    assert_equal "645sub", Geojson::BusImporter.ref_slug("645副")
    refute_match(/\A791_sh_/, Geojson::BusImporter.ref_slug("791經貢寮區衛生"))
    assert_match(/\A791_[0-9a-f]{10}\z/, Geojson::BusImporter.ref_slug("791經貢寮區衛生"))
    refute_equal Geojson::BusImporter.ref_slug("紅32"), Geojson::BusImporter.ref_slug("32")
    refute_equal Geojson::BusImporter.ref_slug("內湖幹線"), Geojson::BusImporter.ref_slug("紅32")
    assert_match(/\Aganxian_[0-9a-f]{10}\z/, Geojson::BusImporter.ref_slug("內湖幹線"))
  end

  test "modernize_variant_slug maps legacy qu/fu tokens" do
    assert_equal "taipei_311sh", Geojson::BusImporter.modernize_variant_slug("taipei_311qu")
    assert_equal "taipei_645sub", Geojson::BusImporter.modernize_variant_slug("taipei_645fu")
    assert_equal "kaohsiung_ju20bsub_sh_493aafc87e",
      Geojson::BusImporter.modernize_variant_slug("kaohsiung_ju20bfu_qu_493aafc87e")
    assert_equal "taichung_500_sh1_c44e12253d",
      Geojson::BusImporter.modernize_variant_slug("taichung_500_qu1_c44e12253d")
    assert_equal "tra_fugang_depot", Geojson::BusImporter.modernize_variant_slug("tra_fugang_depot")
  end

  test "imports Keelung city bus geometry and stop points without operator fields" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      series: "9",
      client: client,
      rewrite_manifest: false
    )

    path = Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901")
    assert_equal [ "keelung_901" ], result.routes
    assert path.exist?

    data = JSON.parse(path.read)
    assert_equal "Keelung", data.dig("properties", "city_id")
    assert_equal "901", data.dig("properties", "ref")
    assert_match(/\A#[0-9A-Fa-f]{6}\z/, data.dig("properties", "color"))
    assert_nil data.dig("properties", "operator_id")
    assert data["features"].any? { |feature| feature.dig("geometry", "type") == "LineString" }
    station = data["features"].find { |feature| feature.dig("properties", "feature_type") == "station" }
    assert station
    assert_equal "KELST01", station.dig("properties", "station_id")
  ensure
    remove_keelung_fixture("keelung_901")
  end

  test "marks dispatch yards with stop_role depot" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(stop_name: "暖暖分站(調度站)", station_id: "KELDEPOT")
      ]
    )

    Geojson::BusImporter.import!(
      city_id: "Keelung",
      series: "9",
      client: client,
      rewrite_manifest: false
    )

    data = JSON.parse(Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901").read)
    station = data["features"].find { |feature| feature.dig("properties", "feature_type") == "station" }
    assert_equal "depot", station.dig("properties", "stop_role")
    assert Geojson::BusImporter.depot_stop_name?("東南客運停車場")
    assert Geojson::BusImporter.depot_stop_name?("中壢總站")
    assert Geojson::BusImporter.depot_stop_name?("三重客運五股站")
    assert Geojson::BusImporter.depot_stop_name?("八斗子分站")
    refute Geojson::BusImporter.depot_stop_name?("立體停車場(五股公有市場)")
    refute Geojson::BusImporter.depot_stop_name?("南港機廠")
    refute Geojson::BusImporter.depot_stop_name?("安坑輕軌機廠")
    refute Geojson::BusImporter.depot_stop_name?("高鐵總機廠")
    refute Geojson::BusImporter.depot_stop_name?("捷運北屯總站(敦富路)")
    refute Geojson::BusImporter.depot_stop_name?("總站")
  ensure
    remove_keelung_fixture("keelung_901")
  end

  test "imports every route when series is omitted" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record, route_record(uid: "KEL902", name: "902") ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record,
        shape_record(uid: "KEL902", wkt: "LINESTRING(121.74 25.13, 121.75 25.12)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record,
        stop_of_route_record(uid: "KEL902", stop_uid: "KEL2001")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_includes result.routes, "keelung_901"
    assert_includes result.routes, "keelung_902"
  ensure
    remove_keelung_fixture("keelung_901", "keelung_902")
  end

  test "keeps both direction polylines and direction on stops" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record(map_url: "https://example.test/101.png") ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record,
        shape_record(direction: 1, wkt: "LINESTRING(121.739 25.1322, 121.744 25.1282)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record.merge("Direction" => 0),
        stop_of_route_record(stop_uid: "KEL1002").merge("Direction" => 1)
      ]
    )

    Geojson::BusImporter.import!(
      city_id: "Keelung",
      series: "9",
      client: client,
      rewrite_manifest: false
    )

    data = JSON.parse(Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901").read)
    line_features = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
    stations = data["features"].select { |feature| feature.dig("properties", "feature_type") == "station" }

    assert_equal 2, line_features.length
    assert_equal [ 0, 1 ], line_features.map { |feature| feature.dig("properties", "direction") }.sort
    assert_equal "https://example.test/101.png", data.dig("properties", "official_map_url")
    assert_equal [ 0, 1 ], stations.map { |feature| feature.dig("properties", "direction") }.sort
  ensure
    remove_keelung_fixture("keelung_901")
  end

  test "keeps 101 Xiangfeng and Zhongzheng variants and drops extra-digit ghosts" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEL991A", name: "991", headsign: "和平島—經中正路"),
        route_record(uid: "KEL991B", name: "991", headsign: "和平島—經祥豐街"),
        route_record(uid: "KEL3014", name: "9914", headsign: "太白莊→經太平青鳥")
      ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(uid: "KEL991A"),
        shape_record(uid: "KEL991B", wkt: "LINESTRING(121.75 25.14, 121.76 25.15)"),
        shape_record(uid: "KEL3014", wkt: "LINESTRING(121.73 25.13, 121.74 25.14)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(uid: "KEL991A"),
        stop_of_route_record(uid: "KEL991B", stop_uid: "KEL991B1"),
        stop_of_route_record(uid: "KEL3014", stop_uid: "KEL30141")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_equal %w[keelung_991_xiangfeng keelung_991_zhongzheng].sort, result.routes.sort

    zhongzheng = JSON.parse(Geojson::BusLayout.find_geojson("keelung_991_zhongzheng").read)
    assert_equal "991", zhongzheng.dig("properties", "ref")
    assert_equal "中正路", zhongzheng.dig("properties", "via")
    assert_includes zhongzheng.dig("properties", "name"), "中正路"
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "keeps Keelung 301 original plus two detours and drops 3014" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEE0318", name: "301", headsign: "太白莊—經成功市場"),
        route_record(uid: "KEE0325", name: "3014", headsign: "太白莊→經太平青鳥"),
        route_record(uid: "KEE0381", name: "301", headsign: "太白莊→經中山一路"),
        route_record(uid: "KEE0389", name: "301", headsign: "太白莊→經高遠新村")
      ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(uid: "KEE0318", wkt: "LINESTRING(121.74 25.13, 121.75 25.12)"),
        shape_record(uid: "KEE0325", wkt: "LINESTRING(121.73 25.13, 121.74 25.14)"),
        shape_record(uid: "KEE0381"),
        shape_record(uid: "KEE0389", wkt: "LINESTRING(121.75 25.14, 121.76 25.15)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(uid: "KEE0318", stop_uid: "KEE03181"),
        stop_of_route_record(uid: "KEE0325", stop_uid: "KEE03251"),
        stop_of_route_record(uid: "KEE0381"),
        stop_of_route_record(uid: "KEE0389", stop_uid: "KEE03891")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_includes result.routes, "keelung_301"
    refute result.routes.any? { |slug| slug.include?("be8a74ee1e") }
    assert_equal 3, result.routes.length

    original = JSON.parse(Geojson::BusLayout.find_geojson("keelung_301").read)
    assert_equal "301", original.dig("properties", "name")
    assert_nil original.dig("properties", "via")

    detours = result.routes.reject { |slug| slug == "keelung_301" }.sort.map do |slug|
      JSON.parse(Geojson::BusLayout.find_geojson(slug).read).dig("properties", "via")
    end
    assert_equal %w[成功市場 高遠新村].sort, detours.sort
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "keeps extra-digit detours when the 3-digit parent has only one path" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEE0525", name: "306", headsign: "基隆車站—中平街(經西定路)"),
        route_record(uid: "KEE0531", name: "3062", headsign: "中平街—基隆車站(經西定路)"),
        route_record(uid: "KEE0532", name: "3063", headsign: "基隆車站—中平街(經西定路)—經成功市場")
      ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(uid: "KEE0525"),
        shape_record(uid: "KEE0531", wkt: "LINESTRING(121.75 25.14, 121.76 25.15)"),
        shape_record(uid: "KEE0532", wkt: "LINESTRING(121.73 25.13, 121.74 25.14)")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(uid: "KEE0525"),
        stop_of_route_record(uid: "KEE0531", stop_uid: "KEE05311"),
        stop_of_route_record(uid: "KEE0532", stop_uid: "KEE05321")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    vias = result.routes.map do |slug|
      JSON.parse(Geojson::BusLayout.find_geojson(slug).read).dig("properties", "via")
    end
    assert_includes vias, "西定路"
    assert_includes vias, "西定路、成功市場"
    assert_equal 2, result.routes.length
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "keeps extra-digit TDX names when no 3-digit parent exists" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEE0447", name: "4101", headsign: "七堵郵局—壯觀台北(經長庚醫院)")
      ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record(uid: "KEE0447") ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record(uid: "KEE0447") ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_equal [ "keelung_410" ], result.routes
    data = JSON.parse(Geojson::BusLayout.find_geojson("keelung_410").read)
    assert_equal "410", data.dig("properties", "ref")
    assert_nil data.dig("properties", "via")
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "keeps Keelung 17xx routes in 1000+ instead of collapsing to 1xx" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEE1717", name: "1717", headsign: "基隆車站—大武崙")
      ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record(uid: "KEE1717") ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record(uid: "KEE1717") ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_equal [ "keelung_1717" ], result.routes
    path = Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_1717", ref: "1717")
    assert path.exist?
    assert_includes path.to_s, "/1000+/"
    data = JSON.parse(path.read)
    assert_equal "1717", data.dig("properties", "ref")
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "omits via text when a route number has only one path" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEL992", name: "992", headsign: "信義國中—和平島(經祥豐街)")
      ],
      "v2/Bus/Shape/City/Keelung" => [ shape_record(uid: "KEL992") ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record(uid: "KEL992") ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    assert_equal [ "keelung_992" ], result.routes
    data = JSON.parse(Geojson::BusLayout.find_geojson("keelung_992").read)
    assert_equal "992", data.dig("properties", "name")
    assert_nil data.dig("properties", "via")
  ensure
    remove_keelung_fixture("keelung_992")
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "joins two via clauses with a dunhao instead of nested parentheses" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [
        route_record(uid: "KEL993A", name: "993", headsign: "八斗子—經美的世界(經八斗山莊)"),
        route_record(uid: "KEL993B", name: "993", headsign: "八斗子—經中正路")
      ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(uid: "KEL993A"),
        shape_record(uid: "KEL993B")
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [
        stop_of_route_record(uid: "KEL993A"),
        stop_of_route_record(uid: "KEL993B")
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "Keelung",
      client: client,
      rewrite_manifest: false
    )

    nested = result.routes.find { |slug| slug != "keelung_993_zhongzheng" }
    data = JSON.parse(Geojson::BusLayout.find_geojson(nested).read)
    assert_equal "美的世界、八斗山莊", data.dig("properties", "via")
    assert_equal "993（經美的世界、八斗山莊）", data.dig("properties", "name")
    refute_includes data.dig("properties", "name"), "(經"
  ensure
    result&.routes&.each { |slug| remove_keelung_fixture(slug) }
  end

  test "imports InterCity highway coaches from InterCity TDX paths" do
    client = FakeTdxClient.new(
      "v2/Bus/Route/InterCity" => [
        {
          "RouteUID" => "THB1820",
          "RouteName" => { "Zh_tw" => "1820", "En" => "1820" },
          "RouteMapImageUrl" => "https://web.taiwanbus.tw/MISUploadData/Schematic/file/1820.jpg",
          "Operators" => [
            {
              "OperatorID" => "45",
              "OperatorName" => { "Zh_tw" => "國光客運", "En" => "Kuo-Kuang Bus Co., Ltd." }
            }
          ],
          "SubRoutes" => [
            {
              "SubRouteUID" => "THB182001",
              "SubRouteName" => { "Zh_tw" => "1820" },
              "Direction" => 0,
              "Headsign" => "臺北→竹東"
            },
            {
              "SubRouteUID" => "THB182002",
              "SubRouteName" => { "Zh_tw" => "1820" },
              "Direction" => 1,
              "Headsign" => "竹東→臺北"
            },
            {
              "SubRouteUID" => "THB1820A1",
              "SubRouteName" => { "Zh_tw" => "1820A" },
              "Direction" => 0,
              "Headsign" => "臺北→竹東[繞駛關西市區]"
            },
            {
              "SubRouteUID" => "THB1820A2",
              "SubRouteName" => { "Zh_tw" => "1820A" },
              "Direction" => 1,
              "Headsign" => "竹東→臺北[繞駛關西市區]"
            }
          ]
        }
      ],
      "v2/Bus/Shape/InterCity" => [
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB182001",
          "Direction" => 0,
          "Geometry" => "LINESTRING(121.5 25.0, 121.6 25.1)"
        },
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB182002",
          "Direction" => 1,
          "Geometry" => "LINESTRING(121.6 25.1, 121.5 25.0)"
        },
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB1820A1",
          "Direction" => 0,
          "Geometry" => "LINESTRING(121.5 25.0, 121.55 25.05, 121.6 25.1)"
        },
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB1820A2",
          "Direction" => 1,
          "Geometry" => "LINESTRING(121.6 25.1, 121.55 25.05, 121.5 25.0)"
        }
      ],
      "v2/Bus/StopOfRoute/InterCity" => [
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB182001",
          "Direction" => 0,
          "Stops" => [
            {
              "StopUID" => "THB1001",
              "StopName" => { "Zh_tw" => "台北轉運站", "En" => "Taipei Bus Station" },
              "StopSequence" => 1,
              "StopPosition" => { "PositionLon" => 121.5, "PositionLat" => 25.0 }
            }
          ]
        },
        {
          "RouteUID" => "THB1820",
          "SubRouteUID" => "THB1820A1",
          "Direction" => 0,
          "Stops" => [
            {
              "StopUID" => "THB1001",
              "StopName" => { "Zh_tw" => "台北轉運站", "En" => "Taipei Bus Station" },
              "StopSequence" => 1,
              "StopPosition" => { "PositionLon" => 121.5, "PositionLat" => 25.0 }
            }
          ]
        }
      ]
    )

    result = Geojson::BusImporter.import!(
      city_id: "InterCity",
      client: client,
      rewrite_manifest: false
    )

    path = Geojson::BusLayout.geojson_path(
      city_id: "InterCity",
      slug: "inter_city_1820",
      ref: "1820",
      operator_id: "45",
      operator_name: "國光客運"
    )
    path_a = Geojson::BusLayout.geojson_path(
      city_id: "InterCity",
      slug: "inter_city_1820a",
      ref: "1820A",
      operator_id: "45",
      operator_name: "國光客運"
    )
    assert_equal [ "inter_city_1820", "inter_city_1820a" ].sort, result.routes.sort
    assert path.exist?
    assert path_a.exist?

    data = JSON.parse(path.read)
    assert_equal "InterCity", data.dig("properties", "city_id")
    assert_equal "1820", data.dig("properties", "ref")
    assert_equal "45", data.dig("properties", "operator_id")
    assert_equal "國光客運", data.dig("properties", "operator")
    assert_equal data.dig("properties", "color"), JSON.parse(path_a.read).dig("properties", "color")
    assert_includes data.dig("properties", "official_map_url"), "1820.jpg"

    data_a = JSON.parse(path_a.read)
    assert_equal "1820A", data_a.dig("properties", "ref")
    assert_includes data_a.dig("properties", "name"), "繞駛關西市區"
  ensure
    %w[inter_city_1820 inter_city_1820a].each do |slug|
      leftover = Geojson::BusLayout.find_geojson(slug)
      FileUtils.rm_f(leftover) if leftover
    end
  end

  test "exposes InterCity and city TDX paths" do
    city = Geojson::BusCatalog.find("Keelung")
    intercity = Geojson::BusCatalog.find("InterCity")

    assert_equal "v2/Bus/Route/City/Keelung", Geojson::BusImporter.route_path_for(city)
    assert_equal "v2/Bus/Shape/City/Keelung", Geojson::BusImporter.shape_path_for(city)
    assert_equal "v2/Bus/StopOfRoute/City/Keelung", Geojson::BusImporter.stop_of_route_path_for(city)
    assert_equal "v2/Bus/Route/InterCity", Geojson::BusImporter.route_path_for(intercity)
    assert_equal "v2/Bus/Shape/InterCity", Geojson::BusImporter.shape_path_for(intercity)
    assert_equal "v2/Bus/StopOfRoute/InterCity", Geojson::BusImporter.stop_of_route_path_for(intercity)
  end

  test "skips TDX test routes when grouping city routes" do
    city = Geojson::BusCatalog.find("Kaohsiung")
    routes = [
      route_record(uid: "KHH1", name: "紅1"),
      route_record(uid: "KHHTEST", name: "測試路線"),
      route_record(uid: "KHHTEST2", name: "測試路線2")
    ]

    slugs = Geojson::BusImporter.grouped_routes(routes, city:).map(&:first)

    assert_includes slugs, "kaohsiung_hong1"
    assert_not_includes slugs, "kaohsiung_95c1ce5b71"
    assert(slugs.none? { |slug| slug.include?("測試") || slug.match?(/95c1ce5b71|87ee037057/) })
  end

  private

  def remove_keelung_fixture(*slugs)
    slugs.flatten.compact.each do |slug|
      path = Geojson::BusLayout.find_geojson(slug)
      FileUtils.rm_f(path) if path&.exist?
    end
  end

  def route_record(uid: "KEL901", name: "901", map_url: nil, headsign: nil)
    record = {
      "RouteUID" => uid,
      "RouteName" => { "Zh_tw" => name, "En" => name },
      "RouteMapImageUrl" => map_url,
      "Operators" => [
        {
          "OperatorID" => "KeelungBus",
          "OperatorName" => { "Zh_tw" => "基隆市公車處", "En" => "Keelung City Bus" }
        }
      ]
    }
    if headsign
      record["SubRoutes"] = [
        { "SubRouteUID" => "#{uid}01", "SubRouteName" => { "Zh_tw" => name }, "Direction" => 0, "Headsign" => headsign }
      ]
    end
    record
  end

  def shape_record(uid: "KEL901", direction: 0, wkt: "LINESTRING(121.739 25.132, 121.744 25.128)")
    {
      "RouteUID" => uid,
      "Direction" => direction,
      "Geometry" => wkt
    }
  end

  test "keeps full inbound geometry even when it overlaps outbound corridor" do
    shared = "LINESTRING(121.7400 25.1300, 121.7410 25.1300, 121.7420 25.1300, 121.7430 25.1300)"
    inbound_spur = "LINESTRING(121.7400 25.1300, 121.7410 25.1300, 121.7420 25.1300, 121.7420 25.1310, 121.7420 25.1320)"

    client = FakeTdxClient.new(
      "v2/Bus/Route/City/Keelung" => [ route_record ],
      "v2/Bus/Shape/City/Keelung" => [
        shape_record(direction: 0, wkt: shared),
        shape_record(direction: 1, wkt: inbound_spur)
      ],
      "v2/Bus/StopOfRoute/City/Keelung" => [ stop_of_route_record ]
    )

    Geojson::BusImporter.import!(
      city_id: "Keelung",
      series: "9",
      client: client,
      rewrite_manifest: false
    )

    data = JSON.parse(Geojson::BusLayout.geojson_path(city_id: "Keelung", slug: "keelung_901", ref: "901").read)
    routes = data["features"].select { |feature| feature.dig("properties", "feature_type") == "route" }
    outbound = routes.select { |feature| feature.dig("properties", "direction").to_i.zero? }
    inbound = routes.select { |feature| feature.dig("properties", "direction").to_i == 1 }

    assert_operator outbound.sum { |feature| feature.dig("geometry", "coordinates").length }, :>=, 4
    # Must retain the full return path (shared corridor + spur), not spur stubs only.
    assert_operator inbound.sum { |feature| feature.dig("geometry", "coordinates").length }, :>=, 5
  ensure
    remove_keelung_fixture("keelung_901")
  end

  def stop_of_route_record(uid: "KEL901", stop_uid: "KEL1001", stop_name: "基隆車站", station_id: "KELST01")
    {
      "RouteUID" => uid,
      "Stops" => [
        {
          "StopUID" => stop_uid,
          "StationID" => station_id,
          "StopName" => { "Zh_tw" => stop_name, "En" => "Keelung Station" },
          "StopSequence" => 1,
          "StopPosition" => { "PositionLon" => 121.7394, "PositionLat" => 25.1318 }
        }
      ]
    }
  end
end
