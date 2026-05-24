ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# After a master-key rotation, Railway may still have the old RAILS_MASTER_KEY while
# credentials.yml.enc was re-encrypted. A stale key raises InvalidMessage on boot.
if ENV["SECRET_KEY_BASE"].to_s != ""
  ENV.delete("RAILS_MASTER_KEY")
elsif ENV["RAILS_ENV"] == "production" && ENV["RAILS_MASTER_KEY"].to_s != ""
  # Force SECRET_KEY_BASE (or an updated master key) instead of a broken decrypt.
  ENV.delete("RAILS_MASTER_KEY")
end
