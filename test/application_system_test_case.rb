# frozen_string_literal: true

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  setup do
    # Transport mode is URL-based (/ vs /bus). Clear any leftover preference from
    # older builds so rail tests are not stuck on the bus sidebar.
    page.execute_script("try { localStorage.removeItem('map-transport-mode') } catch (e) {}")
  rescue Selenium::WebDriver::Error::WebDriverError, Capybara::NotSupportedByDriverError
    # Browser not ready yet on first setup before visit.
  end
end
