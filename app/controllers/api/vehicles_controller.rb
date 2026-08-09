# frozen_string_literal: true

module Api
  class VehiclesController < ApplicationController
    # GET /api/vehicles?at=2026-07-27T10:00:00Z&route_ids[]=bannan&route_ids[]=wenhu_line
    def index
      at = parse_at!(params[:at])
      route_ids = Array(params[:route_ids]).compact.map(&:to_s).reject(&:blank?)

      if route_ids.empty?
        render json: { at: at.iso8601, vehicles: [] }
        return
      end

      query = Transit::VehiclePositionQuery.new(
        at: at,
        route_ids: route_ids,
        datasets: ScheduleDataset.active.to_a
      )
      vehicles = query.call

      render json: { at: at.iso8601, vehicles: vehicles, live: query.live_meta }
    end

    private

    def parse_at!(raw)
      return Time.zone.now if raw.blank?

      parsed =
        begin
          Time.iso8601(raw.to_s).in_time_zone
        rescue ArgumentError, TypeError
          Time.zone.parse(raw.to_s)
        end
      raise ArgumentError if parsed.blank?

      parsed
    rescue ArgumentError, TypeError
      raise ActionController::BadRequest, "Invalid at param (expected ISO time string)"
    end
  end
end
