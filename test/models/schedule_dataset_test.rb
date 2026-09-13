# frozen_string_literal: true

require "test_helper"

class ScheduleDatasetTest < ActiveSupport::TestCase
  test "activate! does not deactivate other sources" do
    manual = ScheduleDataset.create!(name: "林鐵", source: "manual", active: true)
    tdx = ScheduleDataset.create!(name: "TDX", source: "tdx", active: false)

    tdx.activate!

    assert tdx.reload.active?
    assert manual.reload.active?
  end

  test "discard_replaced! destroys other rows of the same source" do
    keep = ScheduleDataset.create!(name: "TDX new", source: "tdx", active: true)
    old = ScheduleDataset.create!(name: "TDX old", source: "tdx", active: false)
    manual = ScheduleDataset.create!(name: "糖鐵", source: "manual", active: true)

    ScheduleDataset.discard_replaced!(source: "tdx", keep_id: keep.id)

    assert ScheduleDataset.exists?(keep.id)
    refute ScheduleDataset.exists?(old.id)
    assert ScheduleDataset.exists?(manual.id)
  end
end
