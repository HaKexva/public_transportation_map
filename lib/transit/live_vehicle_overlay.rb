# frozen_string_literal: true

module Transit
  # Applies TDX live feeds onto timetable-estimated vehicles when simulation
  # time is near wall-clock "now".
  #
  # - TRA TrainLiveBoard: per-train DelayTime + station status
  # - Metro LiveBoard (TRTC/KRTC/TYMC/KLRT): line/direction median ETA shift
  # - KLRT LivePosition: real lat/lng GPS when available
  class LiveVehicleOverlay
    CLOCK_ZONE = ActiveSupport::TimeZone["Taipei"]
    NEAR_NOW_SECONDS = 120
    CACHE_TTL = 50.seconds
    STALE_TTL = 5.minutes

    # TDX LiveBoard systems that actually publish ETA boards.
    METRO_LIVEBOARD_SYSTEMS = %w[TRTC KRTC TYMC KLRT].freeze

    ROUTE_TO_LIVEBOARD = {
      "wenhu_line" => "TRTC",
      "tamsui_xinyi" => "TRTC",
      "xinbeitou_branch" => "TRTC",
      "bannan" => "TRTC",
      "songshan_xindian" => "TRTC",
      "xiaobitan_branch" => "TRTC",
      "zhonghe_xinlu" => "TRTC",
      "circular" => "TRTC",
      "red_line" => "KRTC",
      "orange_line" => "KRTC",
      "circular_lrt" => "KLRT",
      "airport_mrt" => "TYMC",
      "airport_mrt_express" => "TYMC"
    }.freeze

    def self.apply!(vehicles, at:, route_ids:, client: nil)
      new(at: at, route_ids: route_ids, client: client).apply!(vehicles)
    end

    def initialize(at:, route_ids:, client: nil)
      @at = at.in_time_zone(CLOCK_ZONE)
      @route_ids = Array(route_ids).map(&:to_s).reject(&:blank?).to_set
      @client = client
      @meta = { applied: false, tra: false, metro: false, gps: false }
    end

    attr_reader :meta

    def apply!(vehicles)
      return vehicles if vehicles.blank?
      return vehicles unless near_now?
      return vehicles unless client_configured?

      apply_tra!(vehicles)
      apply_metro_liveboard!(vehicles)
      apply_klrt_gps!(vehicles)

      @meta[:applied] = @meta[:tra] || @meta[:metro] || @meta[:gps]
      vehicles
    rescue TdxClient::Error, StandardError => e
      Rails.logger.warn("[LiveVehicleOverlay] #{e.class}: #{e.message}")
      vehicles
    end

    def near_now?
      (@at - CLOCK_ZONE.now).abs <= NEAR_NOW_SECONDS
    end

    private

    def client_configured?
      (@client || TdxClient).configured?
    end

    def tdx
      @tdx ||= @client || TdxClient.new
    end

    def apply_tra!(vehicles)
      return unless vehicles.any? { |v| v[:system_id].to_s == "tra" }

      live_by_train = tra_live_by_train
      return if live_by_train.empty?

      routes_by_id = TransitRoute.where(route_id: vehicles.filter_map { |v| v[:route_id] if v[:system_id].to_s == "tra" }.uniq).index_by(&:route_id)
      at_minutes = minutes_since_midnight(@at)

      vehicles.each_with_index do |vehicle, index|
        next unless vehicle[:system_id].to_s == "tra"

        live = live_by_train[normalize_train_no(vehicle[:train_number])]
        next unless live

        delay_seconds = live[:delay_minutes].to_i * 60
        effective_minutes = at_minutes - (delay_seconds / 60.0)
        updated = recompute_tra_vehicle(vehicle, routes_by_id[vehicle[:route_id]], effective_minutes, live)
        next unless updated

        updated[:delay_seconds] = delay_seconds
        updated[:delay_source] = "tdx_tra"
        updated[:position_source] = "timetable+live"
        updated[:status] = status_for(delay_seconds, stopped: updated[:status] == "stopped")
        vehicles[index] = updated
        @meta[:tra] = true
      end
    end

    def recompute_tra_vehicle(vehicle, route, effective_minutes, live)
      trip_id = vehicle[:id].to_s.delete_prefix("trip:").to_i
      return nil if trip_id <= 0

      ordered = trip_stops(trip_id)
      return nil if ordered.length < 2

      # Prefer live station dwell when board says approaching / at station.
      if live[:station_status].to_i <= 1 && live[:station_id].present?
        dwell = force_dwell_at_station(ordered, live[:station_id])
        if dwell
          from_ref, to_ref, progress, dep, arr, stopped = dwell
          return attach_coords(route, vehicle.merge(
            from_station_ref: from_ref,
            to_station_ref: to_ref,
            progress: progress.round(4),
            departure_minutes: dep,
            arrival_minutes: arr,
            motion_departure_minutes: dep,
            motion_arrival_minutes: arr,
            status: stopped ? "stopped" : vehicle[:status]
          ))
        end
      end

      segment = place_on_stops(ordered, effective_minutes)
      return nil unless segment

      from_ref, to_ref, progress, dep, arr, stopped = segment
      attach_coords(route, vehicle.merge(
        from_station_ref: from_ref,
        to_station_ref: to_ref,
        progress: progress.round(4),
        departure_minutes: dep,
        arrival_minutes: arr,
        motion_departure_minutes: dep,
        motion_arrival_minutes: arr,
        status: stopped ? "stopped" : "on_time"
      ))
    end

    def force_dwell_at_station(ordered, station_id)
      idx = ordered.index { |stop| station_ref_includes?(stop[:station_ref], station_id) }
      return nil unless idx

      stop = ordered[idx]
      next_stop = ordered[idx + 1] || stop
      [ stop[:station_ref], next_stop[:station_ref], 0.0, stop[:arrival], stop[:departure], true ]
    end

    def place_on_stops(ordered, minutes)
      minutes = modulo_minutes(minutes, 1440)

      ordered.each_with_index do |stop, i|
        if stop[:arrival] <= stop[:departure] && minutes >= stop[:arrival] && minutes < stop[:departure]
          next_stop = ordered[i + 1] || stop
          return [ stop[:station_ref], next_stop[:station_ref], 0.0, stop[:arrival], stop[:departure], true ]
        end

        next_stop = ordered[i + 1]
        next unless next_stop

        a = stop[:departure]
        b = next_stop[:arrival]
        next unless within_segment?(minutes, a, b)

        return [ stop[:station_ref], next_stop[:station_ref], segment_progress(minutes, a, b), a, b, false ]
      end

      nil
    end

    def trip_stops(trip_id)
      @trip_stops_cache ||= {}
      return @trip_stops_cache[trip_id] if @trip_stops_cache.key?(trip_id)

      rows = TripStopTime.where(schedule_trip_id: trip_id).order(:stop_sequence).pluck(
        :stop_sequence, :station_ref, :arrival_time, :departure_time
      )
      @trip_stops_cache[trip_id] = rows.map do |_seq, station_ref, arrival_time, departure_time|
        {
          station_ref: station_ref,
          arrival: minutes_since_midnight(arrival_time || departure_time),
          departure: minutes_since_midnight(departure_time || arrival_time)
        }
      end
    end

    def apply_metro_liveboard!(vehicles)
      systems = liveboard_systems_for(vehicles)
      return if systems.empty?

      boards_by_system = systems.to_h { |sys| [ sys, metro_liveboard(sys) ] }
      shifts = metro_shifts(vehicles, boards_by_system)
      return if shifts.empty?

      routes_by_id = TransitRoute.where(route_id: shifts.keys.map { |route_id, _dir| route_id }.uniq).index_by(&:route_id)
      at_minutes = minutes_since_midnight(@at)

      vehicles.each_with_index do |vehicle, index|
        key = [ vehicle[:route_id].to_s, vehicle[:direction].to_s ]
        shift_seconds = shifts[key]
        next unless shift_seconds

        updated = apply_time_shift(vehicle, routes_by_id[vehicle[:route_id]], at_minutes, shift_seconds)
        next unless updated

        updated[:delay_seconds] = shift_seconds.round
        updated[:delay_source] = "tdx_metro_liveboard"
        updated[:position_source] =
          vehicle[:position_source].to_s.include?("headway") ? "headway_estimate+live" : "station_timetable+live"
        updated[:status] = status_for(shift_seconds, stopped: updated[:status] == "stopped")
        vehicles[index] = updated
        @meta[:metro] = true
      end
    end

    def liveboard_systems_for(vehicles)
      systems = vehicles.filter_map { |v| ROUTE_TO_LIVEBOARD[v[:route_id].to_s] }.uniq
      systems & METRO_LIVEBOARD_SYSTEMS
    end

    def metro_shifts(vehicles, boards_by_system)
      samples = Hash.new { |h, k| h[k] = [] }
      at_minutes = minutes_since_midnight(@at)

      boards_by_system.each do |system, boards|
        boards.each do |board|
          estimate = board["EstimateTime"]
          next if estimate.nil?

          route_id = MetroSystemRegistry.route_id_for(tdx_rail_system: system, line_id: board["LineID"])
          next unless route_id && @route_ids.include?(route_id)

          station_id = board["StationID"].to_s
          dest_name = ResponseDecoder.localized_name(board["DestinationStationName"]).to_s
          candidates = vehicles.select do |v|
            v[:route_id].to_s == route_id &&
              station_ref_includes?(v[:to_station_ref], station_id) &&
              destination_matches?(v[:destination_name], dest_name)
          end
          next if candidates.empty?

          candidates.each do |vehicle|
            arrival = vehicle[:motion_arrival_minutes] || vehicle[:arrival_minutes]
            next unless arrival

            scheduled_eta = arrival - at_minutes
            scheduled_eta += 1440 if scheduled_eta < -12 * 60
            # Positive sample => train is later than timetable.
            samples[[ route_id, vehicle[:direction].to_s ]] << ((estimate.to_f - scheduled_eta) * 60.0)
          end
        end
      end

      samples.transform_values { |list| median(list) }.reject { |_, v| v.nil? || v.abs < 15 }
    end

    def apply_time_shift(vehicle, route, at_minutes, shift_seconds)
      dep = vehicle[:motion_departure_minutes] || vehicle[:departure_minutes]
      arr = vehicle[:motion_arrival_minutes] || vehicle[:arrival_minutes]
      return nil unless dep && arr

      effective = at_minutes - (shift_seconds / 60.0)
      stopped = false
      progress =
        if within_segment?(effective, dep, arr)
          segment_progress(effective, dep, arr)
        elsif before_segment?(effective, dep, arr)
          0.0
        else
          # Past arrival — treat as brief dwell at to-station.
          stopped = true
          1.0
        end

      attach_coords(route, vehicle.merge(
        progress: progress.round(4),
        status: stopped ? "stopped" : vehicle[:status]
      ))
    end

    def apply_klrt_gps!(vehicles)
      return unless vehicles.any? { |v| v[:route_id].to_s == "circular_lrt" }

      positions = klrt_live_positions
      return if positions.empty?

      unused = positions.dup
      vehicles.each_with_index do |vehicle, index|
        next unless vehicle[:route_id].to_s == "circular_lrt"

        match = take_gps_match(unused, vehicle)
        next unless match

        lat, lng = match
        vehicles[index] = vehicle.merge(
          lat: lat,
          lng: lng,
          position_source: "tdx_gps",
          delay_source: vehicle[:delay_source].to_s.start_with?("tdx") ? vehicle[:delay_source] : "tdx_gps"
        )
        @meta[:gps] = true
      end
    end

    def take_gps_match(unused, vehicle)
      return nil if unused.empty?

      train = normalize_train_no(vehicle[:train_number])
      by_trip = unused.find_index { |row| normalize_train_no(row[:trip_id]) == train && train.present? }
      if by_trip
        row = unused.delete_at(by_trip)
        return [ row[:lat], row[:lng] ]
      end

      # Fall back to nearest GPS fix to the timetable estimate.
      return nil unless vehicle[:lat] && vehicle[:lng]

      best_idx = nil
      best_dist = Float::INFINITY
      unused.each_with_index do |row, idx|
        d = (row[:lat] - vehicle[:lat])**2 + (row[:lng] - vehicle[:lng])**2
        if d < best_dist
          best_dist = d
          best_idx = idx
        end
      end
      return nil if best_idx.nil? || best_dist > 0.01 # ~1km^2 rough gate

      row = unused.delete_at(best_idx)
      [ row[:lat], row[:lng] ]
    end

    def tra_live_by_train
      records = cached_fetch("tra/train_live_board/v1") do
        tdx.fetch_all("v3/Rail/TRA/TrainLiveBoard")
      end

      map = {}
      records.each do |row|
        train_no = normalize_train_no(row["TrainNo"])
        next if train_no.blank?

        map[train_no] = {
          delay_minutes: row["DelayTime"].to_i,
          station_id: row["StationID"].to_s,
          station_status: row["TrainStationStatus"]
        }
      end
      map
    end

    def metro_liveboard(system)
      cached_fetch("metro/liveboard/#{system}/v1") do
        tdx.fetch_all("v2/Rail/Metro/LiveBoard/#{system}")
      end
    end

    def klrt_live_positions
      records = cached_fetch("metro/live_position/KLRT/v1") do
        tdx.fetch_all("v2/Rail/Metro/LivePosition/KLRT")
      end

      records.filter_map do |row|
        point = row["TrainPosition"] || {}
        lat = point["PositionLat"] || point["lat"]
        lng = point["PositionLon"] || point["lon"]
        next unless lat && lng

        {
          trip_id: row["TripID"].to_s,
          lat: lat.to_f,
          lng: lng.to_f,
          direction: row["Direction"]
        }
      end
    end

    def cached_fetch(key)
      cache_key = "tdx_live/#{key}"
      stale_key = "#{cache_key}/stale"

      fresh = Rails.cache.read(cache_key)
      return fresh if fresh

      begin
        value = Array(yield)
        Rails.cache.write(cache_key, value, expires_in: CACHE_TTL)
        Rails.cache.write(stale_key, value, expires_in: STALE_TTL)
        value
      rescue TdxClient::Error, StandardError => e
        Rails.logger.warn("[LiveVehicleOverlay] fetch #{key} failed: #{e.message}")
        Rails.cache.read(stale_key) || []
      end
    end

    def attach_coords(route, vehicle)
      return vehicle unless route

      vehicle[:from_station_name] = GeojsonStationCoords.lookup_name(route, vehicle[:from_station_ref])
      vehicle[:to_station_name] = GeojsonStationCoords.lookup_name(route, vehicle[:to_station_ref])

      coords = GeojsonStationCoords.interpolate(
        route,
        vehicle[:from_station_ref],
        vehicle[:to_station_ref],
        vehicle[:progress]
      )
      coords ? vehicle.merge(coords) : vehicle
    end

    def status_for(delay_seconds, stopped:)
      return "stopped" if stopped
      return "on_time" if delay_seconds.abs < 120

      delay_seconds.positive? ? "delayed" : "early"
    end

    def normalize_train_no(value)
      value.to_s.strip.sub(/\A0+/, "").presence || value.to_s.strip
    end

    def station_ref_includes?(station_ref, station_id)
      return false if station_id.blank?

      station_ref.to_s.split(";").map(&:strip).any? { |part| part == station_id.to_s || part.end_with?(station_id.to_s) }
    end

    def destination_matches?(vehicle_dest, board_dest)
      return true if board_dest.blank? || vehicle_dest.blank?

      a = vehicle_dest.to_s
      b = board_dest.to_s
      a.include?(b) || b.include?(a)
    end

    def median(values)
      return nil if values.blank?

      sorted = values.map(&:to_f).sort
      mid = sorted.length / 2
      if sorted.length.odd?
        sorted[mid]
      else
        (sorted[mid - 1] + sorted[mid]) / 2.0
      end
    end

    def minutes_since_midnight(time_or_nil)
      return 0 unless time_or_nil

      if time_or_nil.is_a?(ActiveSupport::TimeWithZone) && time_or_nil.year != 2000
        t = time_or_nil.in_time_zone(CLOCK_ZONE)
        return t.hour * 60 + t.min + (t.sec / 60.0)
      end

      t = time_or_nil.respond_to?(:utc) ? time_or_nil.utc : time_or_nil
      t.hour * 60 + t.min + (t.sec / 60.0)
    end

    def modulo_minutes(value, mod)
      ((value % mod) + mod) % mod
    end

    def within_segment?(minutes, a, b)
      if a <= b
        minutes >= a && minutes <= b
      else
        minutes >= a || minutes <= b
      end
    end

    def before_segment?(minutes, a, b)
      if a <= b
        minutes < a
      else
        minutes < a && minutes > b
      end
    end

    def segment_progress(minutes, a, b)
      return 0.0 if a == b

      if a <= b
        ((minutes - a).to_f / (b - a)).clamp(0.0, 1.0)
      else
        span = (1440 - a) + b
        offset = minutes >= a ? (minutes - a) : (1440 - a + minutes)
        (offset.to_f / span).clamp(0.0, 1.0)
      end
    end
  end
end
