# frozen_string_literal: true

module Views
  module Dashboards
    class Show < Views::Base
      def initialize(routes_manifest: {})
        @routes_manifest = routes_manifest
        super()
      end

      BUNDLED_ROUTE_IDS = %w[airport_mrt_express].freeze

      COMING_SOON_LAYERS = [
        { label: "公車", color: "#2563eb" },
        { label: "渡輪", color: "#0891b2" }
      ].freeze

      METRO_LAYER = {
        id: "all_metro",
        label: "捷運",
        color: "#A74C00",
        badge: :amber,
        description: "台北、新北、桃園、台中、高雄捷運與輕軌"
      }.freeze

      TRA_SYSTEM = {
        id: "tra",
        label: "台鐵",
        color: "#004B87",
        badge: :blue,
        description: "縱貫線、山線、海線、東部幹線與支線"
      }.freeze

      HSR_SYSTEM = {
        id: "hsr",
        label: "高鐵",
        color: "#F4811A",
        badge: :orange,
        description: "台灣高鐵（南港－左營）"
      }.freeze

      OTHER_SYSTEM = {
        id: "other",
        label: "其他",
        color: "#64748B",
        badge: :secondary,
        description: "纜車、機場電車"
      }.freeze

      METRO_SYSTEMS = [
        { id: "taipei_metro", label: "台北捷運", color: "#A74C00", badge: :amber, description: "6 條路線" },
        { id: "new_taipei_metro", label: "新北捷運", color: "#E95A0C", badge: :orange, description: "環狀線、淡海與安坑輕軌" },
        { id: "taoyuan_metro", label: "桃園捷運", color: "#0073B7", badge: :blue, description: "機場捷運（藍／紫雙線）" },
        { id: "taichung_metro", label: "台中捷運", color: "#8FC31F", badge: :lime, description: "綠線" },
        { id: "kaohsiung_metro", label: "高雄捷運", color: "#F5C200", badge: :yellow, description: "紅線、橘線、環狀輕軌" }
      ].freeze

      LEGEND_LINES = [
        {
          label: "機場捷運",
          note: "普通車（藍）／直達車（紫）雙線並排",
          style: :parallel,
          colors: [ "#0073B7", "#6A2C91" ]
        },
        {
          label: "淡海輕軌",
          note: "綠山／藍海雙軌並排",
          style: :parallel,
          colors: [ "#ED6B46", "#ED6B46" ]
        },
        {
          label: "機場電車",
          note: "北側／南側雙軌並排",
          style: :parallel,
          colors: [ "#4F46E5", "#4F46E5" ]
        },
        { label: "聯通道轉乘", note: "單灰色虛線", color: "#525252", style: :dashed },
        { label: "站外轉乘（優惠）", note: "雙灰色虛線（較粗）", color: "#3a3a3a", style: :dashed_double }
      ].freeze

      LEGEND_MARKERS = [
        { label: "一般站", type: :station, color: "#666666" },
        { label: "起迄站", type: :terminal, color: "#A74C00" },
        { label: "轉乘站", type: :transfer, colors: [ "#E3002C", "#A74C00" ] },
        { label: "機廠／維修區", type: :depot, color: "#64748B" },
        { label: "站外轉乘站", type: :out_of_station, color: "#737373" },
        { label: "轉角站（不提供載客服務）", type: :angle_station, color: "#00AFE2" },
        {
          label: "快慢車交會站",
          type: :airport_mrt_transfer,
          colors: [ "#0073B7", "#6A2C91" ],
          note: "A18、A21 僅環北直達部分班次停靠"
        }
      ].freeze

      def view_template
        div(
          class: "map-split-layout fixed inset-0 flex flex-col overflow-hidden bg-background md:flex-row",
          data: { controller: "map split-pane" }
        ) do
          aside(
            class: "map-split-layout__sidebar flex min-h-0 min-w-0 flex-col",
            data: { split_pane_target: "sidebar" },
            aria: { label: "路線圖層與圖例" }
          ) do
            render_layers_panel
            div(class: "map-legend-toolbar shrink-0 border-t border-border/60 bg-background/95 px-4 py-3") do
              render_legend_dialog
            end
          end

          div(
            class: "map-split-layout__resizer shrink-0",
            role: "separator",
            aria: {
              label: "調整側欄與地圖寬度",
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
              aria: { label: "Map of Taiwan, Penghu, Kinmen, and Matsu" }
            )
          end
        end
      end

      private

      def render_legend_dialog
        render RubyUI::Dialog.new do
          render RubyUI::DialogTrigger.new do
            render RubyUI::Button.new(
              variant: :outline,
              size: :sm,
              class: "w-full",
              id: "map-legend-trigger"
            ) { "圖例" }
          end

          render RubyUI::DialogContent.new(size: :sm, id: "map-legend") do
            render RubyUI::DialogHeader.new do
              render RubyUI::DialogTitle.new { "圖例" }
              render RubyUI::DialogDescription.new { "路線與車站符號" }
            end

            div(class: "map-legend-dialog__body space-y-3") do
              render_legend_section("路線", LEGEND_LINES) { |item| render_legend_line_item(item) }
              render_legend_section("車站", LEGEND_MARKERS) { |item| render_legend_marker_item(item) }
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
            elsif item[:style] == :dashed_double
              render_legend_double_dashed(item[:color])
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

      def render_legend_double_dashed(color)
        div(class: "map-legend-parallel-lines map-legend-parallel-lines--fare-discount", aria: { hidden: true }) do
          2.times do
            span(
              class: "map-legend-line map-legend-line--dashed",
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
        style == :dashed ? "#{base} map-legend-line--dashed" : "#{base} map-legend-line--solid"
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
              render RubyUI::Separator.new
              render_footer
            end
          end
        end
      end

      def render_header
        render RubyUI::CardHeader.new(class: "space-y-3 pb-3") do
          div(class: "flex items-start justify-between gap-3") do
            div(class: "space-y-1") do
              div(class: "flex items-center gap-2") do
                render_map_icon
                render RubyUI::CardTitle.new(class: "text-lg leading-tight") { "台灣大眾運輸地圖" }
              end
              render RubyUI::CardDescription.new(class: "text-xs") { "Taiwan Public Transit Map" }
            end
            div(class: "flex shrink-0 items-center gap-1") do
              render_theme_toggle
              button(
                type: "button",
                class: "map-ui-panel__toggle",
                aria: { label: "收合圖層面板", expanded: true, controls: "map-layers-panel-body" },
                data: { action: "click->map#toggleLayersPanel" }
              ) { render_collapse_icon }
            end
          end
        end
      end

      def render_layer_controls
        render RubyUI::CardContent.new(class: "flex min-h-0 flex-1 flex-col overflow-hidden p-0") do
          div(class: "route-search-toolbar shrink-0 space-y-2 border-b border-border/60 px-3 py-3") do
            render_layer_search
            render_all_transit_toggle
            render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "leading-relaxed") do
              "搜尋或點選路線進入站點頁面；勾選可在地圖上顯示。"
            end
          end

          div(class: "route-results min-h-0 flex-1 overflow-y-auto px-2 py-2", data: { map_target: "routeResults" }) do
            searchable_route_groups.each { |group| render_route_search_section(group) }
            render_coming_soon_layers
          end
        end
      end

      def searchable_route_groups
        groups = []
        groups << { kind: :metro, system: METRO_LAYER, metro_systems: active_metro_systems } if active_metro_systems.any?
        groups << { kind: :routes, system: TRA_SYSTEM, routes: tra_routes } if tra_routes.any?
        groups << { kind: :routes, system: HSR_SYSTEM, routes: hsr_routes } if hsr_routes.any?
        groups << { kind: :routes, system: OTHER_SYSTEM, routes: other_routes } if other_routes.any?
        groups
      end

      def render_route_search_section(group)
        return render_metro_layer_section(group) if group[:kind] == :metro

        render_transit_layer_section(group)
      end

      def render_metro_layer_section(group)
        system = group[:system]
        metro_systems = group[:metro_systems]
        section_id = "layer-section-#{system[:id]}"

        render RubyUI::Collapsible.new(
          open: false,
          class: "route-search-section mb-3",
          data: {
            map_target: "layerSearchGroup",
            search_text: metro_layer_search_text(metro_systems)
          }
        ) do
          render_layer_section_trigger(system, section_id: section_id)

          render RubyUI::CollapsibleContent.new(id: section_id, class: "flex flex-col gap-0.5") do
            render_metro_all_toggle
            metro_systems.each { |metro_system| render_metro_system_subsection(metro_system) }
          end
        end
      end

      def render_transit_layer_section(group)
        system = group[:system]
        routes = group[:routes]
        section_id = "layer-section-#{system[:id]}"

        render RubyUI::Collapsible.new(
          open: false,
          class: "route-search-section mb-3",
          data: {
            map_target: "layerSearchGroup",
            search_text: route_section_search_text(system, routes)
          }
        ) do
          render_layer_section_trigger(system, section_id: section_id)

          render RubyUI::CollapsibleContent.new(id: section_id, class: "flex flex-col gap-0.5") do
            render_transit_system_all_toggle(system)
            routes.each { |route| render_route_search_row(route, system:) }
          end
        end
      end

      def render_metro_system_subsection(system)
        routes = system_routes(system[:id])
        section_id = "layer-section-#{system[:id]}"

        render RubyUI::Collapsible.new(
          open: system[:id] == "taipei_metro",
          class: "route-search-subsection mb-2 ml-1 border-l border-border/40 pl-2",
          data: {
            map_target: "layerSearchGroup",
            search_text: metro_system_search_text(system)
          }
        ) do
          render RubyUI::CollapsibleTrigger.new(
            class: [
              "route-search-section__trigger mb-1 flex w-full cursor-pointer items-center",
              "justify-between gap-2 rounded-md px-1 py-1 hover:bg-accent/50"
            ].join(" "),
            aria: {
              expanded: system[:id] == "taipei_metro",
              controls: section_id,
              label: "展開 #{system[:label]} 路線"
            }
          ) do
            span(class: "flex min-w-0 items-center gap-2") do
              span(
                class: "size-2.5 shrink-0 rounded-full",
                style: "background-color: #{system[:color]}"
              )
              render RubyUI::Text.new(as: "span", size: "2", class: "truncate font-medium leading-tight") do
                system[:label]
              end
            end
            span(class: "route-search-section__chevron shrink-0 text-muted-foreground", aria: { hidden: true }) do
              render_chevron_icon
            end
          end

          render RubyUI::CollapsibleContent.new(id: section_id, class: "flex flex-col gap-0.5") do
            render_metro_system_toggle(system)
            routes.each { |route| render_route_search_row(route, system:) }
          end
        end
      end

      def render_layer_section_trigger(system, section_id:)
        render RubyUI::CollapsibleTrigger.new(
          class: [
            "route-search-section__trigger sticky top-0 z-[1] mb-1 flex w-full cursor-pointer items-center",
            "justify-between gap-2 rounded-md bg-background/95 px-1 py-1 backdrop-blur-sm",
            "hover:bg-accent/50"
          ].join(" "),
          aria: {
            expanded: false,
            controls: section_id,
            label: "展開 #{system[:label]} 路線"
          }
        ) do
          span(class: "flex min-w-0 items-center gap-2") do
            span(
              class: "size-2.5 shrink-0 rounded-full",
              style: "background-color: #{system[:color]}"
            )
            render RubyUI::Text.new(
              as: "span",
              size: "1",
              weight: "muted",
              class: "truncate uppercase tracking-wide"
            ) { system[:label] }
          end
          span(class: "route-search-section__chevron shrink-0 text-muted-foreground", aria: { hidden: true }) do
            render_chevron_icon
          end
        end
      end

      def render_route_search_row(route, system:)
        subtitle = route_row_subtitle(route)

        div(
          class: "route-search-item group flex w-full items-start gap-2 rounded-lg border border-transparent px-2 py-2 transition-colors hover:border-border/60 hover:bg-accent/50",
          data: {
            map_target: "layerSearchItem",
            search_text: route_search_text(route, system)
          }
        ) do
          a(
            href: route_path(route["id"]),
            class: "route-search-item__link flex min-w-0 flex-1 items-start gap-2 text-left text-foreground no-underline",
            data: { turbo_frame: "_top" }
          ) do
            span(
              class: "mt-1.5 size-2.5 shrink-0 rounded-full",
              style: "background-color: #{route_display_color(route)}"
            )
            span(class: "min-w-0 flex-1") do
              span(class: "flex items-center gap-2") do
                span(class: "truncate text-sm font-medium leading-tight") { route["name"] }
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

          input(
            type: "checkbox",
            id: "layer-#{route['id']}",
            class: "#{layer_checkbox_classes} mt-0.5 shrink-0",
            disabled: true,
            aria: { label: "在地圖顯示 #{route['name']}" },
            data: {
              map_target: "layerCheckbox",
              action: "click->map#stopCheckboxEvent change->map#toggleLayer",
              map_layer_param: route["id"]
            }
          )
        end
      end

      def route_row_subtitle(route)
        parts = [ route["name_en"].presence ]
        parts << "普通車藍線／直達車紫線並排" if route["id"] == "airport_mrt"
        parts << "綠山／藍海雙軌並排" if route["id"] == "danhai_lrt"
        parts << "北側／南側雙軌並排" if route["id"] == "taoyuan_airport_skytrain"
        parts.compact.join(" · ")
      end

      def route_search_text(route, system)
        [
          system[:label],
          route["name"],
          route["name_en"],
          route["ref"],
          route["id"]&.tr("_", " ")
        ].compact.join(" ")
      end

      def route_section_search_text(system, routes)
        texts = [ system[:label], system[:description], system[:id] ]

        routes.each do |route|
          texts.push(route["name"], route["name_en"], route["ref"], route["id"])
        end

        texts.compact.join(" ")
      end

      def active_metro_systems
        METRO_SYSTEMS.select { |system| @routes_manifest.fetch(system[:id], []).any? }
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

      def render_coming_soon_layers
        render RubyUI::Collapsible.new(
          open: false,
          class: "route-search-section mt-4 border-t border-border/40 px-1 pt-3",
          data: { map_target: "layerSearchMuted" }
        ) do
          render RubyUI::CollapsibleTrigger.new(
            class: [
              "route-search-section__trigger mb-2 flex w-full cursor-pointer items-center justify-between gap-2",
              "rounded-md px-1 py-1 hover:bg-accent/50"
            ].join(" "),
            aria: {
              expanded: false,
              controls: "layer-section-coming-soon",
              label: "展開即將推出圖層"
            }
          ) do
            render RubyUI::Text.new(as: "span", size: "1", weight: "muted", class: "uppercase tracking-wide") do
              "即將推出"
            end
            span(class: "route-search-section__chevron shrink-0 text-muted-foreground", aria: { hidden: true }) do
              render_chevron_icon
            end
          end

          render RubyUI::CollapsibleContent.new(id: "layer-section-coming-soon") do
            div(class: "flex flex-wrap gap-1.5") do
              COMING_SOON_LAYERS.each do |layer|
                span(
                  class: "inline-flex items-center gap-1.5 rounded-full border border-border/60 bg-muted/40 px-2.5 py-1 text-xs text-muted-foreground"
                ) do
                  span(class: "size-2 shrink-0 rounded-full", style: "background-color: #{layer[:color]}")
                  plain layer[:label]
                end
              end
            end
          end
        end
      end

      def render_footer
        render RubyUI::CardFooter.new(class: "flex flex-col bg-muted/20 p-0 md:gap-2 md:px-4 md:pt-3 md:pb-4") do
          div(class: "hidden flex-col items-stretch gap-2 md:flex") do
            div(class: "grid grid-cols-2 gap-2") do
              render RubyUI::Button.new(
                variant: :default,
                size: :sm,
                class: "w-full",
                data: { action: "click->map#showAllTransit" }
              ) { "顯示全部路線" }
              render RubyUI::Button.new(
                variant: :outline,
                size: :sm,
                class: "w-full",
                data: { action: "click->map#resetViewport" }
              ) { "重設視角" }
            end
            render RubyUI::Button.new(
              variant: :ghost,
              size: :sm,
              class: "w-full text-muted-foreground",
              data: { action: "click->map#showAllMetro" }
            ) { "僅顯示捷運與輕軌" }
            if tra_routes.any?
              render RubyUI::Button.new(
                variant: :ghost,
                size: :sm,
                class: "w-full text-muted-foreground",
                data: { action: "click->map#showAllTra" }
              ) { "僅顯示台鐵" }
            end
            render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "leading-relaxed") do
              "不同捷運系統之間的轉乘皆為站外轉乘；需同時開啟兩條路線，會以灰色虛線連接各系統站體（如十四張：環狀線 Y08 與安坑輕軌 K09）。"
            end
          end
        end
      end

      def render_transit_system_all_toggle(system)
        render_layer_toggle(
          {
            id: system[:id],
            label: "顯示全部路線",
            color: system[:color],
            badge: system[:badge],
            badge_label: "全部",
            description: system[:description]
          },
          nested: true,
          extra_padding: true,
          stimulus_action: "change->map#toggleMetroSystem",
          metro_system_param: system[:id]
        )
      end

      def render_all_transit_toggle
        render_layer_toggle(
          {
            id: "all_transit",
            label: "全部路線",
            color: "#2563EB",
            badge: :blue,
            badge_label: "全部",
            description: "捷運、輕軌、台鐵、高鐵與其他已收錄路線"
          },
          stimulus_action: "change->map#toggleAllTransit"
        )
      end

      def render_metro_all_toggle
        render_layer_toggle(
          {
            id: "all_metro",
            label: "顯示全部路線",
            color: METRO_LAYER[:color],
            badge: METRO_LAYER[:badge],
            badge_label: "全部",
            description: METRO_LAYER[:description]
          },
          nested: true,
          extra_padding: true,
          stimulus_action: "change->map#toggleAllMetro"
        )
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
          label(for: "layer-search", class: "sr-only") { "搜尋路線" }
          div(class: "relative") do
            span(class: "pointer-events-none absolute inset-y-0 left-3 flex items-center text-muted-foreground", aria: { hidden: true }) do
              render_search_icon
            end
            input(
              type: "search",
              id: "layer-search",
              placeholder: "搜尋路線、代碼或站名…",
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
              aria: { label: "清除搜尋" },
              data: {
                map_target: "layerSearchClear",
                action: "click->map#clearLayerSearch"
              }
            ) { "清除" }
          end
          p(
            class: "hidden px-2 text-xs text-muted-foreground",
            data: { map_target: "layerSearchEmpty" }
          ) { "找不到符合的路線" }
        end
      end

      def render_metro_system(system)
        render RubyUI::Collapsible.new(
          open: system[:id] == "taipei_metro",
          class: "rounded-lg border border-border/40 bg-muted/20",
          data: {
            map_target: "layerSearchGroup",
            search_text: metro_system_search_text(system)
          }
        ) do
          render RubyUI::CollapsibleTrigger.new(
            class: "flex w-full cursor-pointer items-center justify-between gap-2 rounded-lg px-2.5 py-2 text-sm font-medium hover:bg-accent/50"
          ) do
            span(class: "flex min-w-0 flex-col items-start gap-0.5 text-left") do
              span(class: "flex items-center gap-2") do
                span(class: "size-2.5 shrink-0 rounded-full", style: "background-color: #{system[:color]}")
                plain system[:label]
              end
              render RubyUI::Text.new(as: "span", size: "1", weight: "muted") { system[:description] }
            end
            render_chevron_icon
          end

          render RubyUI::CollapsibleContent.new(class: "space-y-0.5 px-1 pb-2") do
            render_metro_system_toggle(system)
            system_routes(system[:id]).each { |route| render_route_toggle(route, system:) }
          end
        end
      end

      def system_routes(system_id)
        @routes_manifest.fetch(system_id, []).reject { |route| BUNDLED_ROUTE_IDS.include?(route["id"]) }
      end

      def render_metro_system_toggle(system)
        render_layer_toggle(
          {
            id: system[:id],
            label: system[:label],
            color: system[:color],
            badge: system[:badge],
            badge_label: "全部",
            description: system[:description]
          },
          nested: true,
          extra_padding: true,
          stimulus_action: "change->map#toggleMetroSystem",
          metro_system_param: system[:id]
        )
      end

      def render_route_toggle(route, system:)
        description = route["name_en"].presence
        if route["id"] == "airport_mrt"
          description = [ description, "普通車藍線／直達車紫線並排" ].compact.join(" · ")
        end
        if route["id"] == "danhai_lrt"
          description = [ description, "綠山／藍海雙軌並排" ].compact.join(" · ")
        end
        if route["id"] == "taoyuan_airport_skytrain"
          description = [ description, "北側／南側雙軌並排" ].compact.join(" · ")
        end

        render_layer_toggle(
          {
            id: route["id"],
            label: route["name"],
            color: route_display_color(route),
            badge: system[:badge],
            badge_label: route["ref"],
            description: description
          },
          nested: true
        )
      end

      def route_display_color(route)
        return "#0073B7" if route["id"] == "airport_mrt"

        route["color"]
      end

      def render_layer_toggle(layer, nested: false, extra_padding: false, stimulus_action: "change->map#toggleLayer", metro_system_param: nil)
        input_id = "layer-#{layer[:id]}"
        badge_label = layer[:badge_label] || layer[:label]

        padding = if extra_padding
          "pl-3 pr-1"
        elsif nested
          "pl-2 pr-1"
        else
          "px-2"
        end

        checkbox_data = {
          map_target: "layerCheckbox",
          action: stimulus_action
        }
        checkbox_data[:map_layer_param] = layer[:id] if stimulus_action == "change->map#toggleLayer"
        checkbox_data[:map_metro_system_param] = metro_system_param if metro_system_param

        div(
          class: "rounded-lg py-1.5 transition-colors hover:bg-accent/50 #{padding}",
          data: {
            map_target: "layerSearchItem",
            search_text: layer_search_text(layer)
          }
        ) do
          div(class: "flex items-center justify-between gap-3") do
            div(class: "flex min-w-0 flex-1 items-center gap-3") do
              input(
                type: "checkbox",
                id: input_id,
                class: layer_checkbox_classes,
                disabled: true,
                data: checkbox_data
              )
              render RubyUI::FormFieldLabel.new(for: input_id, class: "flex min-w-0 cursor-pointer flex-col gap-0.5") do
                span(class: "flex items-center gap-2 font-medium") do
                  span(class: "size-2.5 shrink-0 rounded-full", style: "background-color: #{layer[:color]}")
                  plain layer[:label]
                end
                if layer[:description].present?
                  render RubyUI::Text.new(as: "span", size: "1", weight: "muted") { layer[:description] }
                end
              end
            end
            render RubyUI::Badge.new(variant: layer[:badge], size: :sm) { badge_label }
          end
        end
      end

      def layer_search_text(layer)
        [
          layer[:label],
          layer[:description],
          layer[:badge_label],
          layer[:id]&.tr("_", " ")
        ].compact.join(" ")
      end

      def metro_system_search_text(system)
        routes = system_routes(system[:id])
        texts = [ system[:label], system[:description], system[:id] ]

        routes.each do |route|
          texts.push(route["name"], route["name_en"], route["ref"], route["id"])
        end

        texts.compact.join(" ")
      end

      def metro_layer_search_text(metro_systems)
        texts = [ METRO_LAYER[:label], METRO_LAYER[:description], "捷運", "輕軌" ]

        metro_systems.each do |system|
          texts << metro_system_search_text(system)
        end

        texts.compact.join(" ")
      end

      def other_routes_search_text
        texts = [ OTHER_SYSTEM[:label], OTHER_SYSTEM[:description], "other" ]

        other_routes.each do |route|
          texts.push(route["name"], route["name_en"], route["ref"], route["id"])
        end

        texts.compact.join(" ")
      end

      def render_theme_toggle
        render RubyUI::ThemeToggle.new(
          class: "inline-flex shrink-0 items-center rounded-lg border border-border bg-muted/50 p-0.5",
          data: { controller: "ruby-ui--theme-toggle" }
        ) do
          button(
            type: "button",
            class: "theme-toggle-button",
            aria: { label: "淺色模式" },
            data: {
              ruby_ui__theme_toggle_target: "lightButton",
              action: "click->ruby-ui--theme-toggle#setLightTheme"
            }
          ) { render_sun_icon }

          button(
            type: "button",
            class: "theme-toggle-button",
            aria: { label: "深色模式" },
            data: {
              ruby_ui__theme_toggle_target: "darkButton",
              action: "click->ruby-ui--theme-toggle#setDarkTheme"
            }
          ) { render_moon_icon }
        end
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

      def render_info_icon
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
          s.circle(cx: "12", cy: "12", r: "10")
          s.path(d: "M12 16v-4")
          s.path(d: "M12 8h.01")
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

      def render_collapse_icon
        svg(
          xmlns: "http://www.w3.org/2000/svg",
          viewbox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          stroke_width: "2",
          stroke_linecap: "round",
          stroke_linejoin: "round",
          class: "map-ui-panel__chevron size-4 shrink-0",
          aria: { hidden: true }
        ) do |s|
          s.path(d: "m18 15-6-6-6 6")
        end
      end

      def render_chevron_icon
        svg(
          xmlns: "http://www.w3.org/2000/svg",
          viewbox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          stroke_width: "2",
          stroke_linecap: "round",
          stroke_linejoin: "round",
          class: "size-4 shrink-0 text-muted-foreground"
        ) do |s|
          s.path(d: "m6 9 6 6 6-6")
        end
      end
    end
  end
end
