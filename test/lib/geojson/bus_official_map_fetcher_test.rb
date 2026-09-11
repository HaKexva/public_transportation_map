# frozen_string_literal: true

require "test_helper"

class GeojsonBusOfficialMapFetcherTest < ActiveSupport::TestCase
  class StubFetcher < Geojson::BusOfficialMapFetcher
    def initialize(bodies)
      super(city_ids: [], resolve_portals: false, rewrite_manifest: false, sync_tdx: false)
      @bodies = bodies
    end

    def http_get_body(url)
      @bodies[url]
    end
  end

  test "resolves taipei MapOverview HTML to File/Get image" do
    portal = "https://ebus.gov.taipei/MapOverview?nid=0100023400"
    body = %(<img src="./File/Get/abc-123?v=1" width="1024" />)
    fetcher = StubFetcher.new(portal => body)

    assert_equal "https://ebus.gov.taipei/File/Get/abc-123?v=1", fetcher.resolve_direct_image_url(portal)
  end

  test "resolves taichung route-map HTML to strapi upload" do
    portal = "https://citybus.taichung.gov.tw/ebus/route-map/1"
    body = %(<img src=https://citybus.taichung.gov.tw/ebus/strapi/uploads/1_f944e75a53.jpeg />)
    fetcher = StubFetcher.new(portal => body)

    assert_equal(
      "https://citybus.taichung.gov.tw/ebus/strapi/uploads/1_f944e75a53.jpeg",
      fetcher.resolve_direct_image_url(portal)
    )
  end

  test "resolves tcbus lineimage HTML to gif" do
    portal = "https://www.tcbus.com.tw/image/lineimage.php?imagetest=100"
    body = %(<img src=100.gif border="0">)
    fetcher = StubFetcher.new(portal => body)

    assert_equal "https://www.tcbus.com.tw/image/100.gif", fetcher.resolve_direct_image_url(portal)
  end

  test "keeps direct image urls unchanged" do
    url = "https://web.taiwanbus.tw/MISUploadData/Schematic/file/1820.jpg"
    fetcher = StubFetcher.new({})

    assert_equal url, fetcher.resolve_direct_image_url(url)
  end

  test "resolves kinmen routemap HTML to cms image" do
    portal = "http://ebus.kinmen.gov.tw/extend/routemap.php?routename=15"
    body = %(<img src="https://ebus.kinmen.gov.tw/cms/api/route/1512/map/253/image" >)
    fetcher = StubFetcher.new(portal => body)

    assert_equal(
      "https://ebus.kinmen.gov.tw/cms/api/route/1512/map/253/image",
      fetcher.resolve_direct_image_url(portal)
    )
  end

  test "resolves kinmen extend png maps" do
    portal = "http://ebus.kinmen.gov.tw/extend/routemap.php?routename=8822"
    body = %(<img src="https://ebus.kinmen.gov.tw/extend/route20230601/8822.png" >)
    fetcher = StubFetcher.new(portal => body)

    assert_equal(
      "https://ebus.kinmen.gov.tw/extend/route20230601/8822.png",
      fetcher.resolve_direct_image_url(portal)
    )
  end

  test "drops taoyuan SPA and lienchiang homepage urls" do
    fetcher = StubFetcher.new({})

    assert_nil fetcher.resolve_direct_image_url("https://ebus.tycg.gov.tw/ebus/driving-map/12")
    assert_nil fetcher.resolve_direct_image_url("https://www.matsutransit.com/")
    assert_nil fetcher.resolve_direct_image_url("https://citybus.taichung.gov.tw/ebus/strapi")
  end
end
