class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_locale

  private

  def set_locale
    locale = params[:locale].presence || cookies[:locale].presence || I18n.default_locale
    locale = locale.to_sym
    locale = I18n.default_locale unless I18n.available_locales.include?(locale)

    I18n.locale = locale
  end
end
