# frozen_string_literal: true

class AddStationRefIndexToTripStopTimes < ActiveRecord::Migration[8.1]
  def change
    add_index :trip_stop_times, :station_ref
  end
end
