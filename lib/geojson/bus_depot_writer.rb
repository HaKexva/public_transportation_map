# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Geojson
  # Aggregates bus dispatch yards / operator terminals into a catalog.
  # Rail/metro 「機廠」 markers live in metro_depots.json — never here.
  # Routes without a depot-named stop take theirs from MANUAL_PATH, a hand-filled
  # Markdown route table whose 場站代碼 column points into the depot list kept in
  # STATIONS_BASENAME (auto-detected + hand-added). write_missing! regenerates both.
  class BusDepotWriter
    OUTPUT_PATH = Rails.root.join("public/geojson/bus_depots.json")
    MANUAL_PATH = Rails.root.join("lib/geojson/bus_depots_manual.md")
    STATIONS_PATH = Rails.root.join("lib/geojson/bus_depots_stations.md")
    DEPOT_COLUMNS = {
      "code" => "代碼",
      "name" => "場站名稱",
      "lon" => "經度",
      "lat" => "緯度",
      "note" => "備註"
    }.freeze
    ROUTE_COLUMNS = {
      "route_name" => "路線",
      "operator" => "業者",
      "departure" => "起點",
      "destination" => "終點",
      "depot_code" => "場站代碼",
      "route_id" => "路線代碼"
    }.freeze
    CITY_LABELS = {
      "taipei_new_taipei_bus" => "台北新北",
      "keelung_bus" => "基隆市",
      "taoyuan_bus" => "桃園市",
      "hsinchu_city_bus" => "新竹市",
      "hsinchu_county_bus" => "新竹縣",
      "miaoli_bus" => "苗栗縣",
      "taichung_bus" => "台中市",
      "changhua_bus" => "彰化縣",
      "nantou_bus" => "南投縣",
      "yunlin_bus" => "雲林縣",
      "chiayi_city_bus" => "嘉義市",
      "chiayi_county_bus" => "嘉義縣",
      "tainan_bus" => "台南市",
      "kaohsiung_bus" => "高雄市",
      "pingtung_bus" => "屏東縣",
      "yilan_bus" => "宜蘭縣",
      "hualian_bus" => "花蓮縣",
      "taitung_bus" => "台東縣",
      "kinmen_bus" => "金門縣",
      "intercity_bus" => "公路客運"
    }.freeze
    CONFIRMED_BASENAME = "bus_depots_confirmed.md"
    STATIONS_BASENAME = "bus_depots_stations.md"
    MANUAL_INTRO = <<~MARKDOWN
      # 公車場站手填表

      TDX 沒有「路線所屬場站」資料；下列路線的場站請人工指定。
      在「場站代碼」欄填 `#{STATIONS_BASENAME}` 場站清單裡的代碼（任何縣市的代碼都可以用）。
      手動指定會取代自動偵測結果，所以已有自動場站的路線也可以加一列改指定。
      聯營路線可填多個代碼，用逗號分隔（例：`N3, N34`）。填 `#` 代表暫緩：保留在表上、不指定場站。

      「路線代碼」欄與各縣市標題結尾的反引號代碼勿改。`bin/rails geojson:bus_depots_missing` 重產本檔時會保留已填內容。
      確認無誤後跑 `bin/rails geojson:bus_depots_confirm`，已指定的路線會移到 `#{CONFIRMED_BASENAME}` 並從本檔刪除。
    MARKDOWN
    CONFIRMED_INTRO = <<~MARKDOWN
      # 公車場站（已確認）

      由 `bin/rails geojson:bus_depots_confirm` 從 `bus_depots_manual.md` 移入的已確認路線指定，
      重建 `public/geojson/bus_depots.json` 時會與手填表合併；同一路線以本檔為準。
      格式同手填表，可直接修改；場站資料在 `#{STATIONS_BASENAME}`。
    MARKDOWN
    STATIONS_INTRO = <<~MARKDOWN
      # 公車場站清單

      `bus_depots_manual.md` 與 `#{CONFIRMED_BASENAME}` 的「場站代碼」都指向本檔。

      - `S`／`A` 開頭是從站牌自動偵測到的場站，可點「地圖」確認位置；`bin/rails geojson:bus_depots_missing` 會重新整理這些列。
      - 各縣市依客運分表（依場站名稱開頭的客運名；沒有客運名的放「其他」），手動代碼在前、自動偵測在後。
      - 清單裡沒有的場站，請在該縣市任一表格最後自己加一列：代碼自訂（例：`N1`，全檔不可重複，不可用 `S`／`A` 開頭），
        填場站名稱與經緯度（WGS84，例：`121.5170`、`25.0478`；Google 地圖複製的順序是「緯度, 經度」，請分開填），備註可留空。
        重新整理時會自動歸到對應客運的表。
      - 經緯度也可以直接貼 Google 地圖的 Plus Code（貼在「經度」欄，例：`7QQ32GX8+4R` 或 `2GX8+4R 台北市`），
        跑 `bin/rails geojson:bus_depots_stations` 會換成經緯度，原代碼留在備註。短代碼依後面的縣市名、備註地址或同縣市其他場站推算。
      - 經緯度可留空、備註填地址：路線指定照樣生效，只是地圖上要等有座標才會畫出。
        之後可跑 `bin/rails geojson:bus_depots_geocode` 依地址自動補座標（需 Google Geocoding API）。
    MARKDOWN
    OPERATOR_PREFIX = /\A(.+?(?:客運|巴士|汽車))(?=.)/
    OTHER_OPERATOR = "其他"
    CITY_OPERATORS = { "keelung_bus" => "基隆市公車" }.freeze
    # Plus Code short-code references ([lon, lat]); each county's yards sit within
    # the ±0.5° a 4-character short code can recover.
    COUNTY_CENTERS = {
      "台北市" => [ 121.5654, 25.0600 ], "新北市" => [ 121.4628, 25.0120 ], "基隆市" => [ 121.7419, 25.1276 ],
      "桃園市" => [ 121.3010, 24.9937 ], "新竹市" => [ 120.9686, 24.8039 ], "新竹縣" => [ 121.0177, 24.8387 ],
      "苗栗縣" => [ 120.8214, 24.5602 ], "台中市" => [ 120.6736, 24.1477 ], "彰化縣" => [ 120.5161, 24.0518 ],
      "南投縣" => [ 120.6836, 23.9609 ], "雲林縣" => [ 120.4313, 23.7092 ], "嘉義市" => [ 120.4491, 23.4801 ],
      "嘉義縣" => [ 120.4500, 23.4518 ], "台南市" => [ 120.2270, 22.9999 ], "高雄市" => [ 120.3014, 22.6273 ],
      "屏東縣" => [ 120.4879, 22.5519 ], "宜蘭縣" => [ 121.7539, 24.7021 ], "花蓮縣" => [ 121.6014, 23.9872 ],
      "台東縣" => [ 121.1438, 22.7583 ], "澎湖縣" => [ 119.5793, 23.5711 ], "金門縣" => [ 118.3171, 24.4321 ],
      "連江縣" => [ 119.9517, 26.1505 ]
    }.freeze
    # ~1.1 km grid: opposite-direction poles and nearby yard gates merge.
    COORD_DECIMALS = 2
    NUMBER = /\A-?\d+(\.\d+)?\z/
    DEFERRED_CODE = "#"

    Result = Data.define(:depots, :auto_depots)
    Manual = Data.define(:depots, :routes)
    ConfirmResult = Data.define(:routes)

    def self.write!(path: OUTPUT_PATH, bus_root: nil, manual_path: MANUAL_PATH, confirmed_path: nil, stations_path: nil)
      new(path:, bus_root:, manual_path:, confirmed_path:, stations_path:).write!
    end

    def self.write_missing!(path: OUTPUT_PATH, bus_root: nil, manual_path: MANUAL_PATH, confirmed_path: nil, stations_path: nil)
      new(path:, bus_root:, manual_path:, confirmed_path:, stations_path:).write_missing!
    end

    def self.refresh_stations!(manual_path: MANUAL_PATH, confirmed_path: nil, stations_path: nil)
      new(path: OUTPUT_PATH, manual_path:, confirmed_path:, stations_path:).refresh_stations!
    end

    def self.confirm!(manual_path: MANUAL_PATH, confirmed_path: nil, stations_path: nil)
      new(path: OUTPUT_PATH, manual_path:, confirmed_path:, stations_path:).confirm!
    end

    def self.depot_code(depot_id)
      match = depot_id.to_s.match(/\Abus_depot_sid_(\w+)\z/)
      match ? "S#{match[1]}" : "A#{Digest::SHA1.hexdigest(depot_id.to_s)[0, 6].upcase}"
    end

    def self.auto_code?(code)
      code.to_s.match?(/\A[SA]/)
    end

    def self.depot_row_valid?(row)
      row["code"].present? && row["name"].present?
    end

    def self.depot_row_located?(row)
      row["lon"].to_s.match?(NUMBER) && row["lat"].to_s.match?(NUMBER)
    end

    def self.route_row_filled?(row)
      row["route_id"].present? && row["depot_code"].present? && !route_row_deferred?(row)
    end

    def self.route_row_deferred?(row)
      row["depot_code"].to_s.strip == DEFERRED_CODE
    end

    # Jointly operated routes list several depots: 「N3, N34」 / 「N3、N34」.
    def self.depot_codes(row)
      row["depot_code"].to_s.split(/[,，、\s]+/).reject(&:blank?)
    end

    # One row per (depot, city it serves) so each city's list shows its own yards.
    def self.auto_depot_rows(depots, route_city)
      depots.flat_map do |depot|
        note = "自動偵測・#{depot['routes'].length} 條路線・[地圖](https://www.google.com/maps?q=#{depot['lat']},#{depot['lon']})"
        depot["routes"].filter_map { |route_id| route_city[route_id] }.uniq.map do |city|
          {
            "city" => city,
            "code" => depot_code(depot["id"]),
            "name" => depot["name"],
            "lon" => depot["lon"].to_s,
            "lat" => depot["lat"].to_s,
            "note" => note
          }
        end
      end
    end

    # Pass depot_rows for the stations file, route_rows for the route tables
    # (manual / confirmed); a table is only written when its rows are given.
    def self.manual_markdown(depot_rows: [], route_rows: [], intro: MANUAL_INTRO)
      city_order = CITY_LABELS.keys
      cities = (depot_rows + route_rows).map { |row| row["city"].to_s }.uniq
        .sort_by { |city| [ city_order.index(city) || city_order.length, city ] }
      depots_by_city = depot_rows.group_by { |row| row["city"].to_s }
      routes_by_city = route_rows.group_by { |row| row["city"].to_s }

      lines = [ intro ]
      cities.each do |city|
        depots = depots_by_city.fetch(city, [])
        routes = routes_by_city.fetch(city, [])
        assigned = routes.count { |row| route_row_filled?(row) }
        deferred = routes.count { |row| route_row_deferred?(row) }
        counts = [
          ("#{depots.length} 個場站" if depot_rows.any?),
          ("#{routes.length} 條路線，已指定 #{assigned}#{"，暫緩 #{deferred}" if deferred.positive?}" if route_rows.any?)
        ].compact.join("，")
        lines << "## #{CITY_LABELS.fetch(city, city)} `#{city}`（#{counts}）"
        lines << ""
        depots_by_operator(depots).each do |operator, rows|
          lines << "### #{operator}（#{rows.length} 個）"
          lines << ""
          lines.concat(markdown_table(DEPOT_COLUMNS, rows))
          lines << ""
        end
        next unless route_rows.any?

        lines << "### 路線"
        lines << ""
        lines.concat(markdown_table(ROUTE_COLUMNS, routes.reject { |row| route_row_deferred?(row) }))
        lines << ""
        if deferred.positive?
          lines << "<details><summary>暫緩（#{deferred} 條）</summary>"
          lines << ""
          lines.concat(markdown_table(ROUTE_COLUMNS, routes.select { |row| route_row_deferred?(row) }))
          lines << ""
          lines << "</details>"
          lines << ""
        end
      end
      lines.join("\n")
    end

    # 「三重客運蘆洲一站」→ 三重客運. Bare terminal names (「建國客運站」「板橋客運站」)
    # are places, not operators.
    def self.depot_operator(name)
      match = name.to_s.match(OPERATOR_PREFIX)
      match && match.post_match != "站" ? match[1].tr("台", "臺") : nil
    end

    # Operators in name order with hand-added codes (N1, N2 …) before auto-detected
    # ones; depots without an operator prefix go last under 其他.
    def self.depots_by_operator(rows)
      rows.group_by { |row| depot_operator(row["name"]) || CITY_OPERATORS.fetch(row["city"].to_s, OTHER_OPERATOR) }
        .sort_by { |operator, _| [ operator == OTHER_OPERATOR ? 1 : 0, operator ] }
        .map do |operator, group|
          [ operator, group.sort_by { |row| [ auto_code?(row["code"]) ? 1 : 0, row["code"].to_s[/\d+/].to_i, row["code"].to_s ] } ]
        end
    end

    # Rows whose 經度 or 緯度 cell holds a Google Maps Plus Code get real
    # coordinates; the code is kept in 備註. Short codes are recovered near the
    # county named after the code or in 備註, else near the block's reference
    # point (reference_for.call(city) → [lon, lat] or nil).
    def self.resolve_plus_codes(rows, &reference_for)
      rows.map do |row|
        cell = [ row["lon"], row["lat"] ].find { |value| Geojson::PlusCode.code?(value) }
        next row if cell.nil?

        code = Geojson::PlusCode.extract(cell)
        reference = county_center(cell.to_s.sub(/\A\S+/, "")) || county_center(row["note"]) || reference_for&.call(row["city"])
        lon, lat = Geojson::PlusCode.decode(code, reference:)
        if lon.nil?
          warn "Plus Code #{code} for #{row['code']} needs a full code or a county name after it"
          next row
        end

        note = [ row["note"].presence, "Plus Code #{code}" ].compact.join("・")
        row.merge("lon" => lon.to_s, "lat" => lat.to_s, "note" => note)
      end
    end

    def self.county_center(text)
      normalized = text.to_s.tr("臺", "台")
      COUNTY_CENTERS.find { |county, _| normalized.include?(county) }&.last
    end

    def self.markdown_table(columns, rows)
      header = [ "| #{columns.values.join(' | ')} |", "|#{' --- |' * columns.length}" ]
      header + rows.map do |row|
        cells = columns.keys.map { |key| row[key].to_s.gsub(/\s+/, " ").strip.gsub("|", "\\|") }
        "| #{cells.join(' | ')} |"
      end
    end

    def self.parse_manual(path)
      return Manual.new(depots: [], routes: []) unless File.exist?(path)

      city = nil
      columns = nil
      depots = []
      routes = []
      File.foreach(path) do |line|
        if (heading = line.match(/\A##\s.*?`([^`]+)`/))
          city = heading[1]
          columns = nil
          next
        end
        next unless line.lstrip.start_with?("|")

        cells = line.strip.delete_prefix("|").delete_suffix("|")
          .split(/(?<!\\)\|/).map { |cell| cell.strip.gsub("\\|", "|") }
        if (header = [ DEPOT_COLUMNS, ROUTE_COLUMNS ].find { |set| set.values == cells })
          columns = header
          next
        end
        next if columns.nil? || cells.all? { |cell| cell.match?(/\A:?-+:?\z/) } || cells.all?(&:blank?)

        row = columns.keys.zip(cells.values_at(0...columns.length).map(&:to_s)).to_h.merge("city" => city)
        (columns.equal?(DEPOT_COLUMNS) ? depots : routes) << row
      end
      Manual.new(depots: depots, routes: routes)
    end

    def initialize(path:, bus_root: nil, manual_path: MANUAL_PATH, confirmed_path: nil, stations_path: nil)
      @path = path
      @bus_root = bus_root || Geojson::BusLayout.bus_root
      @manual_path = manual_path
      @confirmed_path = confirmed_path || Pathname(manual_path).dirname.join(CONFIRMED_BASENAME)
      @stations_path = stations_path || Pathname(manual_path).dirname.join(STATIONS_BASENAME)
    end

    # Moves every assigned route row (not `#`) whose depot codes all exist from
    # the working table into the confirmed file. Does not rebuild the JSON.
    def confirm!
      working = self.class.parse_manual(@manual_path)
      confirmed = self.class.parse_manual(@confirmed_path)
      depots = depot_catalog(working, confirmed)
      known_codes = depots.map { |row| row["code"] }.to_set

      moving = working.routes.select do |row|
        self.class.route_row_filled?(row) &&
          self.class.depot_codes(row).all? { |code| self.class.auto_code?(code) || known_codes.include?(code) }
      end
      moving_ids = moving.map { |row| row["route_id"] }.to_set

      write_stations(depots)
      confirmed_routes = confirmed.routes.reject { |row| moving_ids.include?(row["route_id"]) } + moving
      File.write(@confirmed_path, self.class.manual_markdown(
        route_rows: confirmed_routes.sort_by { |row| [ row["operator"].to_s, row["route_name"].to_s, row["route_id"].to_s ] },
        intro: CONFIRMED_INTRO
      ))
      File.write(@manual_path, self.class.manual_markdown(route_rows: working.routes.reject { |row| moving_ids.include?(row["route_id"]) }))
      ConfirmResult.new(routes: moving.length)
    end

    # Re-sorts the stations file by operator and converts Plus Codes in place.
    def refresh_stations!
      working = self.class.parse_manual(@manual_path)
      confirmed = self.class.parse_manual(@confirmed_path)
      before = self.class.parse_manual(@stations_path).depots
      depots = depot_catalog(working, confirmed)
      write_stations(depots)
      (depots - before).count { |row| row["note"].to_s.include?("Plus Code") }
    end

    # Rewrites MANUAL_PATH and the stations file: hand-added depots and assigned
    # routes are kept, auto depot rows are refreshed, and every route still
    # without a depot gets a blank row.
    def write_missing!
      working = self.class.parse_manual(@manual_path)
      confirmed = self.class.parse_manual(@confirmed_path)
      manual = combined_manual(working, confirmed)
      result = write!(manual)
      confirmed_ids = confirmed.routes.map { |row| row["route_id"] }.to_set
      covered = result.depots.flat_map { |depot| depot["routes"] }.to_set.merge(confirmed_ids)
      filled = working.routes.select do |row|
        !confirmed_ids.include?(row["route_id"]) &&
          (self.class.route_row_filled?(row) || self.class.route_row_deferred?(row))
      end
      covered.merge(filled.map { |row| row["route_id"] })

      route_city = {}
      blanks = route_files.filter_map do |path, data|
        properties = data["properties"] || {}
        route_id = route_id_for(path, properties)
        route_city[route_id] = city_for(path)
        next if covered.include?(route_id)

        names = Array(data["features"])
          .select { |feature| feature.dig("properties", "feature_type") == "station" && feature.dig("properties", "direction").to_s == "0" }
          .map { |feature| feature.dig("properties", "name") }
        {
          "city" => city_for(path),
          "route_id" => route_id,
          "route_name" => properties["name"],
          "operator" => properties["operator"],
          "departure" => names.first,
          "destination" => names.last
        }
      end

      route_rows = (filled + blanks).sort_by { |row| [ row["operator"].to_s, row["route_name"].to_s, row["route_id"].to_s ] }
      hand_depots = manual.depots.reject { |row| self.class.auto_code?(row["code"]) }
      write_stations(self.class.auto_depot_rows(result.auto_depots, route_city).sort_by { |row| [ row["name"].to_s, row["code"] ] } + hand_depots)
      File.write(@manual_path, self.class.manual_markdown(route_rows:))
      puts "Wrote #{@manual_path} (#{blanks.length} routes without a depot)"
      blanks.length
    end

    def write!(manual = combined_manual)
      buckets = Hash.new { |hash, key|
        hash[key] = {
          "name" => nil,
          "routes" => [],
          "lons" => [],
          "lats" => [],
          "station_ids" => [],
          "address" => nil,
          "auto" => false
        }
      }

      route_files.each do |path, data|
        route_id = route_id_for(path, data["properties"] || {})

        Array(data["features"]).each do |feature|
          props = feature["properties"] || {}
          next unless props["feature_type"] == "station"
          next unless depot_feature?(props)

          lon, lat = Geojson::BusStopClustering.coordinates_for(feature)
          next if lon.nil? || lat.nil?

          name = props["name"].to_s
          station_id = Geojson::BusStopClustering.station_id_for(props)
          key = depot_bucket_key(name:, lon:, lat:, station_id:)
          next if key.blank?

          bucket = buckets[key]
          bucket["auto"] = true
          bucket["name"] ||= name
          bucket["lons"] << lon
          bucket["lats"] << lat
          bucket["station_ids"] << station_id if station_id.present?
          bucket["routes"] << route_id unless bucket["routes"].include?(route_id)
        end
      end

      key_by_code = buckets.keys.index_by { |key| self.class.depot_code(depot_id(key)) }
      manual.depots.each do |row|
        next if key_by_code.key?(row["code"]) || !self.class.depot_row_valid?(row)

        bucket =
          if self.class.depot_row_located?(row)
            lon = row["lon"].to_f
            lat = row["lat"].to_f
            # Google Maps copies 「緯度, 經度」; in Taiwan longitude is always the larger number.
            lon, lat = lat, lon if lon < lat
            key = depot_bucket_key(name: row["name"], lon:, lat:, station_id: nil)
            buckets[key].tap do |located|
              located["lons"] << lon
              located["lats"] << lat
            end
          else
            key = "code:#{row['code']}"
            buckets[key]
          end
        bucket["name"] ||= row["name"]
        bucket["address"] ||= row["note"].presence
        key_by_code[row["code"]] = key
      end

      manual.routes.each do |row|
        next unless self.class.route_row_filled?(row)

        keys = self.class.depot_codes(row).filter_map do |code|
          key_by_code[code].tap do |key|
            warn "Depot #{code} for #{row['route_id']} is not in any depot list (#{@stations_path})" if key.nil?
          end
        end
        next if keys.empty?

        # A hand assignment is authoritative: the route leaves any auto-detected yard.
        buckets.each_value { |bucket| bucket["routes"].delete(row["route_id"]) }
        keys.uniq.each { |key| buckets[key]["routes"] << row["route_id"] }
      end

      entries = buckets.filter_map do |key, bucket|
        next if bucket["routes"].empty?

        # Hand-added depots may lack coordinates; the map skips them until filled.
        lon = average(bucket["lons"])
        lat = average(bucket["lats"])

        depot = {
          "id" => depot_id(key),
          "name" => bucket["name"],
          "routes" => bucket["routes"].sort,
          "lon" => lon&.round(6),
          "lat" => lat&.round(6),
          "address" => bucket["address"],
          "station_ids" => bucket["station_ids"].uniq.sort,
          "grade" => "調度站"
        }.compact
        [ depot, bucket["auto"] ]
      end.sort_by { |depot, _| [ depot["name"].to_s, depot["id"].to_s ] }

      depots = entries.map(&:first)
      FileUtils.mkdir_p(@path.dirname)
      File.write(@path, "#{JSON.pretty_generate(depots)}\n")
      puts "Wrote #{@path} (#{depots.length} bus depots)"
      Result.new(depots: depots, auto_depots: entries.select(&:last).map(&:first))
    end

    private

    def combined_manual(working = self.class.parse_manual(@manual_path), confirmed = self.class.parse_manual(@confirmed_path))
      confirmed_ids = confirmed.routes.map { |row| row["route_id"] }.to_set
      Manual.new(
        depots: depot_catalog(working, confirmed),
        routes: confirmed.routes + working.routes.reject { |row| confirmed_ids.include?(row["route_id"]) }
      )
    end

    # The stations file wins; depot rows still sitting in the route files (older
    # layout) are picked up so the next write moves them over.
    def depot_catalog(working, confirmed)
      rows = (self.class.parse_manual(@stations_path).depots + confirmed.depots + working.depots).uniq do |row|
        self.class.auto_code?(row["code"]) ? [ row["city"], row["code"] ] : row["code"]
      end
      self.class.resolve_plus_codes(rows) { |city| city_reference(rows, city) }
    end

    def city_reference(rows, city)
      located = rows.select { |row| row["city"] == city && self.class.depot_row_located?(row) }
      points = located.map { |row| [ row["lon"].to_f, row["lat"].to_f ] }
      if points.empty?
        points = route_files.filter_map do |path, data|
          next unless city_for(path) == city

          Array(data["features"]).find { |feature| feature.dig("geometry", "type") == "Point" }&.dig("geometry", "coordinates")
        end
      end
      return nil if points.empty?

      [ points.sum(&:first) / points.length, points.sum(&:last) / points.length ]
    end

    def write_stations(depot_rows)
      File.write(@stations_path, self.class.manual_markdown(depot_rows:, intro: STATIONS_INTRO))
    end

    def route_files
      @route_files ||= Dir.glob(@bus_root.join("**/*.geojson")).sort.filter_map do |path|
        next if File.basename(path).start_with?("_")

        [ Pathname(path), JSON.parse(File.read(path)) ]
      rescue JSON::ParserError
        nil
      end
    end

    def route_id_for(path, properties)
      properties["id"].presence || File.basename(path, ".geojson")
    end

    def city_for(path)
      path.relative_path_from(@bus_root).each_filename.first
    end

    def depot_id(key)
      "bus_depot_#{key}".gsub(/[^\w.-]+/, "_").squeeze("_")
    end

    def depot_feature?(properties)
      name = properties["name"] || properties[:name]
      # Re-validate by name so stale stop_role=depot on 「…機廠」 poles are dropped.
      Geojson::BusImporter.depot_stop_name?(name)
    end

    def depot_bucket_key(name:, lon:, lat:, station_id:)
      return "sid:#{station_id}" if station_id.present?
      return nil if name.blank?

      lat_key = format("%.#{COORD_DECIMALS}f", lat.to_f)
      lon_key = format("%.#{COORD_DECIMALS}f", lon.to_f)
      "#{lat_key}|#{lon_key}|#{name}"
    end

    def average(values)
      list = Array(values).compact
      return nil if list.empty?

      list.sum.to_f / list.length
    end
  end
end
