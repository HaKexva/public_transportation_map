# frozen_string_literal: true

module Geojson
  # Decodes Google Maps Plus Codes (Open Location Code) offline. Short codes
  # (「3H5R+4C 南港區」) need a reference point within ~50 km to recover the
  # dropped prefix.
  module PlusCode
    ALPHABET = "23456789CFGHJMPQRVWX"
    SEPARATOR_POSITION = 8
    PAIR_UNITS = [ 160_000, 8_000, 400, 20, 1 ].freeze
    UNITS_PER_DEGREE = 8_000
    GRID_ROWS = 5
    GRID_COLUMNS = 4
    PATTERN = /\A([#{ALPHABET}]{2,8})(0*)\+([#{ALPHABET}]*)\z/i

    module_function

    # Accepts the text Google Maps copies, e.g. 「7QQ32GJQ+QW」 or 「GJQ+QW 台北市」.
    def extract(text)
      code = text.to_s.strip.split(/\s+/).first.to_s.upcase
      code.match?(PATTERN) ? code : nil
    end

    def code?(text) = !extract(text).nil?

    def full?(code) = code.index("+") == SEPARATOR_POSITION && !code.include?("0")

    # Returns [lon, lat] of the code's centre, or nil when a short code has no reference.
    def decode(text, reference: nil)
      code = extract(text) or return nil
      return center(code) if full?(code)
      return nil if reference.nil?

      recover(code, *reference)
    end

    def center(code)
      digits = code.delete("+").delete("0")
      lat = lon = 0r
      lat_size = lon_size = nil
      digits.chars.first(10).each_slice(2).with_index do |(lat_digit, lon_digit), index|
        lat_size = lon_size = PAIR_UNITS[index].to_r / UNITS_PER_DEGREE
        lat += ALPHABET.index(lat_digit) * lat_size
        lon += ALPHABET.index(lon_digit) * lon_size if lon_digit
      end
      digits.chars.drop(10).each do |digit|
        lat_size /= GRID_ROWS
        lon_size /= GRID_COLUMNS
        value = ALPHABET.index(digit)
        lat += (value / GRID_COLUMNS) * lat_size
        lon += (value % GRID_COLUMNS) * lon_size
      end
      [ (lon - 180 + lon_size / 2).to_f.round(6), (lat - 90 + lat_size / 2).to_f.round(6) ]
    end

    def recover(code, ref_lon, ref_lat)
      padding = SEPARATOR_POSITION - code.index("+")
      resolution = 20.0**(2 - padding / 2)
      lon, lat = center(encode(ref_lon, ref_lat)[0, padding] + code)
      lat += resolution if ref_lat - resolution / 2 > lat
      lat -= resolution if ref_lat + resolution / 2 < lat
      lon += resolution if ref_lon - resolution / 2 > lon
      lon -= resolution if ref_lon + resolution / 2 < lon
      [ lon.round(6), lat.round(6) ]
    end

    def encode(lon, lat)
      lat_units = ((lat + 90) * UNITS_PER_DEGREE).floor
      lon_units = ((lon + 180) * UNITS_PER_DEGREE).floor
      code = PAIR_UNITS.map do |unit|
        lat_digit, lat_units = lat_units.divmod(unit)
        lon_digit, lon_units = lon_units.divmod(unit)
        ALPHABET[lat_digit] + ALPHABET[lon_digit]
      end.join
      "#{code[0, SEPARATOR_POSITION]}+#{code[SEPARATOR_POSITION..]}"
    end
  end
end
