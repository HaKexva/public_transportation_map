# frozen_string_literal: true

module Views
  module Dashboards
    class Show < Views::Base
      def initialize(routes_manifest: {})
        @routes_manifest = routes_manifest
        super()
      end

      LAYERS = [
        { id: "bus", label: "公車", color: "#2563eb", badge: :blue, description: "市區公車與公路客運" },
        { id: "train", label: "火車", color: "#dc2626", badge: :red, description: "台鐵路網" },
        { id: "hsr", label: "高鐵", color: "#9333ea", badge: :purple, description: "台灣高鐵" },
        { id: "ferry", label: "渡輪", color: "#0891b2", badge: :cyan, description: "渡輪與離島航線" }
      ].freeze

      METRO_SYSTEMS = [
        { id: "taipei_metro", label: "台北捷運", color: "#A74C00", badge: :amber, description: "勾選要顯示的路線" },
        { id: "new_taipei_metro", label: "新北捷運", color: "#E95A0C", badge: :orange, description: "淡海輕軌、安坑輕軌、環狀線" },
        { id: "taoyuan_metro", label: "桃園捷運", color: "#6A2C91", badge: :purple, description: "機場捷運" },
        { id: "taichung_metro", label: "台中捷運", color: "#8FC31F", badge: :lime, description: "綠線" },
        { id: "kaohsiung_metro", label: "高雄捷運", color: "#F5C200", badge: :yellow, description: "紅線、橘線、環狀輕軌" }
      ].freeze

      def view_template
        div(class: "fixed inset-0 overflow-hidden bg-background", data: { controller: "map" }) do
          div(
            id: "taiwan-region-map",
            class: "absolute inset-0 z-0 min-h-dvh w-full",
            data: { map_target: "map" },
            role: "region",
            aria: { label: "Map of Taiwan, Penghu, Kinmen, and Matsu" }
          )
          render_layers_panel
        end
      end

      private

      def render_layers_panel
        div(class: "pointer-events-none absolute inset-y-4 left-4 z-[1000] flex w-80 max-w-[calc(100%-2rem)] flex-col") do
          render RubyUI::Card.new(
            class: "pointer-events-auto flex max-h-full flex-col overflow-hidden border-border/60 bg-background/95 shadow-2xl backdrop-blur-md"
          ) do
            render_header
            render RubyUI::Separator.new
            render_layer_controls
            render RubyUI::Separator.new
            render_footer
          end
        end
      end

      def render_header
        render RubyUI::CardHeader.new(class: "space-y-4 pb-4") do
          div(class: "flex items-start justify-between gap-3") do
            div(class: "space-y-1.5") do
              div(class: "flex items-center gap-2") do
                render_map_icon
                render RubyUI::CardTitle.new(class: "text-lg") { "Public Transit Map" }
              end
              render RubyUI::CardDescription.new { "台灣與離島大眾運輸地圖" }
            end
            render_theme_toggle
          end
        end
      end

      def render_layer_controls
        render RubyUI::CardContent.new(class: "flex-1 overflow-y-auto py-4") do
          render RubyUI::Text.new(as: "p", size: "2", weight: "muted", class: "mb-3 px-1 uppercase tracking-wide") do
            "交通圖層"
          end
          div(class: "flex flex-col gap-1") do
            LAYERS.each { |layer| render_layer_toggle(layer) }
            render_metro_collapsible
          end
        end
      end

      def render_footer
        render RubyUI::CardFooter.new(class: "flex-col items-stretch gap-3 bg-muted/20 pt-4") do
          render RubyUI::Alert.new do
            render_info_icon
            render RubyUI::AlertTitle.new { "圖層提示" }
            render RubyUI::AlertDescription.new do
              plain "可勾選個別路線，或使用「重設」一次顯示全部捷運路線。支線會隨主線一併顯示。站外轉乘（如十四張、紅樹林、板橋、三重、新北產業園區、機場捷運台北車站）在兩條路線都開啟時會以虛線連接。"
            end
          end
          render RubyUI::Button.new(
            variant: :outline,
            size: :sm,
            class: "w-full",
            data: { action: "click->map#resetView" }
          ) { "重設地圖視角" }
        end
      end

      def render_metro_collapsible
        render RubyUI::Collapsible.new(open: true, class: "mt-1 rounded-lg border border-border/60 bg-muted/20") do
          render RubyUI::CollapsibleTrigger.new(
            class: "flex w-full cursor-pointer items-center justify-between gap-2 rounded-lg px-3 py-2.5 text-sm font-semibold hover:bg-accent/50"
          ) do
            span(class: "flex items-center gap-2") do
              span(class: "size-2.5 shrink-0 rounded-full bg-amber-600")
              plain "捷運"
            end
            render_chevron_icon
          end

          render RubyUI::CollapsibleContent.new(class: "space-y-0.5 px-1 pb-2") do
            render_metro_all_toggle
            METRO_SYSTEMS.each { |system| render_metro_system(system) }
          end
        end
      end

      def render_metro_all_toggle
        render_layer_toggle(
          {
            id: "all_metro",
            label: "全部捷運",
            color: "#A74C00",
            badge: :amber,
            badge_label: "全部",
            description: "一次顯示所有城市捷運路線"
          },
          nested: true,
          stimulus_action: "change->map#toggleAllMetro"
        )
      end

      def layer_checkbox_classes
        [
          "peer h-4 w-4 shrink-0 rounded-sm border border-input ring-offset-background accent-primary",
          "disabled:cursor-not-allowed disabled:opacity-50",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
        ]
      end

      def render_metro_system(system)
        routes = @routes_manifest.fetch(system[:id], [])

        render RubyUI::Collapsible.new(
          open: system[:id] == "taipei_metro",
          class: "rounded-lg border border-border/40 bg-background/50"
        ) do
          render RubyUI::CollapsibleTrigger.new(
            class: "flex w-full cursor-pointer items-center justify-between gap-2 rounded-lg px-2 py-2 text-sm font-medium hover:bg-accent/50"
          ) do
            span(class: "flex min-w-0 items-center gap-2") do
              span(class: "size-2.5 shrink-0 rounded-full", style: "background-color: #{system[:color]}")
              plain system[:label]
            end
            render_chevron_icon
          end

          render RubyUI::CollapsibleContent.new(class: "space-y-0.5 px-1 pb-2") do
            if routes.empty?
              render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "px-2 py-1.5") do
                "路線資料準備中"
              end
            else
              render_metro_system_toggle(system)
              main_routes(system[:id]).each { |route| render_route_toggle(route, system:) }
            end
          end
        end
      end

      def main_routes(system_id)
        @routes_manifest.fetch(system_id, []).reject { |route| route["branch_of"].present? }
      end

      def branch_routes_for(main_route_id, system_id: "taipei_metro")
        @routes_manifest.fetch(system_id, []).select { |route| route["branch_of"] == main_route_id }
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
        branches = branch_routes_for(route["id"], system_id: system[:id])
        description = route["name_en"].to_s
        if branches.any?
          branch_names = branches.map { |branch| branch["name"] }.join("、")
          description = "#{description}（含#{branch_names}）"
        end

        render_layer_toggle(
          {
            id: route["id"],
            label: route["name"],
            color: route["color"],
            badge: system[:badge],
            badge_label: route["ref"],
            description: description
          },
          nested: true
        )
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

        div(class: "rounded-lg py-1 transition-colors hover:bg-accent/50 #{padding}") do
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
