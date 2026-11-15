# frozen_string_literal: true

require "test_helper"

class GeojsonPlusCodeTest < ActiveSupport::TestCase
  test "decodes a full code to its centre" do
    assert_equal [ -122.084063, 37.422063 ], Geojson::PlusCode.decode("849VCWC8+R9")
  end

  test "recovers a short code near the reference point" do
    assert_equal [ 121.517063, 25.047813 ], Geojson::PlusCode.decode("2GX8+4R 台北市", reference: [ 121.9, 24.6 ])
    assert_nil Geojson::PlusCode.decode("2GX8+4R")
  end

  test "ignores plain coordinates" do
    assert_not Geojson::PlusCode.code?("121.5170")
    assert_not Geojson::PlusCode.code?("")
  end
end
