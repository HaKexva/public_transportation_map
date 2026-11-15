# frozen_string_literal: true

# Warm the 29MB itinerary graph in the background so the first /plan click
# does not pay JSON parse + index cost.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next unless defined?(Transit::Itinerary::Graph)

  Thread.new do
    Transit::Itinerary::Graph.current
  rescue StandardError => error
    Rails.logger.warn("[itinerary] graph warm failed: #{error.class}: #{error.message}")
  end
end
