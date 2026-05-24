ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# After a master-key rotation, Railway may still have the old RAILS_MASTER_KEY while
# credentials.yml.enc was re-encrypted. A stale key makes Active Record decrypt fail
# on boot even when SECRET_KEY_BASE is set — drop the conflicting variable.
ENV.delete("RAILS_MASTER_KEY") if ENV["SECRET_KEY_BASE"].to_s != ""
