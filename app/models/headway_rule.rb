# frozen_string_literal: true

class HeadwayRule < ApplicationRecord
  belongs_to :schedule_dataset
  belongs_to :transit_route
  belongs_to :service_calendar

  validates :direction, :starts_at, :ends_at, :interval_seconds, presence: true
  validates :interval_seconds, numericality: { greater_than: 0 }

  def interval_minutes
    interval_seconds / 60
  end
end
