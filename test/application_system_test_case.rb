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

  setup do
    # Transport mode is URL-based (/ vs /bus). Clear any leftover preference from
    # older builds so rail tests are not stuck on the bus sidebar.
    page.execute_script("try { localStorage.removeItem('map-transport-mode') } catch (e) {}")
  rescue Selenium::WebDriver::Error::WebDriverError, Capybara::NotSupportedByDriverError
    # Browser not ready yet on first setup before visit.
  end
end
