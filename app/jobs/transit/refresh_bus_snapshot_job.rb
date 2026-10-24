# frozen_string_literal: true

module Transit
  # Keeps bus_route_timetables fresh so bus route details never wait on TDX.
  class RefreshBusSnapshotJob < ApplicationJob
    queue_as :default

    def perform(client: TdxClient.new(ignore_breaker: true))
      return unless client.configured?

      Geojson::BusServiceDays.refresh!(client:, apply: false)
    end
  end
end
