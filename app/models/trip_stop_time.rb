# frozen_string_literal: true

class TripStopTime < ApplicationRecord
  belongs_to :schedule_trip

  validates :station_ref, :stop_sequence, presence: true
  validates :stop_sequence, uniqueness: { scope: :schedule_trip_id }
  validates :station_ref, uniqueness: { scope: :schedule_trip_id }

  def pass_time
    departure_time || arrival_time
  end
end
