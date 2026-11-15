# frozen_string_literal: true

module Transit
  module Itinerary
    # Builds a variable-length stage tree from itinerary alternatives.
    #
    # Stage count is data-driven: a short trip may be one stage, a multi-transfer
    # trip may be many. Letters (A, B, …, AA, …) are only labels for whatever
    # depth we get — not a fixed A–G template. Grouping heuristics (local feeders
    # before a trunk, consecutive TRA, hub reconvergence) are defaults that can
    # change; prior chat examples are illustrations, not the product spec.
    # Client selection is hub-tree constrained across whatever stages exist.
    class Corridor
      LONG_BUS_MINUTES = 90
      LONG_RAIL_MINUTES = 60
      HUB_ALIASES = {
        "台北" => "台北車站",
        "臺北" => "台北車站",
        "台北車站" => "台北車站",
        "臺北車站" => "台北車站",
        "台北車站(忠孝)" => "台北車站",
        "臺北車站(忠孝)" => "台北車站",
        "台北車站(青島)" => "台北車站",
        "臺北車站(青島)" => "台北車站",
        "台北車站(鄭州)" => "台北車站",
        "北車" => "台北車站",
        "台中" => "台中車站",
        "臺中" => "台中車站",
        "台中車站" => "台中車站",
        "臺中車站" => "台中車站",
        "新烏日" => "新烏日",
        "新烏日站" => "新烏日",
        "高鐵台中" => "高鐵台中",
        "高鐵台中站" => "高鐵台中",
        "台中高鐵" => "高鐵台中",
        "台中高鐵站" => "高鐵台中",
        "台南" => "台南車站",
        "臺南" => "台南車站",
        "台南車站" => "台南車站",
        "臺南車站" => "台南車站",
        "花蓮" => "花蓮車站",
        "花蓮車站" => "花蓮車站",
        "左營" => "左營／高雄",
        "新左營" => "左營／高雄",
        "高雄" => "左營／高雄",
        "高雄車站" => "左營／高雄"
      }.freeze

      # Hubs that share a transfer complex: arrivals here can continue onto the same trunk.
      HUB_TRANSFER_KEYS = {
        "新烏日" => "taichung_hsr",
        "高鐵台中" => "taichung_hsr",
        "左營／高雄" => "kaohsiung_rail",
        "建國客運站" => "kaohsiung_rail"
      }.freeze

      def self.call(itineraries)
        new(itineraries).call
      end

      def initialize(itineraries)
        @itineraries = Array(itineraries)
      end

      def call
        return { "stages" => [], "segments" => [], "default_option" => nil } if @itineraries.empty?

        parts = @itineraries.each_with_index.map { |itinerary, index| split(itinerary, index) }
        stages = build_stages(parts)
        {
          "stages" => stages,
          "segments" => legacy_segments(stages),
          "default_option" => default_itinerary_index(stages, parts)
        }
      end

      private

      def split(itinerary, index)
        {
          index:,
          slices: coalesce_slices(Array(itinerary["legs"])),
          duration: itinerary["duration_minutes"],
          depart_at: itinerary["depart_at"],
          arrive_at: itinerary["arrive_at"]
        }
      end

      # Walk+ride atoms, then merge consecutive local feeders and consecutive
      # TRA majors so alternate ways to the same hub share one stage column.
      def coalesce_slices(legs)
        atoms = []
        buffer = []
        legs.each do |leg|
          buffer << leg
          next unless leg["kind"] == "ride"

          atoms << slice_from(buffer)
          buffer = []
        end
        if buffer.any?
          if atoms.any?
            atoms.last[:legs].concat(buffer)
          else
            atoms << slice_from(buffer)
          end
        end

        merged = []
        atoms.each do |atom|
          if merged.empty?
            merged << atom
            next
          end

          prev = merged.last
          if mergeable_slices?(prev, atom)
            prev[:legs].concat(atom[:legs])
            merged[-1] = slice_from(prev[:legs])
          else
            merged << atom
          end
        end
        absorb_land_feeders_before_water!(merged)
      end

      def mergeable_slices?(left, right)
        # Local feeders share a stage (102 / 102→10).
        return true if !left[:major] && !right[:major]

        false
      end

      # 高鐵＋橘線＋渡輪 → (高鐵＋橘線)｜渡輪, so ferry lines up with flight.
      def absorb_land_feeders_before_water!(slices)
        index = 0
        while index < slices.length
          slice = slices[index]
          unless water_air_mode?(slice[:mode]) && index >= 2
            index += 1
            next
          end

          trunk_at = index - 1
          trunk_at -= 1 while trunk_at.positive? && !slices[trunk_at][:major] && !water_air_mode?(slices[trunk_at][:mode])
          if slices[trunk_at][:major] && !water_air_mode?(slices[trunk_at][:mode]) && trunk_at < index - 1
            legs = slices[trunk_at][:legs]
            ((trunk_at + 1)...index).each { |cursor| legs.concat(slices[cursor][:legs]) }
            slices[trunk_at] = slice_from(legs)
            slices.slice!(trunk_at + 1, index - trunk_at - 1)
            index = trunk_at + 1
          else
            index += 1
          end
        end
        slices
      end

      def water_air_mode?(mode)
        %w[ferry flight].include?(mode.to_s)
      end

      def slice_from(legs)
        rides = legs.select { |leg| leg["kind"] == "ride" }
        last_ride = rides.last
        {
          legs:,
          mode: primary_mode(legs),
          major: rides.any? { |leg| major_trunk_leg?(leg) },
          from_hub: hub_name(rides.first&.dig("from", "name") || legs.first&.dig("from", "name")),
          to_hub: hub_name(last_ride&.dig("to", "name") || legs.last&.dig("to", "name"))
        }
      end

      def build_stages(parts)
        depth = parts.map { |part| part[:slices].length }.max.to_i
        return [] if depth.zero?

        # Default left-align so ferry/flight trunks share a column. Only a
        # leading major on a shorter path (國道客運) spans A+B…; a short path
        # that ends early covers trailing letters from its last slice.
        placements = Array.new(depth) { [] }
        parts.each do |part|
          len = part[:slices].length
          next if len.zero?

          offset = depth - len
          # Only pure land shortcuts (國道客運) span forward. Paths that still
          # contain ferry/flight must left-align so water/air share a column.
          lead_span = offset.positive? &&
            part[:slices].first[:major] &&
            part[:slices].none? { |slice| water_air_mode?(slice[:mode]) }
          part[:slices].each_with_index do |slice, index|
            if lead_span
              if index.zero?
                placements[0] << { part:, slice:, span_end: offset }
              else
                column = offset + index
                placements[column] << { part:, slice:, span_end: column }
              end
            else
              span_end = index
              span_end = depth - 1 if index == len - 1 && len < depth
              placements[index] << { part:, slice:, span_end: }
            end
          end
        end

        stages = (0...depth).map do |column|
          stage_from_placements(stage_letter(column), placements[column], column, depth, parts)
        end
        apply_continues_from!(stages)
        stages
      end

      def stage_from_placements(letter, rows, column, depth, parts)
        groups = rows.group_by { |row| [ option_group_key(row[:slice]), row[:span_end] ] }
        hubs = rows.map { |row| row[:slice][:to_hub] }.compact.uniq
        modes = rows.map { |row| row[:slice][:mode] }.compact.uniq
        role = column_role(rows.map { |row| row[:slice] }, column, depth)

        options = groups.map do |(_key, group)|
          sample_row = group.min_by { |row| row[:part][:duration].to_i }
          slice = sample_row[:slice]
          span_end = sample_row[:span_end]
          covers = (column..span_end).map { |index| stage_letter(index) }
          {
            "title" => option_title(slice, role),
            "mode" => slice[:mode],
            "from_hub" => slice[:from_hub],
            "hub" => slice[:to_hub],
            "legs" => summarize_legs(slice[:legs]),
            "itinerary_indexes" => group.map { |row| row[:part][:index] }.uniq.sort,
            "covers" => covers,
            "duration_minutes" => sample_row[:part][:duration],
            "depart_at" => sample_row[:part][:depart_at],
            "arrive_at" => sample_row[:part][:arrive_at]
          }.compact
        end

        assign_option_ids!(options, letter)
        annotate_hub_connections!(parts, column, options, depth)

        {
          "id" => letter,
          "kind" => options.length > 1 ? "choice" : "shared",
          "title" => stage_title(role, hubs, modes),
          "hubs" => hubs,
          "modes" => modes,
          "options" => options
        }
      end

      def part_slice_at(part, column, depth)
        offset = depth - part[:slices].length
        local = column - offset
        return nil if local.negative?

        part[:slices][local]
      end

      def assign_option_ids!(options, letter)
        return if options.empty?

        options.each do |option|
          covers = Array(option["covers"])
          option["_base_id"] = covers.length > 1 ? covers.join("+") : (covers.first || letter)
        end

        options.group_by { |option| option["_base_id"] }.each do |base, group|
          if group.length == 1
            group[0]["id"] = base
          else
            group.each_with_index { |option, index| option["id"] = "#{base}-#{index + 1}" }
          end
        end

        options.each { |option| option.delete("_base_id") }
      end

      def apply_continues_from!(stages)
        stages.each_with_index do |stage, index|
          next if index.zero?

          prev = stages[index - 1]
          stage["options"].each do |option|
            parents = []

            prev["options"].each do |parent|
              next if parent_covers_stage?(parent, stage["id"])
              parents << parent["id"] if compatible_continuation?(parent, option)
            end

            # Spanning parents that finish on the previous stage (A+B → C).
            stages[0...index].each do |earlier|
              earlier["options"].each do |parent|
                covers = Array(parent["covers"])
                next unless covers.length > 1 && covers.last == prev["id"]
                next if covers.include?(stage["id"])
                parents << parent["id"] if compatible_continuation?(parent, option)
              end
            end

            option["continues_from"] = parents.uniq
          end
        end
      end

      def parent_covers_stage?(parent, stage_id)
        covers = Array(parent["covers"])
        covers.length > 1 && covers.include?(stage_id)
      end

      def compatible_continuation?(parent, child)
        return true if hubs_match?(parent["hub"], child["from_hub"])

        (Array(parent["itinerary_indexes"]) & Array(child["itinerary_indexes"])).any?
      end

      def hubs_match?(left, right)
        return true if left.blank? || right.blank?
        return true if left == right

        hub_key(left) == hub_key(right)
      end

      def hub_key(name)
        normalized = hub_name(name) || name.to_s
        HUB_TRANSFER_KEYS[normalized] || normalized
      end

      def column_role(slices, column, depth)
        return :access if column.zero?
        return :egress if column == depth - 1

        majors = slices.count { |slice| slice[:major] }
        return :trunk if majors.positive? && majors >= (slices.length / 2.0).ceil

        :transfer
      end

      def stage_title(role, hubs, modes)
        hub = hubs.size == 1 ? hubs.first : I18n.t("map.itinerary.segment_destination")
        mode_text = modes.map { |mode| mode_label(mode) }.uniq.join("／")
        case role
        when :access
          I18n.t("map.itinerary.segment_arrive", hub:)
        when :trunk
          if modes.size > 1
            I18n.t("map.itinerary.segment_choice", modes: mode_text, hub:)
          else
            I18n.t("map.itinerary.segment_go", mode: mode_label(modes.first), hub:)
          end
        when :egress
          I18n.t("map.itinerary.segment_egress", hub:)
        when :transfer
          if modes.size > 1
            I18n.t("map.itinerary.segment_choice", modes: mode_text, hub:)
          elsif modes.first
            I18n.t("map.itinerary.segment_transfer", mode: mode_label(modes.first))
          else
            I18n.t("map.itinerary.segment_arrive", hub:)
          end
        else
          I18n.t("map.itinerary.segment_arrive", hub:)
        end
      end

      def option_title(slice, role)
        hub = slice[:to_hub] || I18n.t("map.itinerary.segment_destination")
        mode = slice[:mode]
        names = summarize_legs(slice[:legs]).select { |leg| leg["kind"] == "ride" }.map { |leg| leg["name"] }.compact
        label = names.join("→").presence || (mode && mode_label(mode))

        case role
        when :access
          label ? "#{label} → #{hub}" : I18n.t("map.itinerary.segment_arrive", hub:)
        when :trunk
          if mode
            I18n.t("map.itinerary.segment_go", mode: mode_label(mode), hub:)
          else
            label || hub
          end
        when :egress
          label ? "#{label} → #{hub}" : I18n.t("map.itinerary.segment_egress", hub:)
        else
          label || (mode && I18n.t("map.itinerary.segment_transfer", mode: mode_label(mode))) || hub
        end
      end

      def stage_letter(index)
        return ("A".ord + index).chr if index < 26

        # 26 → AA, 27 → AB …
        "#{stage_letter((index / 26) - 1)}#{('A'.ord + (index % 26)).chr}"
      end

      def default_itinerary_index(stages, parts)
        return parts.first[:index] if stages.empty?

        picks = []
        covered = {}
        stages.each do |stage|
          next if covered[stage["id"]]

          option = stage["options"].first
          next unless option

          picks << option
          Array(option["covers"]).each do |letter|
            covered[letter] = true if letter != stage["id"]
          end
        end

        indexes = picks.map { |option| option["itinerary_indexes"] }
        intersection = indexes.reduce { |acc, row| acc & row }
        intersection&.first || parts.first[:index]
      end

      def legacy_segments(stages)
        stages.flat_map do |stage|
          options = stage["options"]
          if options.length == 1
            option = options.first
            [ {
              "id" => stage["id"],
              "kind" => "shared",
              "title" => stage["title"],
              "mode" => option["mode"],
              "legs" => option["legs"],
              "itinerary_indexes" => option["itinerary_indexes"]
            }.compact ]
          else
            [
              {
                "id" => stage["id"],
                "kind" => "choice",
                "title" => stage["title"],
                "modes" => stage["modes"]
              }.compact
            ] + options.map do |option|
              {
                "id" => option["id"],
                "kind" => "option",
                "title" => option["title"],
                "parent" => stage["id"],
                "mode" => option["mode"],
                "legs" => option["legs"],
                "itinerary_index" => option["itinerary_indexes"].first,
                "itinerary_indexes" => option["itinerary_indexes"],
                "duration_minutes" => option["duration_minutes"],
                "depart_at" => option["depart_at"],
                "arrive_at" => option["arrive_at"]
              }.compact
            end
          end
        end
      end

      # Selection is hub-based on the client; itinerary_indexes stay as the trips
      # that actually contain this slice. connects_from lists other arrivals at
      # the same hub that may be mixed with this onward option.
      def annotate_hub_connections!(parts, column, options, depth)
        return if column.zero?

        options.each do |option|
          from_hub = option["from_hub"]
          next if from_hub.blank?

          peers = parts.filter_map do |part|
            offset = depth - part[:slices].length
            local_prev = (column - 1) - offset
            next if local_prev.negative?

            prev = part[:slices][local_prev]
            next unless prev && hubs_match?(prev[:to_hub], from_hub)

            {
              "itinerary_index" => part[:index],
              "signature" => signature(prev[:legs]),
              "hub" => from_hub
            }
          end
          next if peers.empty?

          option["connects_from"] = peers.uniq { |row| [ row["itinerary_index"], row["signature"] ] }
        end
      end

      def summarize_legs(legs)
        Array(legs).map do |leg|
          {
            "kind" => leg["kind"],
            "mode" => leg["mode"],
            "name" => leg["name"],
            "from" => leg["from"],
            "to" => leg["to"],
            "board_at" => leg["board_at"],
            "alight_at" => leg["alight_at"],
            "color" => leg["color"],
            "geometry" => leg["geometry"],
            "minutes" => leg["minutes"],
            "train_number" => leg["train_number"],
            "route_id" => leg["route_id"],
            "stops" => leg["stops"],
            "departures" => leg["departures"],
            "headway_minutes" => leg["headway_minutes"],
            "departures_omitted" => leg["departures_omitted"]
          }.compact
        end
      end

      def signature(legs)
        Array(legs).select { |leg| leg["kind"] == "ride" }.map { |leg|
          [ leg["mode"], leg["route_id"], leg.dig("from", "name"), leg.dig("to", "name") ].join(":")
        }.join("|")
      end

      # Group by mode + hubs (and name for locals). Ignore route_id so parallel
      # trips to the same place share one letter option (one HSR B-1, one D bus).
      def option_group_key(slice)
        rides = Array(slice[:legs]).select { |leg| leg["kind"] == "ride" }
        rides.map { |leg|
          parts = [ leg["mode"], hub_name(leg.dig("to", "name")) ]
          unless slice[:major]
            parts << hub_name(leg.dig("from", "name"))
            parts << leg["name"]
          end
          parts.join(":")
        }.join("|")
      end

      def major_trunk_leg?(leg)
        return false unless leg["kind"] == "ride"

        mode = leg["mode"].to_s
        minutes = leg["minutes"].to_i
        return true if mode == "hsr" || mode == "flight"
        return true if mode == "ferry" && minutes >= 40
        return true if mode == "rail" && minutes >= LONG_RAIL_MINUTES
        return true if mode == "bus" && minutes >= LONG_BUS_MINUTES

        false
      end

      def primary_mode(legs)
        Array(legs).select { |leg| leg["kind"] == "ride" }
          .map { |leg| leg["mode"].to_s }
          .max_by { |mode|
            case mode
            when "flight" then 4
            when "hsr" then 3
            when "ferry" then 3
            when "rail" then 2
            when "bus" then 1
            else 0
            end
          }
      end

      def hub_name(name)
        raw = name.to_s.sub(/（.*?）\z/, "").strip
        return if raw.blank?

        HUB_ALIASES[raw] || HUB_ALIASES[raw.tr("台", "臺")] || HUB_ALIASES[raw.tr("臺", "台")] || raw
      end

      def mode_label(mode)
        key = mode.to_s == "bus" ? "coach" : mode.to_s
        I18n.t("map.itinerary.kinds.#{key}", default: mode.to_s)
      end
    end
  end
end
