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
          class: "route-page is-booting relative flex h-dvh flex-col bg-background",
          data: {
            controller: "map",
            map_initial_route_id_value: @route["id"],
            map_routes_manifest_url_value: static_geojson_url("geojson/routes.json"),
            map_metro_depots_url_value: static_geojson_url("geojson/metro_depots.json"),
            map_bus_depots_url_value: static_geojson_url("geojson/bus_depots.json"),
            map_out_of_station_transfers_url_value: static_geojson_url("geojson/out_of_station_transfers.json")
          },
          aria: { busy: "true" }
        ) do
          render_header
          div(class: "route-page__body flex min-h-0 flex-1 flex-col overflow-hidden md:flex-row") do
            render_stops_section
            render_map_section
          end
          # Cover the whole page (stops + map). Overlay inside the map pane left
          # the empty stops list visible with no blocker while GeoJSON loads.
          render_boot_overlay
        end
      end

      private

      def display_name
        localized_route_name(@route)
      end

      def render_header
        header(class: "route-page__header shrink-0 border-b border-border/60 bg-background/95 px-4 py-3 backdrop-blur-sm") do
          div(class: "flex items-start gap-3") do
            a(
              href: root_path,
              class: "route-page__back mt-0.5 shrink-0 text-sm text-muted-foreground transition-colors hover:text-foreground"
            ) { t("route.back") }

            span(
              class: "mt-1 size-3 shrink-0 rounded-full",
              style: "background-color: #{route_color}"
            )

            div(class: "min-w-0 flex-1") do
              render RubyUI::Text.new(as: "p", size: "1", weight: "muted") { @system_label }
              h1(class: "text-lg font-semibold leading-tight") { display_name }
              p(class: "mt-1 text-xs text-muted-foreground", data: { map_target: "routeStopsMeta" }) { "" }
              render_route_view_switcher
            end

            span(class: "shrink-0 rounded bg-muted px-2 py-1 text-xs font-medium text-muted-foreground") do
              @route["ref"]
            end

            input(
              type: "checkbox",
              id: "layer-#{@route['id']}",
              class: layer_checkbox_classes,
              checked: true,
              aria: { label: t("route.show_on_map", name: display_name) },
              data: {
                map_target: "layerCheckbox",
                action: "change->map#toggleLayer",
                map_layer_param: @route["id"]
              }
            )

            render_locale_toggle
          end
        end
      end

      def render_stops_section
        section(
          class: "route-page__stops flex max-h-[45vh] min-h-0 w-full shrink-0 flex-col overflow-hidden border-b border-border/60 md:max-h-none md:w-[22rem] md:border-r md:border-b-0",
          data: { map_target: "routeStopsSection" }
        ) do
          div(class: "shrink-0 border-b border-border/40 px-4 py-2") do
            render RubyUI::Text.new(as: "p", size: "1", weight: "muted", class: "uppercase tracking-wide") { t("route.stops_list") }
            h2(class: "sr-only", data: { map_target: "routeStopsTitle" }) { display_name }
          end

          ol(
            class: "route-stops__list min-h-0 flex-1 list-none overflow-y-auto p-2",
            data: { map_target: "routeStopsList" }
          ) do
            li(class: "route-stops__loading px-3 py-6 text-center text-sm text-muted-foreground") do
              t("route.loading_stops")
            end
          end

          p(
            class: "hidden px-4 py-8 text-center text-sm text-muted-foreground",
            data: { map_target: "routeStopsEmpty" }
          ) { t("route.no_stops") }
        end
      end

      def render_map_section
        div(class: "route-page__map relative flex min-h-0 min-w-0 flex-1 flex-col") do
          div(class: "relative min-h-0 min-w-0 flex-1", data: { map_target: "routeMapSection" }) do
            div(
              class: "absolute inset-0 h-full w-full",
              data: { map_target: "map" },
              role: "region",
              aria: { label: t("route.map_aria", name: display_name) }
            )
            render_time_scrubber(empty_hint_key: "route.vehicles_empty_hint")
          end
          render_official_route_panel
        end
      end

      def route_color
        return "#0073B7" if @route["id"] == "airport_mrt"
        return "#6A2C91" if @route["id"] == "airport_mrt_express"

        @route["color"].presence || "#666666"
      end

      def layer_checkbox_classes
        "size-4 shrink-0 rounded border border-border accent-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
      end
    end
  end
end
