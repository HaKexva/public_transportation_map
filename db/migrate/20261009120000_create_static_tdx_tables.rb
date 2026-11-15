# frozen_string_literal: true

class CreateStaticTdxTables < ActiveRecord::Migration[8.1]
  def change
    create_table :bus_route_timetables do |t|
      t.string :city_id, null: false
      t.string :route_name, null: false
      t.jsonb :schedules, null: false, default: []
      t.jsonb :routes, null: false, default: []
      t.jsonb :fares, null: false, default: []
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :bus_route_timetables, [ :city_id, :route_name ], unique: true

    create_table :station_infos do |t|
      t.string :system, null: false
      t.string :station_id, null: false
      t.jsonb :exits, null: false, default: []
      t.jsonb :facilities, null: false, default: []
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :station_infos, [ :system, :station_id ], unique: true
  end
end
