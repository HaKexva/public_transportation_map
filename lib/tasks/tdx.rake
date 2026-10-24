namespace :tdx do
  desc "Show today's TDX request counts per dataset and the breaker state (DATE=YYYY-MM-DD, DAYS=n)"
  task usage: :environment do
    days = ENV.fetch("DAYS", "1").to_i.clamp(1, 8)
    last = ENV["DATE"].present? ? Date.parse(ENV["DATE"]) : Date.current

    (0...days).reverse_each do |offset|
      date = last - offset
      usage = Transit::TdxClient.usage(date).sort_by { |_name, count| -count }
      puts "#{date}: #{usage.sum { |_name, count| count }} requests"
      usage.each { |name, count| puts format("  %6d  %s", count, name) }
    end

    if (state = Transit::TdxClient.breaker)
      puts "Breaker OPEN until #{Time.zone.at(state[:until]).strftime('%Y-%m-%d %H:%M:%S')}: #{state[:reason]}"
    else
      puts "Breaker closed"
    end
  end

  desc "Close the TDX circuit breaker (e.g. after replacing the API key)"
  task reset_breaker: :environment do
    Transit::TdxClient.close_breaker!
    puts "Breaker closed"
  end
end
