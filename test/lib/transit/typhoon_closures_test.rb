# frozen_string_literal: true

require "test_helper"

class TyphoonClosuresTest < ActiveSupport::TestCase
  HTML = <<~HTML
    <FONT>臺北市</FONT></TD><TD><FONT color=#FF0000 >今天已達停止上班及上課標準。</FONT>
    <FONT>高雄市</FONT></TD><TD><FONT>今天未達停止上班及上課標準。</FONT>
    <FONT>臺南市</FONT></TD><TD><FONT>明天停止上班、停止上課。</FONT>
    <FONT>金門縣</FONT></TD><TD><FONT>照常上班停止上課。</FONT>
    <FONT>外島地區</FONT></TD><TD><FONT>澎湖縣</FONT>
  HTML

  test "keeps only dates when work is stopped, not the surrounding days" do
    today = Date.new(2026, 10, 24)
    dates = Transit::TyphoonClosures.dates(http_get: ->(_) { HTML }, today:)

    assert_equal [ today, today + 1 ], dates
  end
end
