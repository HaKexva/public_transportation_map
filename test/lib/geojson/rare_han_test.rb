# frozen_string_literal: true

require "test_helper"

class Geojson::RareHanTest < ActiveSupport::TestCase
  test "substitutes Ext. C 𫙮 used in 瑞芳𫙮魚坑 for display fonts" do
    assert_equal "傑魚坑路", Geojson::RareHan.display("𫙮魚坑路")
    assert_equal "傑魚坑", Geojson::RareHan.display("\u{2B66E}魚坑")
    assert_equal "平常路", Geojson::RareHan.display("平常路")
    assert_equal "", Geojson::RareHan.display(nil)
  end
end
