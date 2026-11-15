# frozen_string_literal: true

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  # Every page load polls /api/alerts; keep system tests off the live TDX feed.
  setup do
    @original_metro_alert_feed = Transit::MetroAlertFeed.method(:call)
    Transit::MetroAlertFeed.define_singleton_method(:call) { |**| [] }
  end

  teardown do
    Transit::MetroAlertFeed.define_singleton_method(:call, @original_metro_alert_feed) if @original_metro_alert_feed
  end

  # Sidebar landmark search must not call Google from CI/dev .env keys.
  setup do
    @original_google_maps_api_key = GoogleMaps.method(:api_key)
    GoogleMaps.define_singleton_method(:api_key) { nil }
  end

  teardown do
    GoogleMaps.define_singleton_method(:api_key, @original_google_maps_api_key) if @original_google_maps_api_key
  end

  setup do
    # Transport mode is URL-based (/ vs /bus). Clear any leftover preference from
    # older builds so rail tests are not stuck on the bus sidebar.
    page.execute_script(<<~JS)
      try {
        localStorage.removeItem('map-transport-mode')
        document.cookie = 'locale=; path=/; max-age=0'
      } catch (e) {}
    JS
  rescue Selenium::WebDriver::Error::WebDriverError, Capybara::NotSupportedByDriverError
    # Browser not ready yet on first setup before visit.
  end
end
