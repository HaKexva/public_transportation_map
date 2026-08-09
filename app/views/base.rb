# frozen_string_literal: true

class Views::Base < Components::Base
  # The `Views::Base` is an abstract class for all your views.

  # By default, it inherits from `Components::Base`, but you
  # can change that to `Phlex::HTML` if you want to keep views and
  # components independent.

  # More caching options at https://www.phlex.fun/components/caching
  def cache_store = Rails.cache

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
          span(class: "time-scrubber__date", data: { time_scrubber_target: "dateLabel" })
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
          button(
            type: "button",
            class: "time-scrubber__btn time-scrubber__btn--primary",
            data: { action: "time-scrubber#jumpToNow" }
          ) { t("map.time_scrubber.now") }
          button(
            type: "button",
            class: "time-scrubber__btn",
            data: { action: "time-scrubber#shiftDay", delta: "1" },
            aria: { label: t("map.time_scrubber.next_day") }
          ) { "›" }
          span(
            class: "time-scrubber__badge",
            data: { time_scrubber_target: "badge" }
          ) { t("map.time_scrubber.synthetic_badge") }
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
