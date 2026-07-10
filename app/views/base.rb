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
end
