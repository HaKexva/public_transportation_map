# frozen_string_literal: true

class ScheduleDataset < ApplicationRecord
  SOURCES = %w[manual file tdx api].freeze

  has_many :service_calendars, dependent: :destroy
  has_many :schedule_trips, dependent: :destroy
  has_many :headway_rules, dependent: :destroy

  validates :name, :source, presence: true
  validates :source, inclusion: { in: SOURCES }

  scope :active, -> { where(active: true) }
  scope :tdx, -> { where(source: "tdx") }

  def self.current
    active.order(imported_at: :desc, updated_at: :desc).first
  end

  # Marks this snapshot as queryable. Other sources stay active so TDX, 糖鐵,
  # and 林鐵 datasets can be used together.
  def activate!
    update!(active: true, imported_at: Time.current)
  end

  def self.discard_replaced!(source:, keep_id:)
    ids = where(source: source).where.not(id: keep_id).pluck(:id)
    return if ids.empty?

    trip_ids = ScheduleTrip.where(schedule_dataset_id: ids).pluck(:id)
    TripStopTime.where(schedule_trip_id: trip_ids).in_batches.delete_all if trip_ids.any?
    ScheduleTrip.where(schedule_dataset_id: ids).delete_all
    HeadwayRule.where(schedule_dataset_id: ids).delete_all
    ServiceCalendar.where(schedule_dataset_id: ids).delete_all
    where(id: ids).delete_all
  end
end
