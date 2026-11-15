# frozen_string_literal: true

require "application_system_test_case"

class ItineraryTest < ApplicationSystemTestCase
  setup do
    @graph = Transit::Itinerary::Compiler.build(patterns: [
      {
        id: "blue",
        name: "測試捷運",
        mode: "metro",
        color: "#0070bd",
        stops: [
          { key: "a", name: "規劃起站", lat: 25.05, lon: 121.50, kind: "metro" },
          { key: "b", name: "規劃迄站", lat: 25.08, lon: 121.50, kind: "metro" }
        ],
        services: { "daily" => { trips: [
          { train: "1001", times: [ 8 * 60, 8 * 60 + 12 ] },
          { train: "1003", times: [ 8 * 60 + 20, 8 * 60 + 32 ] }
        ], headways: [] } }
      },
      {
        id: "bus",
        name: "測試公車",
        mode: "bus",
        color: "#2563eb",
        stops: [
          { key: "a", name: "規劃起站", lat: 25.05, lon: 121.50, kind: "bus" },
          { key: "b", name: "規劃迄站", lat: 25.08, lon: 121.50, kind: "bus" }
        ],
        services: { "daily" => { trips: [
          { train: nil, times: [ 8 * 60 + 5, 8 * 60 + 35 ] }
        ], headways: [] } }
      }
    ])
    Transit::Itinerary::Graph.override = @graph
  end

  teardown do
    Transit::Itinerary::Graph.clear_override!
  end

  test "plans a trip from the sidebar and draws it on the map" do
    visit plan_map_path
    assert_selector ".leaflet-container", wait: 10
    assert_selector ".map-page-mode__chip--active", text: "規劃路線"
    assert_no_selector "#layer-search"
    assert_no_selector ".map-transport-mode"

    fill_in "出發地", with: "規劃起站"
    fill_in "目的地", with: "規劃迄站"
    page.execute_script("document.getElementById('itinerary-depart').value = '2026-10-26T07:50'")
    click_on "規劃"

    assert_selector ".itinerary-segment__id", text: "A", wait: 10
    assert_selector ".itinerary-segment", text: /測試捷運|測試公車/
    assert_selector ".itinerary-detail", text: "1001", wait: 10
    assert_selector ".itinerary-train", text: "1003"
    assert_selector ".itinerary-line", visible: :all, wait: 10

    find(".itinerary-train", text: "1003").click
    assert_selector ".itinerary-leg__title", text: /08:20.*1003/
    assert_selector ".itinerary-train.is-chosen", text: "1003"
  end
end
