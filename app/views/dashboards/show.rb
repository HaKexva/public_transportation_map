# frozen_string_literal: true

module Views
  module Dashboards
    class Show < Views::Base
      def initialize(routes_manifest: {})
        @routes_manifest = routes_manifest
        super()
      end

      BUNDLED_ROUTE_IDS = %w[airport_mrt_express].freeze

      METRO_SYSTEM_META = [
        { id: "taipei_metro", color: "#A74C00", badge: :amber },
        { id: "new_taipei_metro", color: "#E95A0C", badge: :orange },
        { id: "taoyuan_metro", color: "#0073B7", badge: :blue },
        { id: "taichung_metro", color: "#8FC31F", badge: :lime },
        { id: "kaohsiung_metro", color: "#FAA73F", badge: :orange }
      ].freeze

      def view_template
        div(
          class: "map-split-layout fixed inset-0 flex flex-col overflow-hidden bg-background md:flex-row",
          data: { controller: "map split-pane" }
        ) do
          div(
            class: "map-layers-backdrop",
            data: { action: "click->map#closeMobileLayers" },
            aria: { hidden: true }
          )

          aside(
            class: "map-split-layout__sidebar flex min-h-0 min-w-0 flex-col",
            data: { split_pane_target: "sidebar", map_target: "layersSidebar" },
            aria: { label: t("map.layers_aria") }
          ) do
            render_layers_panel
            render_sidebar_footer
          end

          div(
            class: "map-split-layout__resizer shrink-0",
            role: "separator",
            aria: {
              label: t("map.resizer_aria"),
              orientation: "vertical",
              valuemin: 240,
              valuemax: 720,
              valuenow: 352
            },
            tabindex: 0,
            data: {
              split_pane_target: "resizer",
              action: "pointerdown->split-pane#startDrag"
            }
          )

          div(
            class: "map-split-layout__map relative min-h-0 min-w-0 flex-1",
            data: { split_pane_target: "mapPane" }
          ) do
            div(
              id: "taiwan-region-map",
              class: "absolute inset-0 z-0 h-full w-full",
              data: { map_target: "map" },
              role: "region",
              aria: { label: t("map.map_aria") }
            )
            render_mobile_map_toolbar
          end

          render_legend_dialog
        end
      end

      private

      def category_chips
        [
          { id: "metro", label: t("map.categories.metro") },
          { id: "tra", label: t("map.categories.tra") },
          { id: "hsr", label: t("map.categories.hsr") },
          { id: "other", label: t("map.categories.other") }
        ]
      end

      def metro_layer
        {
          id: "all_metro",
          label: t("map.layers.metro.label"),
          color: "#A74C00",
          badge: :amber,
          description: t("map.layers.metro.description")
        }
      end

      def tra_system
        {
          id: "tra",
          label: t("map.layers.tra.label"),
          color: "#004B87",
          badge: :blue,
          description: t("map.layers.tra.description")
        }
      end

      def hsr_system
        {
          id: "hsr",
          label: t("map.layers.hsr.label"),
          color: "#DB5325",
          badge: :orange,
          description: t("map.layers.hsr.description")
        }
      end

      def other_system
        {
          id: "other",
          label: t("map.layers.other.label"),
          color: "#64748B",
          badge: :secondary,
          description: t("map.layers.other.description")
        }
      end

      def metro_systems
        METRO_SYSTEM_META.map do |meta|
          meta.merge(
            label: t("map.metro_systems.#{meta[:id]}.label"),
            description: t("map.metro_systems.#{meta[:id]}.description")
          )
        end
      end

      def legend_route_lines
        [
          {
            label: t("map.legend_routes.airport_mrt.label"),
            note: t("map.legend_routes.airport_mrt.note"),
            style: :parallel,
            colors: [ "#0073B7", "#6A2C91" ]
          },
          {
            label: t("map.legend_routes.danhai_lrt.label"),
            note: t("map.legend_routes.danhai_lrt.note"),
            style: :parallel,
            colors: [ "#ED6B46", "#ED6B46" ]
          },
          {
            label: t("map.legend_routes.skytrain.label"),
            note: t("map.legend_routes.skytrain.note"),
            style: :parallel,
            colors: [ "#4F46E5", "#4F46E5" ]
          }
        ]
      end

      def legend_transfer_lines
        [
          { label: t("map.legend_transfers.passage.label"), note: t("map.legend_transfers.passage.note"), color: "#525252", style: :solid },
          { label: t("map.legend_transfers.fare_discount.label"), note: t("map.legend_transfers.fare_discount.note"), color: "#3a3a3a", style: :dashed },
          { label: t("map.legend_transfers.walk_transfer.label"), note: t("map.legend_transfers.walk_transfer.note"), color: "#737373", style: :dotted }
        ]
      end

      def legend_markers
        [
          { label: t("map.legend_markers.station"), type: :station, color: "#666666" },
          { label: t("map.legend_markers.terminal"), type: :terminal, color: "#A74C00" },
          { label: t("map.legend_markers.transfer.label"), type: :transfer, colors: [ "#E3002C", "#A74C00" ], note: t("map.legend_markers.transfer.note") },
          {
            label: t("map.legend_markers.airport_mrt_transfer.label"),
            type: :airport_mrt_transfer,
            colors: [ "#0073B7", "#6A2C91" ],
            note: t("map.legend_markers.airport_mrt_transfer.note")
          },
          { label: t("map.legend_markers.depot"), type: :depot, color: "#64748B" },
          { label: t("map.legend_markers.out_of_station.label"), type: :out_of_station, color: "#737373", note: t("map.legend_markers.out_of_station.note") },
          { label: t("map.legend_markers.angle_station"), type: :angle_station, color: "#00AFE2" }
        ]
      end

      def render_legend_dialog
        render RubyUI::Dialog.new(class: "contents") do
          render RubyUI::DialogTrigger.new(class: "hidden", id: "map-legend-dialog-root") do
            button(type: "button", class: "hidden") { t("map.legend") }
          end

          render RubyUI::DialogContent.new(size: :sm, id: "map-legend") do
            render RubyUI::DialogHeader.new do
              render RubyUI::DialogTitle.new { t("map.legend") }
              render RubyUI::DialogDescription.new { t("map.legend_description") }
            end

            div(class: "map-legend-dialog__body space-y-3") do
              render_legend_section(t("map.legend_sections.special_routes"), legend_route_lines) { |item| render_legend_line_item(item) }
              render_legend_section(t("map.legend_sections.transfers"), legend_transfer_lines) { |item| render_legend_line_item(item) }
              render_legend_section(t("map.legend_sections.stations"), legend_markers) { |item| render_legend_marker_item(item) }
            end
          end
        end
      end

      def render_legend_open_button(variant: :outline, size: :sm, class_name: "w-full", id: nil)
        render RubyUI::Button.new(
          variant: variant,
          size: size,
          class: class_name,
          id: id,
          type: :button,
          data: { action: "click->map#openLegend" }
        ) { t("map.legend") }
      end

      def render_mobile_map_toolbar
        div(class: "map-mobile-toolbar") do
          render RubyUI::Button.new(
            variant: :primary,
            size: :sm,
            type: :button,
            class: "shadow-md",
            data: { action: "click->map#openMobileLayers" }
          ) { t("map.layers_button") }
          render_legend_open_button(variant: :outline, size: :sm, class_name: "shadow-md", id: "map-legend-trigger-mobile")
          render RubyUI::Button.new(
            variant: :outline,
            size: :sm,
            type: :button,
            class: "shadow-md",
            data: { action: "click->map#resetViewport" }
          ) { t("map.reset_viewport") }
        end
      end

      def render_sidebar_footer
        div(class: "map-sidebar-footer shrink-0 border-t border-border/60 bg-background/95") do
          div(class: "flex flex-col gap-2 px-4 py-3") do
            div(class: "grid grid-cols-2 gap-2") do
              render RubyUI::Button.new(
                variant: :ghost,
                size: :sm,
                class: "w-full text-muted-foreground",
                data: { action: "click->map#showAllMetro" }
              ) { t("map.show_metro_only") }
              render RubyUI::Button.new(
                variant: :outline,
                size: :sm,
                class: "w-full",
                data: { action: "click->map#resetViewport" }
              ) { t("map.reset_viewport") }
            end
            div(class: "flex items-center gap-2") do
              div(class: "min-w-0 flex-1") do
                render_legend_open_button(id: "map-legend-trigger")
              end
              render_theme_toggle
            end
          end
        end
      end

      def render_legend_section(title, items, &block)
        div(class: "map-legend-section space-y-2") do
          render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "uppercase tracking-wide") { title }
          div(class: "space-y-2.5") do
            items.each { |item| block.call(item) }
          end
        end
      end

      def render_legend_line_item(item)
        div(class: "flex items-center gap-3") do
          span(class: "map-legend-swatch", aria: { hidden: true }) do
            if item[:style] == :parallel
              render_legend_parallel_lines(item[:colors])
            else
              span(
                class: legend_line_swatch_classes(item[:style]),
                style: "--legend-line-color: #{item[:color]}"
              )
            end
          end
          div(class: "min-w-0") do
            render RubyUI::Text.new(as: "p", size: "2", class: "font-medium leading-tight") { item[:label] }
            if item[:note]
              render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "leading-tight") { item[:note] }
            end
          end
        end
      end

      def render_legend_parallel_lines(colors)
        div(class: "map-legend-parallel-lines", aria: { hidden: true }) do
          colors.each do |color|
            span(
              class: "map-legend-line map-legend-line--solid",
              style: "--legend-line-color: #{color}"
            )
          end
        end
      end

      def render_legend_marker_item(item)
        div(class: "flex items-center gap-3") do
          span(class: "map-legend-swatch", aria: { hidden: true }) do
            render_legend_marker_swatch(item)
          end
          div(class: "min-w-0") do
            render RubyUI::Text.new(as: "p", size: "2", class: "font-medium leading-tight") { item[:label] }
            if item[:note]
              render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "leading-tight") { item[:note] }
            end
          end
        end
      end

      def render_legend_marker_swatch(item)
        case item[:type]
        when :station
          span(class: "map-legend-station", style: "background-color: #{item[:color]}")
        when :terminal
          div(
            class: "terminal-station-marker map-legend-terminal-marker",
            style: "--terminal-line-color: #{item[:color]}",
            aria: { hidden: true }
          )
        when :transfer
          left, right = item[:colors]
          div(class: "transfer-station-marker map-legend-transfer-marker", aria: { hidden: true }) do
            div(class: "transfer-station-marker__half", style: "background-color: #{left}")
            div(class: "transfer-station-marker__half", style: "background-color: #{right}")
          end
        when :depot
          div(
            class: "metro-depot-marker map-legend-depot-marker",
            style: "--depot-color: #{item[:color]}",
            aria: { hidden: true }
          )
        when :out_of_station
          div(
            class: "out-of-station-marker map-legend-out-of-station-marker",
            style: "background-color: #{item[:color]}",
            aria: { hidden: true }
          )
        when :angle_station
          div(
            class: "angle-station-marker map-legend-angle-station-marker",
            style: "border-color: #{item[:color]}",
            aria: { hidden: true }
          )
        when :airport_mrt_transfer
          left, right = item[:colors]
          div(class: "transfer-station-marker map-legend-transfer-marker", aria: { hidden: true }) do
            div(class: "transfer-station-marker__half", style: "background-color: #{left}")
            div(class: "transfer-station-marker__half", style: "background-color: #{right}")
          end
        when :express
          div(class: "express-stop-marker", style: "background-color: #{item[:color]}", aria: { hidden: true })
        end
      end

      def legend_line_swatch_classes(style)
        base = "map-legend-line shrink-0"
        case style
        when :dashed then "#{base} map-legend-line--dashed"
        when :dotted then "#{base} map-legend-line--dotted"
        else "#{base} map-legend-line--solid"
        end
      end

      def render_layers_panel
        div(
          class: "map-layers-panel flex min-h-0 min-w-0 flex-1 flex-col",
          data: { map_target: "layersPanel" }
        ) do
          render RubyUI::Card.new(
            class: "map-ui-panel pointer-events-auto flex h-full min-h-0 flex-col overflow-hidden rounded-none border-0 border-border/60 bg-background/95 shadow-none"
          ) do
            div(class: "map-ui-panel__header") do
              render_header
            end
            div(id: "map-layers-panel-body", class: "map-ui-panel__body flex min-h-0 flex-1 flex-col overflow-hidden") do
              render RubyUI::Separator.new
              render_layer_controls
            end
          end
        end
      end

      def render_header
        render RubyUI::CardHeader.new(class: "space-y-3 pb-3") do
          div(class: "flex items-start justify-between gap-2") do
            div(class: "map-ui-panel__title-block min-w-0") do
              div(class: "flex items-center gap-2") do
                render_map_icon
                render RubyUI::CardTitle.new(class: "text-lg leading-tight") { t("map.title") }
              end
            end
            render_locale_toggle
          end
        end
      end

      def render_layer_controls
        render RubyUI::CardContent.new(class: "flex min-h-0 flex-1 flex-col overflow-hidden p-0") do
          div(class: "route-search-toolbar shrink-0 space-y-2 border-b border-border/60 px-3 py-3") do
            render_layer_search
            render_category_chips
            render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "leading-relaxed") do
              t("map.search_hint")
            end
          end

          div(class: "route-results min-h-0 flex-1 overflow-y-auto px-2 py-2", data: { map_target: "routeResults" }) do
            searchable_route_groups.each { |group| render_route_search_section(group) }
          end
        end
      end

      def render_category_chips
        chips = category_chips.select { |chip| category_available?(chip[:id]) }
        default_id = chips.first&.dig(:id)

        div(
          class: "layer-category-chips flex flex-wrap gap-1.5",
          role: "tablist",
          aria: { label: t("map.categories_aria") },
          data: { default_category: default_id }
        ) do
          chips.each do |chip|
            active = chip[:id] == default_id

            button(
              type: "button",
              class: [
                "layer-category-chip inline-flex items-center rounded-md border px-3 py-1.5 text-sm font-semibold transition-colors",
                active ? "layer-category-chip--active" : nil
              ].compact.join(" "),
              role: "tab",
              aria: { selected: active },
              data: {
                map_target: "categoryChip",
                category: chip[:id],
                action: "click->map#selectCategory"
              }
            ) { chip[:label] }
          end
        end
      end

      def category_available?(category_id)
        case category_id
        when "metro" then active_metro_systems.any?
        when "tra" then tra_routes.any?
        when "hsr" then hsr_routes.any?
        when "other" then other_routes.any?
        else false
        end
      end

      def searchable_route_groups
        groups = []
        groups << { kind: :metro, category: "metro", system: metro_layer, metro_systems: active_metro_systems } if active_metro_systems.any?
        groups << { kind: :routes, category: "tra", system: tra_system, routes: tra_routes } if tra_routes.any?
        groups << { kind: :routes, category: "hsr", system: hsr_system, routes: hsr_routes } if hsr_routes.any?
        groups << { kind: :routes, category: "other", system: other_system, routes: other_routes } if other_routes.any?
        groups
      end

      def render_route_search_section(group)
        return render_metro_layer_section(group) if group[:kind] == :metro

        render_transit_layer_section(group)
      end

      def render_metro_layer_section(group)
        system = group[:system]
        systems = group[:metro_systems]

        div(
          class: "route-search-section mb-3",
          data: {
            map_target: "layerSearchGroup",
            category: group[:category],
            search_text: metro_layer_search_text(systems)
          }
        ) do
          render_section_header(
            system,
            select_all: {
              id: "all_metro",
              action: "change->map#toggleAllMetro",
              label: t("map.select_all_metro")
            }
          )
          systems.each { |metro_system| render_metro_system_subsection(metro_system) }
        end
      end

      def render_transit_layer_section(group)
        system = group[:system]
        routes = group[:routes]

        div(
          class: "route-search-section mb-3",
          data: {
            map_target: "layerSearchGroup",
            category: group[:category],
            search_text: route_section_search_text(system, routes)
          }
        ) do
          render_section_header(
            system,
            select_all: {
              id: system[:id],
              action: "change->map#toggleMetroSystem",
              metro_system_param: system[:id],
              label: t("map.select_all_system", label: system[:label])
            }
          )
          div(class: "flex flex-col gap-0.5") do
            routes.each { |route| render_route_search_row(route, system:) }
          end
        end
      end

      def render_section_header(system, select_all:)
        div(class: "route-search-section__header sticky top-0 z-[2] mb-1 flex items-center justify-between gap-2 border-b border-border/50 bg-background px-1 py-1.5") do
          span(class: "flex min-w-0 items-center gap-2") do
            span(
              class: "size-2.5 shrink-0 rounded-full",
              style: "background-color: #{system[:color]}"
            )
            render RubyUI::Text.new(
              as: "span",
              size: "3",
              class: "truncate font-semibold leading-tight"
            ) { system[:label] }
          end
          render_compact_select_all(**select_all)
        end
      end

      def render_compact_select_all(id:, action:, label:, metro_system_param: nil)
        checkbox_data = {
          map_target: "layerCheckbox",
          action: action
        }
        checkbox_data[:map_metro_system_param] = metro_system_param if metro_system_param

        label(class: "inline-flex shrink-0 cursor-pointer items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground") do
          input(
            type: "checkbox",
            id: "layer-#{id}",
            class: layer_checkbox_classes,
            disabled: true,
            aria: { label: label },
            data: checkbox_data
          )
          span { t("map.select_all") }
        end
      end

      def render_metro_system_subsection(system)
        routes = system_routes(system[:id])

        div(
          class: "route-search-subsection mb-3",
          data: {
            map_target: "layerSearchGroup",
            category: "metro",
            search_text: metro_system_search_text(system)
          }
        ) do
          div(class: "mb-1 flex items-center justify-between gap-2 px-1 py-1") do
            span(class: "flex min-w-0 items-center gap-2") do
              span(
                class: "size-2.5 shrink-0 rounded-full",
                style: "background-color: #{system[:color]}"
              )
              render RubyUI::Text.new(as: "span", size: "2", class: "truncate font-medium leading-tight") do
                system[:label]
              end
            end
            render_compact_select_all(
              id: system[:id],
              action: "change->map#toggleMetroSystem",
              metro_system_param: system[:id],
              label: t("map.select_all_system", label: system[:label])
            )
          end

          div(class: "flex flex-col gap-0.5") do
            routes.each { |route| render_route_search_row(route, system:) }
          end
        end
      end

      def render_route_search_row(route, system:)
        display_name = localized_route_name(route)
        subtitle = route_row_subtitle(route)

        div(
          class: "route-search-item group flex w-full items-start gap-2 rounded-lg border border-transparent px-2 py-2 transition-colors hover:border-border/60 hover:bg-accent/50",
          data: {
            map_target: "layerSearchItem",
            category: system_category(system),
            route_id: route["id"],
            search_text: route_search_text(route, system)
          }
        ) do
          input(
            type: "checkbox",
            id: "layer-#{route['id']}",
            class: "#{layer_checkbox_classes} mt-0.5 shrink-0",
            disabled: true,
            aria: { label: t("map.show_on_map", name: display_name) },
            data: {
              map_target: "layerCheckbox",
              action: "click->map#stopCheckboxEvent change->map#toggleLayer",
              map_layer_param: route["id"]
            }
          )

          div(class: "route-search-item__link flex min-w-0 flex-1 items-start gap-2 text-left text-foreground") do
            span(
              class: "mt-1.5 size-2.5 shrink-0 rounded-full",
              style: "background-color: #{route_display_color(route)}"
            )
            span(class: "min-w-0 flex-1") do
              span(class: "flex items-center gap-2") do
                span(class: "truncate text-sm font-medium leading-tight") { display_name }
                span(class: "shrink-0 rounded bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground") do
                  route["ref"]
                end
              end
              if subtitle.present?
                render RubyUI::Text.new(as: "span", size: "1", weight: "muted", class: "mt-0.5 line-clamp-2 leading-snug") do
                  subtitle
                end
              end
            end
          end

          a(
            href: route_path(route["id"]),
            class: "route-search-item__open shrink-0 pt-0.5 text-xs text-muted-foreground no-underline hover:text-foreground",
            data: { turbo_frame: "_top" },
            aria: { label: t("map.open_route_map_for", name: display_name) }
          ) { t("map.open_route_map") }
        end
      end

      def system_category(system)
        case system[:id]
        when "tra" then "tra"
        when "hsr" then "hsr"
        when "other" then "other"
        else "metro"
        end
      end

      def route_row_subtitle(route)
        parts = []
        parts << t("map.route_notes.airport_mrt") if route["id"] == "airport_mrt"
        parts << t("map.route_notes.danhai_lrt") if route["id"] == "danhai_lrt"
        parts << t("map.route_notes.taoyuan_airport_skytrain") if route["id"] == "taoyuan_airport_skytrain"
        parts.compact.join(" · ")
      end

      def route_search_text(route, system)
        [
          system[:label],
          route["name"],
          route["name_en"],
          route["ref"],
          route["id"]&.tr("_", " "),
          *Array(route["station_names"])
        ].compact.join(" ")
      end

      def route_section_search_text(system, routes)
        texts = [ system[:label], system[:description], system[:id] ]

        routes.each do |route|
          texts.push(
            route["name"],
            route["name_en"],
            route["ref"],
            route["id"],
            *Array(route["station_names"])
          )
        end

        texts.compact.join(" ")
      end

      def active_metro_systems
        metro_systems.select { |system| @routes_manifest.fetch(system[:id], []).any? }
      end

      def tra_routes
        @routes_manifest.fetch("tra", [])
      end

      def hsr_routes
        @routes_manifest.fetch("hsr", [])
      end

      def other_routes
        @routes_manifest.fetch("other", [])
      end

      def layer_checkbox_classes
        [
          "peer h-4 w-4 shrink-0 rounded-sm border border-input ring-offset-background accent-primary",
          "disabled:cursor-not-allowed disabled:opacity-50",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
          "relative z-10"
        ].join(" ")
      end

      def render_layer_search
        div(class: "layer-search") do
          label(for: "layer-search", class: "sr-only") { t("map.search_label") }
          div(class: "relative") do
            span(class: "pointer-events-none absolute inset-y-0 left-3 flex items-center text-muted-foreground", aria: { hidden: true }) do
              render_search_icon
            end
            input(
              type: "search",
              id: "layer-search",
              placeholder: t("map.search_placeholder"),
              autocomplete: "off",
              class: [
                "flex h-10 w-full rounded-lg border border-border bg-background py-2 pl-9 pr-9 text-sm shadow-xs",
                "placeholder:text-muted-foreground",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50 focus-visible:border-ring"
              ].join(" "),
              data: {
                map_target: "layerSearchInput",
                action: "input->map#filterLayers search->map#filterLayers keydown.esc->map#clearLayerSearch"
              }
            )
            button(
              type: "button",
              class: "absolute inset-y-0 right-1 hidden rounded-md px-2 text-xs text-muted-foreground hover:bg-accent hover:text-foreground",
              aria: { label: t("map.clear_search") },
              data: {
                map_target: "layerSearchClear",
                action: "click->map#clearLayerSearch"
              }
            ) { t("map.clear") }
          end
          p(
            class: "hidden px-2 text-xs text-muted-foreground",
            data: { map_target: "layerSearchEmpty" }
          ) { t("map.no_results") }
        end
      end

      def system_routes(system_id)
        @routes_manifest.fetch(system_id, []).reject { |route| BUNDLED_ROUTE_IDS.include?(route["id"]) }
      end

      def route_display_color(route)
        return "#0073B7" if route["id"] == "airport_mrt"

        route["color"]
      end

      def metro_system_search_text(system)
        routes = system_routes(system[:id])
        texts = [ system[:label], system[:description], system[:id] ]

        routes.each do |route|
          texts.push(
            route["name"],
            route["name_en"],
            route["ref"],
            route["id"],
            *Array(route["station_names"])
          )
        end

        texts.compact.join(" ")
      end

      def metro_layer_search_text(systems)
        texts = [
          metro_layer[:label],
          metro_layer[:description],
          t("map.categories.metro"),
          "LRT",
          "輕軌"
        ]

        systems.each do |system|
          texts << metro_system_search_text(system)
        end

        texts.compact.join(" ")
      end

      def render_search_icon
        svg(
          xmlns: "http://www.w3.org/2000/svg",
          viewbox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          stroke_width: "2",
          stroke_linecap: "round",
          stroke_linejoin: "round",
          class: "size-3.5"
        ) do |s|
          s.circle(cx: "11", cy: "11", r: "8")
          s.path(d: "m21 21-4.3-4.3")
        end
      end

      def render_map_icon
        svg(
          xmlns: "http://www.w3.org/2000/svg",
          viewbox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          stroke_width: "2",
          stroke_linecap: "round",
          stroke_linejoin: "round",
          class: "size-5 text-primary"
        ) do |s|
          s.path(d: "M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z")
          s.path(d: "M15 5.764v15")
          s.path(d: "M9 3.236v15")
        end
      end

      def render_theme_toggle
        render RubyUI::ThemeToggle.new(
          class: "inline-flex shrink-0 items-center rounded-lg border border-border bg-muted/50 p-0.5",
          data: { controller: "ruby-ui--theme-toggle" }
        ) do
          button(
            type: "button",
            class: "theme-toggle-button",
            aria: { label: t("map.light_mode") },
            data: {
              ruby_ui__theme_toggle_target: "lightButton",
              action: "click->ruby-ui--theme-toggle#setLightTheme"
            }
          ) { render_sun_icon }

          button(
            type: "button",
            class: "theme-toggle-button",
            aria: { label: t("map.dark_mode") },
            data: {
              ruby_ui__theme_toggle_target: "darkButton",
              action: "click->ruby-ui--theme-toggle#setDarkTheme"
            }
          ) { render_moon_icon }
        end
      end

      def render_sun_icon
        svg(
          xmlns: "http://www.w3.org/2000/svg",
          viewbox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          stroke_width: "2",
          stroke_linecap: "round",
          stroke_linejoin: "round",
          class: "size-4"
        ) do |s|
          s.circle(cx: "12", cy: "12", r: "4")
          s.path(d: "M12 2v2")
          s.path(d: "M12 20v2")
          s.path(d: "m4.93 4.93 1.41 1.41")
          s.path(d: "m17.66 17.66 1.41 1.41")
          s.path(d: "M2 12h2")
          s.path(d: "M20 12h2")
          s.path(d: "m6.34 17.66-1.41 1.41")
          s.path(d: "m19.07 4.93-1.41 1.41")
        end
      end

      def render_moon_icon
        svg(
          xmlns: "http://www.w3.org/2000/svg",
          viewbox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          stroke_width: "2",
          stroke_linecap: "round",
          stroke_linejoin: "round",
          class: "size-4"
        ) do |s|
          s.path(d: "M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z")
        end
      end
    end
  end
end
