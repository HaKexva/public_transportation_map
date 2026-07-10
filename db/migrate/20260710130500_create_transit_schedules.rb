# frozen_string_literal: true

class CreateTransitSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :transit_routes do |t|
      t.string :system_id, null: false
      t.string :route_id, null: false
      t.string :name, null: false
      t.string :name_en
      t.string :line_ref, null: false
      t.string :color
      t.string :branch_of_route_id
      t.string :geojson_path

      t.timestamps
    end

    add_index :transit_routes, %i[system_id route_id], unique: true
    add_index :transit_routes, :branch_of_route_id

    create_table :transit_route_stations do |t|
      t.references :transit_route, null: false, foreign_key: true
      t.string :station_ref, null: false
      t.string :name, null: false
      t.string :name_en
      t.integer :stop_sequence, null: false
      t.string :direction, null: false, default: "both"

      t.timestamps
    end

    add_index :transit_route_stations,
              %i[transit_route_id direction station_ref],
              unique: true,
              name: "index_transit_route_stations_on_route_direction_ref"
    add_index :transit_route_stations,
              %i[transit_route_id direction stop_sequence],
              unique: true,
              name: "index_transit_route_stations_on_route_direction_sequence"

    create_table :schedule_datasets do |t|
      t.string :name, null: false
      t.string :source, null: false, default: "manual"
      t.date :valid_from
      t.date :valid_to
      t.boolean :active, null: false, default: false
      t.text :notes
      t.datetime :imported_at

      t.timestamps
    end

    add_index :schedule_datasets, :active

    create_table :service_calendars do |t|
      t.references :schedule_dataset, null: false, foreign_key: true
      t.string :code, null: false
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    add_index :service_calendars, %i[schedule_dataset_id code], unique: true

    create_table :schedule_trips do |t|
      t.references :schedule_dataset, null: false, foreign_key: true
      t.references :transit_route, null: false, foreign_key: true
      t.references :service_calendar, null: false, foreign_key: true
      t.string :direction, null: false
      t.string :train_number
      t.string :trip_type
      t.string :destination_name
      t.text :notes

      t.timestamps
    end

    add_index :schedule_trips, %i[schedule_dataset_id transit_route_id direction]
    add_index :schedule_trips, :train_number

    create_table :trip_stop_times do |t|
      t.references :schedule_trip, null: false, foreign_key: true
      t.string :station_ref, null: false
      t.integer :stop_sequence, null: false
      t.time :arrival_time
      t.time :departure_time
      t.string :pickup_type, null: false, default: "regular"
      t.string :drop_off_type, null: false, default: "regular"

      t.timestamps
    end

    add_index :trip_stop_times, %i[schedule_trip_id stop_sequence], unique: true
    add_index :trip_stop_times, %i[schedule_trip_id station_ref], unique: true

    create_table :headway_rules do |t|
      t.references :schedule_dataset, null: false, foreign_key: true
      t.references :transit_route, null: false, foreign_key: true
      t.references :service_calendar, null: false, foreign_key: true
      t.string :direction, null: false
      t.time :starts_at, null: false
      t.time :ends_at, null: false
      t.integer :interval_seconds, null: false
      t.time :first_departure
      t.time :last_departure
      t.text :notes

      t.timestamps
    end

    add_index :headway_rules, %i[schedule_dataset_id transit_route_id direction]
  end
end
