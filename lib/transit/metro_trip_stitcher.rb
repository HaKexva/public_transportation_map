# frozen_string_literal: true

module Transit
  # Rebuilds multi-stop metro trips from per-station TDX StationTimeTable boards.
  class MetroTripStitcher
    MIN_RUN_MINUTES = 0.5
    MAX_RUN_MINUTES = 18

    StitchedTrip = Data.define(:train_number, :destination_name, :trip_type, :stops)

    def stitch(boards)
      numbered, unnumbered = Array(boards).partition { |board| board[:train_number].present? }
      stitch_by_train_number(numbered) + stitch_by_time_window(unnumbered)
    end

    private

    def stitch_by_train_number(boards)
      boards.group_by { |board| [ board[:route_id], board[:direction], board[:calendar_code], board[:train_number] ] }
        .filter_map do |(_route_id, _direction, _calendar_code, train_number), group|
          stops = unique_stops(group)
          next if stops.length < 2

          sample = group.first
          StitchedTrip.new(
            train_number: train_number,
            destination_name: sample[:destination_name],
            trip_type: sample[:trip_type],
            stops: stops
          )
        end
    end

    def stitch_by_time_window(boards)
      boards.group_by { |board| [ board[:route_id], board[:direction], board[:calendar_code], board[:destination_name] ] }
        .flat_map { |_key, group| chain_unused_departures(group) }
    end

    def chain_unused_departures(group)
      unused = group.sort_by { |board| board[:sequence].to_i }.map { |board| board.merge(used: false) }
      trips = []

      unused.each_with_index do |origin, index|
        next if origin[:used]

        chain = [ origin ]
        origin[:used] = true
        last = origin

        unused[(index + 1)..].each do |candidate|
          next if candidate[:used]
          next unless candidate[:sequence].to_i > last[:sequence].to_i

          gap = minute_gap(last[:departure_minutes], candidate[:departure_minutes])
          next unless gap.between?(MIN_RUN_MINUTES, MAX_RUN_MINUTES)

          chain << candidate
          candidate[:used] = true
          last = candidate
        end

        next if chain.length < 2

        sample = chain.first
        trips << StitchedTrip.new(
          train_number: "#{sample[:station_ref]}-#{sample[:destination_name]}-#{format_minutes(sample[:departure_minutes])}",
          destination_name: sample[:destination_name],
          trip_type: sample[:trip_type],
          stops: unique_stops(chain)
        )
      end

      trips
    end

    def unique_stops(boards)
      boards.sort_by { |board| [ board[:sequence].to_i, board[:departure_minutes].to_f ] }
        .uniq { |board| board[:station_ref] }
        .map do |board|
          {
            station_ref: board[:station_ref],
            arrival_time: board[:arrival_time] || board[:departure_time],
            departure_time: board[:departure_time] || board[:arrival_time]
          }
        end
    end

    def minute_gap(from_minutes, to_minutes)
      delta = to_minutes.to_f - from_minutes.to_f
      delta += 1440 if delta < -720
      delta
    end

    def format_minutes(minutes)
      total = minutes.to_i % 1440
      format("%02d:%02d", total / 60, total % 60)
    end
  end
end
