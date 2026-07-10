# frozen_string_literal: true

class TransitRoute < ApplicationRecord
  DIRECTION_BOTH = "both"
  DIRECTION_FORWARD = "forward"
  DIRECTION_REVERSE = "reverse"
  DIRECTIONS = [ DIRECTION_BOTH, DIRECTION_FORWARD, DIRECTION_REVERSE ].freeze

  has_many :transit_route_stations, dependent: :destroy
  has_many :schedule_trips, dependent: :destroy
  has_many :headway_rules, dependent: :destroy

  validates :system_id, :route_id, :name, :line_ref, presence: true
  validates :route_id, uniqueness: { scope: :system_id }

  scope :for_system, ->(system_id) { where(system_id: system_id) }

  def self.find_by_manifest!(system_id:, route_id:)
    find_by!(system_id: system_id, route_id: route_id)
  end

  def manifest_key
    { "system_id" => system_id, "id" => route_id }
  end

  def branch_route
    return nil if branch_of_route_id.blank?

    self.class.find_by(system_id: system_id, route_id: branch_of_route_id)
  end
end
