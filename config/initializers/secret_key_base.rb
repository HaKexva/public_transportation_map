# frozen_string_literal: true

# secret_key_base is required for sessions and signed cookies.
# Production (Railway): set SECRET_KEY_BASE — do not rely on credentials after key rotation.
# Development/test: tmp/local_secret.txt

# Docker asset precompile (see Dockerfile); Rails generates a throwaway key.
return if ENV["SECRET_KEY_BASE_DUMMY"].present?

if ENV["SECRET_KEY_BASE"].present?
  Rails.application.config.secret_key_base = ENV["SECRET_KEY_BASE"]
  return
end

if Rails.env.production?
  raise <<~ERROR
    Missing SECRET_KEY_BASE in production.

    On Railway:
      1. Locally run: bin/rails secret
      2. Variables → add SECRET_KEY_BASE (paste the 128-character output)
      3. Delete RAILS_MASTER_KEY (the leaked/rotated key breaks credentials decrypt)
      4. Redeploy

    Or set RAILS_MASTER_KEY to the current value in config/master.key (32 hex chars).
  ERROR
end

if Rails.env.local?
  secret_path = Rails.root.join("tmp/local_secret.txt")

  unless secret_path.exist?
    secret_path.parent.mkpath
    secret_path.write(SecureRandom.hex(64))
  end

  Rails.application.config.secret_key_base = secret_path.read.strip
end
