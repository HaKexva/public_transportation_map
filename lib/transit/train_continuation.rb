# frozen_string_literal: true

module Transit
  # TRA/HSR 交路：本班次終點後改編號續駛。
  class TrainContinuation
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    WINDOW_MINUTES = 25
    SYSTEMS = %w[tra hsr].freeze
    NOTE_PATTERN = /改(?:為|駛)\s*([A-Za-z0-9]+)\s*次/

    def initialize(calendar_ids:)
      @calendar_ids = Array(calendar_ids).compact
    end

    def self.relevant_system?(system_id)
      SYSTEMS.include?(system_id.to_s)
    end

    def self.same_station?(left, right)
      tokens_a = station_tokens(left)
      tokens_b = station_tokens(right)
      tokens_a.any? && tokens_b.any? && tokens_a.intersect?(tokens_b)
    end

    def self.station_tokens(ref)
      ref.to_s.split(/[;|,]/).filter_map { |part|
        token = part.strip.downcase
        token.presence
      }.uniq
    end

    def lookup(trip_id:, train_number:, last_station_ref:, arrival_minutes:, notes: nil)
      return nil unless last_station_ref.present? && arrival_minutes
      return nil if @calendar_ids.empty?

      preferred = preferred_number_from_notes(notes)
      candidates = candidates_from(last_station_ref)
      candidates.reject! { |entry| entry[:trip_id] == trip_id }
      candidates.reject! { |entry| same_train_number?(entry[:train_number], train_number) }
      candidates.select! { |entry| within_handoff_window?(arrival_minutes, entry[:departure_minutes]) }

      if preferred.present?
        preferred_match = candidates.find { |entry| same_train_number?(entry[:train_number], preferred) }
        return serialize(preferred_match) if preferred_match
      end

      best = candidates.min_by { |entry| wrap_delta(arrival_minutes, entry[:departure_minutes]) }
      return serialize(best) if best
      return note_only(preferred) if preferred.present?

      nil
    end

    private

    def candidates_from(station_ref)
      tokens = self.class.station_tokens(station_ref)
      tokens.flat_map { |token| starts_by_station[token] }.uniq { |entry| entry[:trip_id] }
    end

    def starts_by_station
      @starts_by_station ||= build_starts_index
    end

    def build_starts_index
      index = Hash.new { |hash, key| hash[key] = [] }
      trips = ScheduleTrip.joins(:transit_route).where(
        service_calendar_id: @calendar_ids,
        transit_routes: { system_id: SYSTEMS }
      ).pluck(
        "schedule_trips.id",
        "schedule_trips.train_number",
        "transit_routes.route_id",
        "schedule_trips.service_calendar_id"
      )
      return index if trips.empty?

      meta_by_id = {}
      trips.each do |id, number, route_id, calendar_id|
        meta_by_id[id] = {
          train_number: number.to_s,
          route_id: route_id,
          calendar_id: calendar_id
        }
      end

      TripStopTime.where(schedule_trip_id: meta_by_id.keys, stop_sequence: 1).pluck(
        :schedule_trip_id,
        :station_ref,
        :departure_time,
        :arrival_time
      ).each do |id, station_ref, departure_time, arrival_time|
        info = meta_by_id[id]
        next unless info

        dep_min = minutes_since_midnight(departure_time || arrival_time)
        next unless dep_min

        entry = info.merge(
          trip_id: id,
          departure_minutes: dep_min,
          station_ref: station_ref
        )
        self.class.station_tokens(station_ref).each { |token| index[token] << entry }
      end

      index
    end

    def preferred_number_from_notes(notes)
      notes.to_s[NOTE_PATTERN, 1].presence
    end

    def same_train_number?(left, right)
      a = normalize_train_number(left)
      b = normalize_train_number(right)
      a.present? && a == b
    end

    def normalize_train_number(value)
      value.to_s.strip.sub(/\A0+/, "").presence || value.to_s.strip.presence
    end

    def within_handoff_window?(arrival_minutes, departure_minutes)
      return false if departure_minutes.nil?

      delta = wrap_delta(arrival_minutes, departure_minutes)
      delta >= 0 && delta <= WINDOW_MINUTES
    end

    def wrap_delta(from_minutes, to_minutes)
      delta = to_minutes.to_f - from_minutes.to_f
      delta += 1440 if delta < -720
      delta
    end

    def serialize(entry)
      {
        train_number: entry[:train_number],
        trip_id: entry[:trip_id],
        route_id: entry[:route_id],
        departure_minutes: entry[:departure_minutes]&.round(2)
      }
    end

    def note_only(train_number)
      {
        train_number: train_number,
        trip_id: nil,
        route_id: nil,
        departure_minutes: nil
      }
    end

    def minutes_since_midnight(time_or_nil)
      return nil unless time_or_nil

      if time_or_nil.is_a?(ActiveSupport::TimeWithZone) && time_or_nil.year != 2000
        t = time_or_nil.in_time_zone(CLOCK_ZONE)
        return t.hour * 60 + t.min + (t.sec / 60.0)
      end

      t = time_or_nil.respond_to?(:utc) ? time_or_nil.utc : time_or_nil
      t.hour * 60 + t.min + (t.sec / 60.0)
    end
  end
end
