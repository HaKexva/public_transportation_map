# frozen_string_literal: true

module Transit
  # Daily copy of the registered bus fleet (class, power, low floor) by plate.
  class RefreshBusVehiclesJob < ApplicationJob
    queue_as :default

    def perform
      BusFleet.refresh_vehicles!
    end
  end
end
