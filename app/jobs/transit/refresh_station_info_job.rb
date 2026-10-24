# frozen_string_literal: true

module Transit
  # Keeps station_infos fresh so station exits / facilities never wait on TDX.
  class RefreshStationInfoJob < ApplicationJob
    queue_as :default

    def perform(client: TdxClient.new(ignore_breaker: true))
      return unless client.configured?

      StationInfoImporter.import!(client:)
    end
  end
end
