# frozen_string_literal: true

require "test_helper"

class GeojsonBusCatalogTest < ActiveSupport::TestCase
  test "lists every TDX city bus region plus highway coaches" do
    ids = Geojson::BusCatalog.cities.map(&:id)

    assert_equal %w[Keelung Taipei NewTaipei Taoyuan Hsinchu], ids.take(5)
    assert_includes ids, "Kaohsiung"
    assert_includes ids, "KinmenCounty"
    assert_not_includes ids, "LienchiangCounty"
    assert_equal "InterCity", ids.last
    assert_equal :intercity, Geojson::BusCatalog.find("InterCity").kind
    assert_equal "Taipei", Geojson::BusCatalog.find("Taipei").tdx_city
    assert_nil Geojson::BusCatalog.find("InterCity").tdx_city
    Geojson::BusCatalog.cities.each do |city|
      assert I18n.exists?("map.bus.cities.#{city.id}", locale: :"zh-TW"), "missing zh-TW label for #{city.id}"
      assert I18n.exists?("map.bus.cities.#{city.id}", locale: :en), "missing en label for #{city.id}"
    end
  end

  test "groups operators within a city from route metadata" do
    routes = [
      { "id" => "a", "city_id" => "Taipei", "operator_id" => "MetroBus", "operator" => "大都會客運", "operator_en" => "Metropolitan Bus" },
      { "id" => "b", "city_id" => "Taipei", "operator_id" => "Capital", "operator" => "首都客運", "operator_en" => "Capital Bus" },
      { "id" => "c", "city_id" => "Taipei", "operator_id" => "MetroBus", "operator" => "大都會客運" },
      { "id" => "d", "city_id" => "InterCity", "operator_id" => "KuoKuang", "operator" => "國光客運" },
      { "id" => "e", "city_id" => "InterCity", "operator_id" => "HoHsin", "operator" => "和欣客運" }
    ]

    grouped = Geojson::BusCatalog.operators_by_city(routes)

    assert_equal %w[MetroBus Capital], grouped.fetch("Taipei").map { |op| op["id"] }
    assert_equal %w[HoHsin KuoKuang], grouped.fetch("InterCity").map { |op| op["id"] }.sort
    assert_equal [ "和欣客運", "國光客運" ], grouped.fetch("InterCity").map { |op| op["name"] }.sort
    joint = { "id" => "j", "city_id" => "Taipei", "operator_id" => "Capital", "operator" => "首都客運", "operator_id_2" => "MetroBus", "operator_2" => "大都會客運" }
    routes << joint
    assert_equal 2, Geojson::BusCatalog.routes_for(routes, city_id: "Taipei", operator_id: "Capital").length
    assert_equal 3, Geojson::BusCatalog.routes_for(routes, city_id: "Taipei", operator_id: "MetroBus").length
    assert_equal 4, Geojson::BusCatalog.routes_for(routes, city_id: "Taipei").length
    assert_not Geojson::BusCatalog.fold_by_operator?("Keelung")
    assert_not Geojson::BusCatalog.fold_by_operator?("Taipei")
    assert_not Geojson::BusCatalog.fold_by_operator?("Taoyuan")
    assert Geojson::BusCatalog.fold_by_operator?("InterCity"), "only highway coaches fold by operator"
  end

  test "folds Greater Taipei routes into hundreds and theme bands" do
    routes = [
      { "id" => "t1", "city_id" => "Taipei", "ref" => "518" },
      { "id" => "t2", "city_id" => "Taipei", "ref" => "紅32" },
      { "id" => "t3", "city_id" => "Taipei", "ref" => "內科通勤專車10" },
      { "id" => "t4", "city_id" => "Taipei", "ref" => "忠孝幹線" },
      { "id" => "t5", "city_id" => "Taipei", "ref" => "南軟通勤專車中和線" },
      { "id" => "n1", "city_id" => "NewTaipei", "ref" => "307" },
      { "id" => "n2", "city_id" => "NewTaipei", "ref" => "39" },
      { "id" => "n3", "city_id" => "NewTaipei", "ref" => "藍1" },
      { "id" => "k1", "city_id" => "Keelung", "ref" => "201" }
    ]

    greater = Geojson::BusCatalog.greater_taipei_routes(routes)
    assert_equal 8, greater.length
    assert_includes Geojson::BusCatalog.sidebar_cities.map(&:id), "Keelung"
    assert_not_includes Geojson::BusCatalog.sidebar_cities.map(&:id), "Taipei"
    assert Geojson::BusCatalog.fold_by_hundreds?("GreaterTaipei")

    grouped = Geojson::BusCatalog.group_by_hundreds(greater)
    assert_equal [ 0, 300, 500, :color_hong, :color_lan, :neike, :nangang_soft, :trunk ], grouped.map(&:first)
    assert_equal %w[n2], grouped.assoc(0).last.map { |route| route["id"] }
    assert_equal %w[n1], grouped.assoc(300).last.map { |route| route["id"] }
    assert_equal %w[t1], grouped.assoc(500).last.map { |route| route["id"] }
    assert_equal %w[t2], grouped.assoc(:color_hong).last.map { |route| route["id"] }
    assert_equal %w[n3], grouped.assoc(:color_lan).last.map { |route| route["id"] }
    assert_equal %w[t3], grouped.assoc(:neike).last.map { |route| route["id"] }
    assert_equal %w[t5], grouped.assoc(:nangang_soft).last.map { |route| route["id"] }
    assert_equal %w[t4], grouped.assoc(:trunk).last.map { |route| route["id"] }
  end

  test "city buses fold by hundreds; themed and non-numeric refs leave number bands" do
    routes = [
      { "id" => "keelung_101", "city_id" => "Keelung", "ref" => "101" },
      { "id" => "keelung_201", "city_id" => "Keelung", "ref" => "201" },
      { "id" => "keelung_201a", "city_id" => "Keelung", "ref" => "201A" },
      { "id" => "keelung_205", "city_id" => "Keelung", "ref" => "205區" },
      { "id" => "keelung_301", "city_id" => "Keelung", "ref" => "301" },
      { "id" => "keelung_3014", "city_id" => "Keelung", "ref" => "3014" },
      { "id" => "keelung_r66", "city_id" => "Keelung", "ref" => "R66" },
      { "id" => "keelung_t99", "city_id" => "Keelung", "ref" => "T99" },
      { "id" => "hong", "city_id" => "Taipei", "ref" => "紅32" },
      { "id" => "neike", "city_id" => "Taipei", "ref" => "內科通勤專車10" },
      { "id" => "express", "city_id" => "Taipei", "ref" => "內科快線1" },
      { "id" => "sightseeing_red", "city_id" => "Taipei", "ref" => "臺北觀光巴士紅線" },
      { "id" => "sightseeing_blue", "city_id" => "Taipei", "ref" => "臺北觀光巴士藍線" },
      { "id" => "nangang", "city_id" => "Taipei", "ref" => "南軟通勤專車中和線" },
      { "id" => "commuter", "city_id" => "Taipei", "ref" => "通勤11" },
      { "id" => "named", "city_id" => "Taipei", "ref" => "藍線" },
      { "id" => "tour", "city_id" => "KinmenCounty", "ref" => "台灣好行北竿線" },
      { "id" => "jilin", "city_id" => "NewTaipei", "ref" => "吉林線" },
      { "id" => "ankeng", "city_id" => "NewTaipei", "ref" => "安坑1線" },
      { "id" => "fbus", "city_id" => "NewTaipei", "ref" => "F123" },
      { "id" => "xiao", "city_id" => "NewTaipei", "ref" => "小12" },
      { "id" => "civic", "city_id" => "Taipei", "ref" => "市民小巴10" },
      { "id" => "od", "city_id" => "NewTaipei", "ref" => "三重-內科" },
      { "id" => "kh_t", "city_id" => "Kaohsiung", "ref" => "T201" }
    ]

    assert_equal :keelung_tr, Geojson::BusCatalog.browse_band("R66", city_id: "Keelung")
    assert_equal :keelung_tr, Geojson::BusCatalog.browse_band("T99", city_id: "Keelung")
    assert_equal 200, Geojson::BusCatalog.browse_band("T201", city_id: "Kaohsiung")
    assert_equal 0, Geojson::BusCatalog.browse_band("79", city_id: "Keelung")
    assert_equal 0, Geojson::BusCatalog.browse_band("R66") # without city → numeric fallthrough
    assert_equal :color_hong, Geojson::BusCatalog.browse_band("紅32")
    assert_equal :metro_feeder, Geojson::BusCatalog.browse_band("GR", city_id: "Taoyuan")
    assert_equal :metro_feeder, Geojson::BusCatalog.browse_band("GR1", city_id: "Taoyuan")
    assert_equal :metro_feeder, Geojson::BusCatalog.browse_band("GR2", city_id: "Taoyuan")
    assert_equal :metro_feeder, Geojson::BusCatalog.browse_band("BR", city_id: "Taoyuan")
    assert_equal :taoyuan_trunk, Geojson::BusCatalog.browse_band("1", city_id: "Taoyuan")
    assert_equal :taoyuan_trunk, Geojson::BusCatalog.browse_band("1A", city_id: "Taoyuan")
    assert_equal :taoyuan_trunk, Geojson::BusCatalog.browse_band("100", city_id: "Taoyuan")
    assert_equal 100, Geojson::BusCatalog.browse_band("101", city_id: "Taoyuan")
    assert_equal 0, Geojson::BusCatalog.browse_band("1", city_id: "Taipei")
    assert_equal "台一幹線", Geojson::BusCatalog.taoyuan_trunk_name("1A")
    assert_equal "中山長興幹線", Geojson::BusCatalog.taoyuan_trunk_name("11A")
    assert_equal "大湳長庚幹線", Geojson::BusCatalog.taoyuan_trunk_name("12A")
    assert_equal "龍壽南竹幹線", Geojson::BusCatalog.taoyuan_trunk_name("13")
    assert_nil Geojson::BusCatalog.taoyuan_trunk_name("13A")
    assert_equal "中園大竹幹線", Geojson::BusCatalog.taoyuan_trunk_name("15")
    assert_equal "大龍竹幹線", Geojson::BusCatalog.taoyuan_trunk_name("16")
    assert_equal :taoyuan_tourist, Geojson::BusCatalog.browse_band("501", city_id: "Taoyuan")
    assert_equal :taoyuan_tourist, Geojson::BusCatalog.browse_band("502(大溪站發車)", city_id: "Taoyuan")
    assert_equal :taoyuan_tourist, Geojson::BusCatalog.browse_band("506", city_id: "Taoyuan")
    assert_equal 1000, Geojson::BusCatalog.browse_band("5010", city_id: "Taoyuan")
    assert_equal :taoyuan_free, Geojson::BusCatalog.browse_band("L502", city_id: "Taoyuan")
    assert_equal :taoyuan_free, Geojson::BusCatalog.browse_band("L110", city_id: "Taoyuan")
    assert_equal :taoyuan_xingfu, Geojson::BusCatalog.browse_band("T100", city_id: "Taoyuan")
    assert_equal 500, Geojson::BusCatalog.browse_band("501", city_id: "Taipei")
    assert_equal :loop_line, Geojson::BusCatalog.browse_band("NL", city_id: "Taoyuan")
    assert_equal :loop_line, Geojson::BusCatalog.browse_band("SL", city_id: "Taoyuan")
    assert_equal :named_line, Geojson::BusCatalog.browse_band("紅線", city_id: "Taoyuan")
    assert_equal :named_line, Geojson::BusCatalog.browse_band("綠線", city_id: "Taoyuan")
    assert_equal :named_line, Geojson::BusCatalog.browse_band("黃線", city_id: "Taoyuan")
    assert_equal :color_hong, Geojson::BusCatalog.browse_band("紅32", city_id: "Taipei")
    assert_equal :f_series, Geojson::BusCatalog.browse_band("F123")
    assert_equal :ankeng, Geojson::BusCatalog.browse_band("安坑1線")
    assert_equal :taipei_tourist, Geojson::BusCatalog.browse_band("臺北觀光巴士紅線")
    assert_equal :taipei_tourist, Geojson::BusCatalog.browse_band("臺北觀光巴士藍線")
    assert_equal :taipei_tourist, Geojson::BusCatalog.browse_band("台北觀光巴士紅線")
    assert_equal "taipei-tourist", Geojson::BusCatalog.browse_band_dir("臺北觀光巴士紅線")
    assert_equal :commuter, Geojson::BusCatalog.browse_band("雙園巴士")
    assert_equal :commuter, Geojson::BusCatalog.browse_band("通勤11")
    assert_equal :named_line, Geojson::BusCatalog.browse_band("吉林線")
    assert_equal :named_line, Geojson::BusCatalog.browse_band("三鶯2線(原812)")
    assert_equal 900, Geojson::BusCatalog.browse_band("982直達")
    assert_equal 900, Geojson::BusCatalog.browse_band("982直達新埔線")
    assert_equal :beishi, Geojson::BusCatalog.browse_band("北士科1")
    assert_equal :huaien, Geojson::BusCatalog.browse_band("懷恩專車S31")
    assert_equal :leapfrog, Geojson::BusCatalog.browse_band("三重-內科")
    assert_equal :leapfrog, Geojson::BusCatalog.browse_band("汐止-台北101")
    assert_equal :leapfrog, Geojson::BusCatalog.browse_band("淡水-國道1號-南港車站")
    assert_equal :leapfrog, Geojson::BusCatalog.browse_band("853跳蛙")
    assert_equal "leapfrog", Geojson::BusCatalog.browse_band_dir("三重-內科")
    assert_equal 700, Geojson::BusCatalog.browse_band("716(台灣好行-皇冠北海岸線)")
    assert_equal 500, Geojson::BusCatalog.browse_band("T517梅山-旗山醫院")
    assert_equal 1000, Geojson::BusCatalog.browse_band("1717")
    assert_equal 1000, Geojson::BusCatalog.browse_band("3014")
    assert_equal 1000, Geojson::BusCatalog.browse_band("5014A")
    assert_equal "1000+", Geojson::BusCatalog.hundreds_band_label(1000)
    assert_equal "1000+", Geojson::BusCatalog.browse_band_dir("1717")
    assert_equal "hong", Geojson::BusCatalog.browse_band_dir("紅32")
    assert_equal "r-t", Geojson::BusCatalog.browse_band_dir("R66", city_id: "Keelung")
    assert_equal "trunk", Geojson::BusCatalog.browse_band_dir("忠孝幹線")
    assert_equal "0", Geojson::BusCatalog.browse_band_key(0)
    assert_equal "color_hong", Geojson::BusCatalog.browse_band_key(:color_hong)
    assert_equal 100, Geojson::BusCatalog.parse_browse_band_key("100")
    assert_equal :color_hong, Geojson::BusCatalog.parse_browse_band_key("color_hong")
    assert_not_equal 0, Geojson::BusCatalog.browse_band("北士科1")
    assert_not_equal 0, Geojson::BusCatalog.browse_band("懷恩專車S31")
    assert_not_equal 0, Geojson::BusCatalog.browse_band("三鶯2線(原812)")

    grouped = Geojson::BusCatalog.group_by_hundreds(routes.select { |r| r["city_id"] == "Keelung" })
    assert_equal :keelung_tr, grouped.first.first
    assert_equal %w[keelung_r66 keelung_t99], grouped.assoc(:keelung_tr).last.map { |route| route["id"] }.sort
    assert_nil grouped.assoc(0)
    assert_equal %w[keelung_3014], grouped.assoc(1000).last.map { |route| route["id"] }

    Geojson::BusCatalog::SPECIAL_BAND_ORDER.each do |band|
      assert I18n.exists?("map.bus.bands.#{band}", locale: :"zh-TW"), "missing zh-TW band #{band}"
      assert I18n.exists?("map.bus.bands.#{band}", locale: :en), "missing en band #{band}"
    end
  end

  test "clusters highway-coach operator route numbers into sidebar ranges" do
    routes = [
      { "ref" => "1751" },
      { "ref" => "1800A" },
      { "ref" => "1881" },
      { "ref" => "7000" },
      { "ref" => "7005" },
      { "ref" => "南投" }
    ]

    assert_equal %w[1751–1881 7000–7005], Geojson::BusCatalog.operator_ref_ranges(routes)
    assert_equal [ "1551" ], Geojson::BusCatalog.operator_ref_ranges([ { "ref" => "1551" } ])
    assert_equal [], Geojson::BusCatalog.operator_ref_ranges([ { "ref" => "台灣好行" } ])
  end

  test "sorts 繞駛三總 campus variants above the timed skip" do
    routes = [
      { "id" => "taipei_645", "ref" => "645", "campus_span" => "outside" },
      { "id" => "taipei_645_1652fe7623", "ref" => "645", "campus_span" => "inside" },
      { "id" => "taipei_645sub", "ref" => "645副", "campus_span" => "outside" },
      { "id" => "taipei_645sub_1652fe7623", "ref" => "645副", "campus_span" => "inside" }
    ]

    assert_equal %w[
      taipei_645_1652fe7623
      taipei_645
      taipei_645sub_1652fe7623
      taipei_645sub
    ], Geojson::BusCatalog.sort_routes(routes).map { |route| route["id"] }
  end

  test "sorts 521/903-style 經三總 id suffix above 不繞駛 sibling" do
    routes = [
      { "id" => "taipei_521", "ref" => "521", "via" => "不繞駛三總" },
      { "id" => "taipei_521_1652fe7623", "ref" => "521" },
      { "id" => "taipei_531", "ref" => "531" }
    ]

    assert_equal %w[
      taipei_521_1652fe7623
      taipei_521
      taipei_531
    ], Geojson::BusCatalog.sort_routes(routes).map { |route| route["id"] }
  end
end
