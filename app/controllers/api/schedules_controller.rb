# frozen_string_literal: true

module Api
  class SchedulesController < ApplicationController
    def index
      date = parse_date!(params[:date])
      route_ids = Array(params[:route_ids]).compact.map(&:to_s).reject(&:blank?)

      if route_ids.empty?
        render json: { date: date.iso8601, routes: [] }
        return
      end

      cache_key = [
        "schedule_snapshot/v1",
        date.iso8601,
        route_ids.sort.join(",")
      ]
      payload = Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
        Transit::ScheduleSnapshot.new(date: date, route_ids: route_ids).call
      end

      render json: payload
    end

    private

    def parse_date!(raw)
      zone = ActiveSupport::TimeZone["Taipei"]
      return zone.today if raw.blank?

      parsed = zone.parse(raw.to_s)&.to_date || Date.iso8601(raw.to_s)
      raise ArgumentError if parsed.blank?

      parsed
    rescue ArgumentError, TypeError
      raise ActionController::BadRequest, "Invalid date param"
    end
  end
end
