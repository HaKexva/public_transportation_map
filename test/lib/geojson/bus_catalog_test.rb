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
    assert_equal 1, Geojson::BusCatalog.routes_for(routes, city_id: "Taipei", operator_id: "Capital").length
    assert_equal 3, Geojson::BusCatalog.routes_for(routes, city_id: "Taipei").length
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
    assert_equal [ 0, 300, 500, :color_hong, :color_lan, :neike_commuter, :nangang_soft, :trunk ], grouped.map(&:first)
    assert_equal %w[n2], grouped.assoc(0).last.map { |route| route["id"] }
    assert_equal %w[n1], grouped.assoc(300).last.map { |route| route["id"] }
    assert_equal %w[t1], grouped.assoc(500).last.map { |route| route["id"] }
    assert_equal %w[t2], grouped.assoc(:color_hong).last.map { |route| route["id"] }
    assert_equal %w[n3], grouped.assoc(:color_lan).last.map { |route| route["id"] }
    assert_equal %w[t3], grouped.assoc(:neike_commuter).last.map { |route| route["id"] }
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
    assert_equal :f_series, Geojson::BusCatalog.browse_band("F123")
    assert_equal :ankeng, Geojson::BusCatalog.browse_band("安坑1線")
    assert_equal :named_line, Geojson::BusCatalog.browse_band("吉林線")
    assert_equal :named_line, Geojson::BusCatalog.browse_band("三鶯2線(原812)")
    assert_equal :beishi, Geojson::BusCatalog.browse_band("北士科1")
    assert_equal :huaien, Geojson::BusCatalog.browse_band("懷恩專車S31")
    assert_equal :other, Geojson::BusCatalog.browse_band("三重-內科")
    assert_equal :other, Geojson::BusCatalog.browse_band("汐止-台北101")
    assert_equal :other, Geojson::BusCatalog.browse_band("淡水-國道1號-南港車站")
    assert_equal 700, Geojson::BusCatalog.browse_band("716(台灣好行-皇冠北海岸線)")
    assert_equal 500, Geojson::BusCatalog.browse_band("T517梅山-旗山醫院")
    assert_equal 1000, Geojson::BusCatalog.browse_band("1717")
    assert_equal 1000, Geojson::BusCatalog.browse_band("3014")
    assert_equal 1000, Geojson::BusCatalog.browse_band("5014A")
    assert_equal "1000+", Geojson::BusCatalog.hundreds_band_label(1000)
    assert_equal "1000+", Geojson::BusCatalog.browse_band_dir("1717")
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
end
