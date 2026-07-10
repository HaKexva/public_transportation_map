# frozen_string_literal: true

class ScheduleTrip < ApplicationRecord
  belongs_to :schedule_dataset
  belongs_to :transit_route
  belongs_to :service_calendar
  has_many :trip_stop_times, -> { order(:stop_sequence) }, dependent: :destroy, inverse_of: :schedule_trip

  validates :direction, presence: true

  scope :for_route, ->(transit_route) { where(transit_route: transit_route) }
  scope :for_calendar, ->(service_calendar) { where(service_calendar: service_calendar) }

  def ordered_stop_times
    trip_stop_times.order(:stop_sequence)
  end
end
