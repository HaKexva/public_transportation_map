# frozen_string_literal: true

require "stringio"
require "shellwords"

module Geojson
  # Minimal ESRI shapefile reader for polyline layers (enough for NLSC railway centerlines).
  module NlscShapefileReader
    module_function

  def line_strings_from_zip(zip_path)
    shp_name = list_zip(zip_path).find { |entry| entry.downcase.end_with?(".shp") }
    raise "No .shp in #{zip_path}" unless shp_name

    binary = extract_zip_entry(zip_path, shp_name)
    parse_line_strings(binary)
  end

  def list_zip(zip_path)
    output = `unzip -Z1 #{Shellwords.escape(zip_path.to_s)} 2>/dev/null`
    output.lines.map(&:strip).reject(&:empty?)
  end

  def extract_zip_entry(zip_path, entry_name)
    `unzip -p #{Shellwords.escape(zip_path.to_s)} #{Shellwords.escape(entry_name)} 2>/dev/null`
  end

  def parse_line_strings(binary)
    io = StringIO.new(binary)
    io.seek(24)
    file_length = io.read(4).unpack1("N") * 2
    io.seek(32)
    shape_type = io.read(4).unpack1("V")
    raise "Unsupported shape type #{shape_type}" unless [ 3, 5, 13, 15, 23, 25 ].include?(shape_type)

    lines = []
    io.seek(100)

    while io.pos + 8 <= file_length
      _record_number = io.read(4).unpack1("N")
      content_length = io.read(4).unpack1("N") * 2
      record_start = io.pos
      record_type = io.read(4).unpack1("V")
      break unless [ 3, 5, 13, 15, 23, 25 ].include?(record_type)

      io.read(32) # bbox
      num_parts = io.read(4).unpack1("V")
      num_points = io.read(4).unpack1("V")
      parts = num_parts.times.map { io.read(4).unpack1("V") }
      points = num_points.times.map do
        x, y = io.read(16).unpack("E2")
        Twd97.project_to_wgs84(x, y)
      end

      parts.each_with_index do |start_index, part_index|
        end_index = parts[part_index + 1] || num_points
        segment = points[start_index...end_index]
        lines << segment if segment.length >= 2
      end

      io.seek(record_start + content_length)
    end

    lines
  end
  end
end
