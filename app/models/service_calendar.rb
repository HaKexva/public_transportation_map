# frozen_string_literal: true

class ServiceCalendar < ApplicationRecord
  COMMON_CODES = {
    "weekday" => "平日",
    "saturday" => "週六",
    "sunday" => "週日",
    "holiday" => "國定假日"
  }.freeze

  belongs_to :schedule_dataset
  has_many :schedule_trips, dependent: :destroy
  has_many :headway_rules, dependent: :destroy

  validates :code, :name, presence: true
  validates :code, uniqueness: { scope: :schedule_dataset_id }
end
