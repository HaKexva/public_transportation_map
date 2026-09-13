# frozen_string_literal: true

module Geojson
  module BusCorridor
    SNAP_METERS = 50.0

    module_function

    def unsnapped_segments(line, corridors)
      return [] if line.blank? || line.length < 2

      flags = line.map { |point| nearest_distance_meters(point, corridors) > SNAP_METERS }
      segments = []
      current = []

      flags.each_with_index do |unsnapped, index|
        if unsnapped
          current << line[index]
        else
          segments << current if current.length >= 2
          current = []
        end
      end
      segments << current if current.length >= 2
      segments
    end

    def nearest_distance_meters(point, corridors)
      Array(corridors).filter_map { |corridor| distance_to_polyline_meters(point, corridor) }.min || Float::INFINITY
    end

    def distance_to_polyline_meters(point, line)
      return meters_between(point, line.first) if line.length < 2

      (0...(line.length - 1)).map { |index| distance_to_segment_meters(point, line[index], line[index + 1]) }.min
    end

    def distance_to_segment_meters(point, start, finish)
      dx = finish[0] - start[0]
      dy = finish[1] - start[1]
      length_squared = (dx * dx) + (dy * dy)
      progress = 0.0
      if length_squared.positive?
        progress = (((point[0] - start[0]) * dx) + ((point[1] - start[1]) * dy)) / length_squared
        progress = progress.clamp(0.0, 1.0)
      end

      projected = [ start[0] + (dx * progress), start[1] + (dy * progress) ]
      meters_between(point, projected)
    end

    def meters_between(left, right)
      dlon = (right[0] - left[0]) * 111_320 * Math.cos(left[1] * Math::PI / 180.0)
      dlat = (right[1] - left[1]) * 110_540
      Math.hypot(dlon, dlat)
    end
  end
end
