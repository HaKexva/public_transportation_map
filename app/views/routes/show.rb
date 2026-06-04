# frozen_string_literal: true

module Views
  module Routes
    class Show < Views::Base
      def initialize(route:, system_label:)
        @route = route
        @system_label = system_label
        super()
      end

      def view_template
        div(
          class: "route-page flex h-dvh flex-col bg-background",
          data: {
            controller: "map",
            map_initial_route_id_value: @route["id"]
          }
        ) do
          render_header
          div(class: "route-page__body flex min-h-0 flex-1 flex-col overflow-hidden md:flex-row") do
            render_stops_section
            render_map_section
          end
        end
      end

      private

      def render_header
        header(class: "route-page__header shrink-0 border-b border-border/60 bg-background/95 px-4 py-3 backdrop-blur-sm") do
          div(class: "flex items-start gap-3") do
            a(
              href: root_path,
              class: "route-page__back mt-0.5 shrink-0 text-sm text-muted-foreground transition-colors hover:text-foreground"
            ) { "← 返回地圖" }

            span(
              class: "mt-1 size-3 shrink-0 rounded-full",
              style: "background-color: #{route_color}"
            )

            div(class: "min-w-0 flex-1") do
              render RubyUI::Text.new(as: "p", size: "1", weight: "muted") { @system_label }
              h1(class: "text-lg font-semibold leading-tight") { @route["name"] }
              if @route["name_en"].present?
                render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "mt-0.5") do
                  @route["name_en"]
                end
              end
              p(class: "mt-1 text-xs text-muted-foreground", data: { map_target: "routeStopsMeta" }) { "" }
            end

            span(class: "shrink-0 rounded bg-muted px-2 py-1 text-xs font-medium text-muted-foreground") do
              @route["ref"]
            end

            input(
              type: "checkbox",
              id: "layer-#{@route['id']}",
              class: layer_checkbox_classes,
              checked: true,
              aria: { label: "在地圖顯示 #{@route['name']}" },
              data: {
                map_target: "layerCheckbox",
                action: "change->map#toggleLayer",
                map_layer_param: @route["id"]
              }
            )
          end
        end
      end

      def render_stops_section
        section(
          class: "route-page__stops flex max-h-[45vh] min-h-0 w-full shrink-0 flex-col overflow-hidden border-b border-border/60 md:max-h-none md:w-[22rem] md:border-r md:border-b-0"
        ) do
          div(class: "shrink-0 border-b border-border/40 px-4 py-2") do
            render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "uppercase tracking-wide") { "站點列表" }
            h2(class: "sr-only", data: { map_target: "routeStopsTitle" }) { @route["name"] }
          end

          ol(
            class: "route-stops__list min-h-0 flex-1 list-none overflow-y-auto p-2",
            data: { map_target: "routeStopsList" }
          )

          p(
            class: "hidden px-4 py-8 text-center text-sm text-muted-foreground",
            data: { map_target: "routeStopsEmpty" }
          ) { "此路線沒有站點資料" }
        end
      end

      def render_map_section
        div(class: "route-page__map relative min-h-0 min-w-0 flex-1") do
          div(
            class: "relative h-full w-full",
            data: { map_target: "map" },
            role: "region",
            aria: { label: "#{@route['name']} 路線地圖" }
          )
        end
      end

      def route_color
        return "#0073B7" if @route["id"] == "airport_mrt"

        @route["color"].presence || "#666666"
      end

      def layer_checkbox_classes
        "size-4 shrink-0 rounded border border-border accent-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
      end
    end
  end
end
