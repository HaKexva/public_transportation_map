# frozen_string_literal: true

module Api
  class StationBoardsController < ApplicationController
    def index
      at = parse_at!(params[:at])
      station_ref = params[:ref].to_s
      route_ids = Array(params[:route_ids]).compact.map(&:to_s).reject(&:blank?)

      if station_ref.blank?
        render json: { at: at.iso8601, station_ref: "", stops: [] }
        return
      end

      payload = Transit::StationBoardQuery.new(
        at: at,
        station_ref: station_ref,
        route_ids: route_ids,
        from_minutes: params[:from],
        until_minutes: params[:until]
      ).call

      render json: payload
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
