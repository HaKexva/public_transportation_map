# frozen_string_literal: true

class ScheduleDataset < ApplicationRecord
  SOURCES = %w[manual file tdx api].freeze

  has_many :service_calendars, dependent: :destroy
  has_many :schedule_trips, dependent: :destroy
  has_many :headway_rules, dependent: :destroy

  validates :name, :source, presence: true
  validates :source, inclusion: { in: SOURCES }

  scope :active, -> { where(active: true) }

  def self.current
    active.order(imported_at: :desc, updated_at: :desc).first
  end

  def activate!
    transaction do
      self.class.where.not(id: id).update_all(active: false)
      update!(active: true, imported_at: Time.current)
    end
  end
end
