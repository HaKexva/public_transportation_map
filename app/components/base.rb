# frozen_string_literal: true

class Components::Base < Phlex::HTML
  include RubyUI
  # Include any helpers you want to be available across all components
  include Phlex::Rails::Helpers::Routes

  def t(key, **options)
    I18n.t(key, **options)
  end

  if Rails.env.development?
    def before_template
      comment { "Before #{self.class.name}" }
      super
    end
  end
end
