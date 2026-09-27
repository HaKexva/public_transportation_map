# frozen_string_literal: true

namespace :solid do
  # When cache/queue/cable share the primary DATABASE_URL, db:prepare sees an
  # existing database and never loads their schema files, leaving the tables missing.
  SOLID_SCHEMA_TABLES = {
    "cache" => "solid_cache_entries",
    "queue" => "solid_queue_jobs",
    "cable" => "solid_cable_messages"
  }.freeze

  desc "Load Solid Cache/Queue/Cable schemas whose tables are missing"
  task ensure_schemas: :environment do
    SOLID_SCHEMA_TABLES.each do |name, table|
      db_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name)
      next unless db_config

      schema_path = Rails.root.join("db/#{name}_schema.rb")
      next unless schema_path.exist?

      ActiveRecord::Base.establish_connection(db_config)
      if ActiveRecord::Base.connection.table_exists?(table)
        puts "solid:#{name} ok"
      else
        ActiveRecord::Schema.verbose = false
        load schema_path
        puts "solid:#{name} loaded #{schema_path.basename}"
      end
    ensure
      ActiveRecord::Base.establish_connection(Rails.env.to_sym)
    end
  end
end
