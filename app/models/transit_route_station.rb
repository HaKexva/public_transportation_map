# frozen_string_literal: true

class TransitRouteStation < ApplicationRecord
  belongs_to :transit_route

  validates :station_ref, :name, :stop_sequence, :direction, presence: true
  validates :station_ref, uniqueness: { scope: %i[transit_route_id direction] }
  validates :stop_sequence, uniqueness: { scope: %i[transit_route_id direction] }
  validates :direction, inclusion: { in: TransitRoute::DIRECTIONS }

  scope :ordered, -> { order(:stop_sequence) }
  scope :for_direction, ->(direction) { where(direction: direction) }
end
