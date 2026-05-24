# frozen_string_literal: true

# secret_key_base is required for sessions and signed cookies.
# Resolution order:
#   1. SECRET_KEY_BASE env var (production/Docker/CI/Railway)
#   2. Rails encrypted credentials (config/master.key or RAILS_MASTER_KEY)
#   3. tmp/local_secret.txt for development and test
#
# Check SECRET_KEY_BASE before reading config.secret_key_base — that accessor
# decrypts credentials.yml.enc and raises if RAILS_MASTER_KEY is stale.

if ENV["SECRET_KEY_BASE"].present?
  Rails.application.config.secret_key_base = ENV["SECRET_KEY_BASE"]
  return
end

return if Rails.application.config.secret_key_base.present?

if Rails.env.local?
  secret_path = Rails.root.join("tmp/local_secret.txt")

  unless secret_path.exist?
    secret_path.parent.mkpath
    secret_path.write(SecureRandom.hex(64))
  end

  Rails.application.config.secret_key_base = secret_path.read.strip
end
