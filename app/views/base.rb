# frozen_string_literal: true

class Views::Base < Components::Base
  # The `Views::Base` is an abstract class for all your views.

  # By default, it inherits from `Components::Base`, but you
  # can change that to `Phlex::HTML` if you want to keep views and
  # components independent.

  # More caching options at https://www.phlex.fun/components/caching
  def cache_store = Rails.cache

  # public/ geojson indexes are Cache-Control:max-age long-lived; bust when mtime changes.
  def static_geojson_url(relative_path)
    path = Rails.public_path.join(relative_path.delete_prefix("/"))
    version = path.exist? ? path.mtime.to_i : 0
    "/#{relative_path.delete_prefix("/")}?v=#{version}"
  end

  def english_locale?
    I18n.locale.to_s == "en"
  end

  def localized_route_name(route)
    if english_locale?
      route["name_en"].presence || route["name"]
    else
      route["name"]
    end
  end

  def render_locale_toggle
    current = I18n.locale.to_s

    button(
      type: "button",
      class: "locale-toggle inline-flex shrink-0 items-center rounded-lg border border-border bg-muted/50 p-0.5",
      aria: { label: t("locale.toggle") },
      data: {
        controller: "locale-toggle",
        action: "click->locale-toggle#toggle"
      }
    ) do
      span(
        class: "locale-toggle-button",
        aria: { hidden: true, pressed: (current == "zh-TW").to_s }
      ) { "中" }
      span(
        class: "locale-toggle-button",
        aria: { hidden: true, pressed: (current == "en").to_s }
      ) { "EN" }
    end
  end

  def render_route_view_switcher
    nav(
      class: "route-view-switcher mt-2 inline-flex rounded-lg border border-border bg-muted/60 p-0.5",
      role: "tablist",
      aria: { label: t("route.view_modes.aria") }
    ) do
      [
        [ "map", t("route.view_modes.map") ],
        [ "official", t("route.view_modes.official") ]
      ].each do |view, label|
        selected = view == "map"
        button(
          type: "button",
          class: [
            "rounded-md px-2.5 py-1 text-xs font-medium",
            selected ? "bg-background text-foreground shadow-xs" : "text-muted-foreground"
          ].join(" "),
          role: "tab",
          aria: { selected: selected.to_s },
          data: {
            map_target: "routeViewTab",
            view: view,
            action: "click->map#switchRouteView",
            map_view_param: view
          }
        ) { label }
      end
    end
  end

  def render_official_route_panel
    div(
      class: "route-official-panel hidden min-h-0 flex-1 flex-col overflow-y-auto bg-background p-4",
      data: { map_target: "routeOfficialPanel" }
    ) do
      a(
        href: "#",
        target: "_blank",
        rel: "noreferrer noopener",
        class: "route-official-panel__link hidden",
        data: { map_target: "routeOfficialLink" }
      ) do
        img(
          class: "route-official-panel__image mx-auto max-h-full max-w-full object-contain",
          data: { map_target: "routeOfficialImage" },
          alt: ""
        )
      end
      p(
        class: "hidden px-2 py-8 text-center text-sm text-muted-foreground",
        data: { map_target: "routeOfficialEmpty" }
      ) { t("route.official_map_missing") }
      p(class: "route-official-panel__source mt-3 text-center text-[11px] text-muted-foreground") { t("route.official_map_source") }
    end
  end

  def render_boot_overlay
    div(
      class: "map-boot-overlay",
      data: { map_target: "bootOverlay" },
      role: "status",
      aria: { busy: "true", live: "polite", label: t("map.boot.aria") }
    ) do
      div(class: "map-boot-overlay__card") do
        h2(class: "map-boot-overlay__title") { t("map.boot.title") }
        p(class: "map-boot-overlay__status", data: { map_target: "bootStatus" }) { t("map.boot.starting") }
        div(class: "map-boot-overlay__track", aria: { hidden: true }) do
          div(class: "map-boot-overlay__bar", data: { map_target: "bootProgressBar" })
        end
        p(class: "map-boot-overlay__count", data: { map_target: "bootCount" }) { t("map.boot.count", done: 0, total: 0) }
        ul(class: "map-boot-overlay__list", data: { map_target: "bootList" })
      end
    end
  end

  def render_time_scrubber(empty_hint_key: "map.time_scrubber.empty_hint")
    div(
      class: "time-scrubber time-scrubber--collapsed",
      data: {
        controller: "time-scrubber",
        time_scrubber_target: "panel"
      },
      role: "region",
      aria: { label: t("map.time_scrubber.aria") }
    ) do
      div(
        class: "time-scrubber__bar",
        data: { action: "pointerdown->time-scrubber#startPanelDrag" }
      ) do
        div(class: "time-scrubber__clock") do
          button(
            type: "button",
            class: "time-scrubber__date",
            data: {
              time_scrubber_target: "dateLabel",
              action: "time-scrubber#openDatePicker"
            },
            aria: { label: t("map.time_scrubber.date_aria") }
          )
          span(class: "time-scrubber__sep", aria: { hidden: true }) { "·" }
          span(class: "time-scrubber__time", data: { time_scrubber_target: "timeLabel" })
        end

        label(class: "time-scrubber__slider-label time-scrubber__slider-label--bar") do
          span(class: "sr-only") { t("map.time_scrubber.scrub_aria") }
          input(
            type: "range",
            class: "time-scrubber__slider",
            min: "0",
            max: "1439",
            step: "1",
            value: "0",
            data: {
              time_scrubber_target: "slider",
              action: "input->time-scrubber#scrub change->time-scrubber#scrub"
            }
          )
        end

        div(class: "time-scrubber__bar-controls") do
          button(
            type: "button",
            class: "time-scrubber__btn",
            data: {
              action: "time-scrubber#togglePlay",
              time_scrubber_target: "playButton"
            },
            aria: { pressed: "false" }
          ) { t("map.time_scrubber.play") }

          label(class: "time-scrubber__speed") do
            span(class: "sr-only") { t("map.time_scrubber.speed_aria") }
            select(
              class: "time-scrubber__speed-select",
              data: {
                time_scrubber_target: "speedSelect",
                action: "change->time-scrubber#changeSpeed"
              },
              aria: { label: t("map.time_scrubber.speed_aria") }
            ) do
              [
                [ 1, t("map.time_scrubber.speed_1x") ],
                [ 2, t("map.time_scrubber.speed_2x") ],
                [ 5, t("map.time_scrubber.speed_5x") ],
                [ 10, t("map.time_scrubber.speed_10x") ],
                [ 30, t("map.time_scrubber.speed_30x") ],
                [ 60, t("map.time_scrubber.speed_60x") ]
              ].each do |value, label|
                option(value: value) { label }
              end
            end
          end

          button(
            type: "button",
            class: "time-scrubber__btn time-scrubber__expand",
            data: {
              action: "time-scrubber#toggleExpanded",
              time_scrubber_target: "expandButton"
            },
            aria: { expanded: "false", label: t("map.time_scrubber.expand") }
          ) { t("map.time_scrubber.expand") }
        end
      end

      div(class: "time-scrubber__details", data: { time_scrubber_target: "details" }) do
        div(class: "time-scrubber__day-row") do
          button(
            type: "button",
            class: "time-scrubber__btn",
            data: { action: "time-scrubber#shiftDay", delta: "-1" },
            aria: { label: t("map.time_scrubber.prev_day") }
          ) { "‹" }
          label(class: "time-scrubber__date-pick") do
            span(class: "sr-only") { t("map.time_scrubber.date_aria") }
            input(
              type: "date",
              class: "time-scrubber__date-input",
              data: {
                time_scrubber_target: "dateInput",
                action: "change->time-scrubber#pickDate"
              },
              aria: { label: t("map.time_scrubber.date_aria") }
            )
          end
          button(
            type: "button",
            class: "time-scrubber__btn",
            data: { action: "time-scrubber#shiftDay", delta: "1" },
            aria: { label: t("map.time_scrubber.next_day") }
          ) { "›" }
          button(
            type: "button",
            class: "time-scrubber__btn time-scrubber__btn--primary",
            data: { action: "time-scrubber#jumpToNow" }
          ) { t("map.time_scrubber.now") }
          span(
            class: "time-scrubber__badge",
            data: { time_scrubber_target: "badge" }
          ) { t("map.time_scrubber.synthetic_badge") }
        end

        div(class: "time-scrubber__periods", role: "group", aria: { label: t("map.time_scrubber.period_aria") }) do
          [
            [ "dawn", 0, 360, 5 * 60 ],
            [ "early", 360, 540, 6 * 60 ],
            [ "morning", 540, 720, 9 * 60 ],
            [ "midday", 720, 900, 12 * 60 ],
            [ "afternoon", 900, 1080, 15 * 60 ],
            [ "evening", 1080, 1260, 18 * 60 ],
            [ "night", 1260, 1440, 21 * 60 ]
          ].each do |id, from_minutes, until_minutes, jump_minutes|
            button(
              type: "button",
              class: "time-scrubber__btn time-scrubber__period",
              data: {
                time_scrubber_target: "periodButton",
                action: "time-scrubber#pickPeriod",
                period: id,
                from: from_minutes,
                until: until_minutes,
                minutes: jump_minutes
              }
            ) { t("map.time_scrubber.period_#{id}") }
          end
        end

        p(class: "time-scrubber__data-note") { t("map.time_scrubber.data_note") }

        p(
          class: "time-scrubber__hint",
          hidden: true,
          data: { time_scrubber_target: "hint" }
        ) { t(empty_hint_key) }

        div(class: "time-scrubber__footer") do
          span(class: "time-scrubber__stats", data: { time_scrubber_target: "vehicleCount" }) { t("map.time_scrubber.vehicle_count", count: 0) }
        end
      end
    end
  end
end
