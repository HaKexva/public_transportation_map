# frozen_string_literal: true

class CreateBusFleetTables < ActiveRecord::Migration[8.1]
  def change
    create_table :bus_vehicles do |t|
      t.string :plate, null: false
      t.string :city_id
      t.string :operator_id
      t.integer :vehicle_class
      t.integer :vehicle_type
      t.boolean :low_floor, null: false, default: false
      t.boolean :electric, null: false, default: false
      t.boolean :hybrid, null: false, default: false
      t.boolean :ramp, null: false, default: false
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :bus_vehicles, :plate, unique: true

    create_table :bus_route_vehicle_sightings do |t|
      t.string :route_id, null: false
      t.string :plate, null: false
      t.integer :sightings, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
    end
    add_index :bus_route_vehicle_sightings, [ :route_id, :plate ], unique: true
    add_index :bus_route_vehicle_sightings, :last_seen_at
  end
end
