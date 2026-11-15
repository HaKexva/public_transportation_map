# frozen_string_literal: true

module Transit
  # Records which buses run which routes (see Transit::BusFleet). The keyless
  # 大臺北 feeds are polled often; TDX cities only when `tdx` is set.
  class CollectBusSightingsJob < ApplicationJob
    queue_as :default

    def perform(tdx = false)
      BusFleet.collect_sightings!(tdx:)
    end
  end
end
