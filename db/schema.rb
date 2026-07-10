# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_10_130500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "headway_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.time "ends_at", null: false
    t.time "first_departure"
    t.integer "interval_seconds", null: false
    t.time "last_departure"
    t.text "notes"
    t.bigint "schedule_dataset_id", null: false
    t.bigint "service_calendar_id", null: false
    t.time "starts_at", null: false
    t.bigint "transit_route_id", null: false
    t.datetime "updated_at", null: false
    t.index ["schedule_dataset_id", "transit_route_id", "direction"], name: "idx_on_schedule_dataset_id_transit_route_id_directi_3ada556cad"
    t.index ["schedule_dataset_id"], name: "index_headway_rules_on_schedule_dataset_id"
    t.index ["service_calendar_id"], name: "index_headway_rules_on_service_calendar_id"
    t.index ["transit_route_id"], name: "index_headway_rules_on_transit_route_id"
  end

  create_table "schedule_datasets", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "imported_at"
    t.string "name", null: false
    t.text "notes"
    t.string "source", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.date "valid_from"
    t.date "valid_to"
    t.index ["active"], name: "index_schedule_datasets_on_active"
  end

  create_table "schedule_trips", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "destination_name"
    t.string "direction", null: false
    t.text "notes"
    t.bigint "schedule_dataset_id", null: false
    t.bigint "service_calendar_id", null: false
    t.string "train_number"
    t.bigint "transit_route_id", null: false
    t.string "trip_type"
    t.datetime "updated_at", null: false
    t.index ["schedule_dataset_id", "transit_route_id", "direction"], name: "idx_on_schedule_dataset_id_transit_route_id_directi_23225f2369"
    t.index ["schedule_dataset_id"], name: "index_schedule_trips_on_schedule_dataset_id"
    t.index ["service_calendar_id"], name: "index_schedule_trips_on_service_calendar_id"
    t.index ["train_number"], name: "index_schedule_trips_on_train_number"
    t.index ["transit_route_id"], name: "index_schedule_trips_on_transit_route_id"
  end

  create_table "service_calendars", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "schedule_dataset_id", null: false
    t.datetime "updated_at", null: false
    t.index ["schedule_dataset_id", "code"], name: "index_service_calendars_on_schedule_dataset_id_and_code", unique: true
    t.index ["schedule_dataset_id"], name: "index_service_calendars_on_schedule_dataset_id"
  end

  create_table "transit_route_stations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "direction", default: "both", null: false
    t.string "name", null: false
    t.string "name_en"
    t.string "station_ref", null: false
    t.integer "stop_sequence", null: false
    t.bigint "transit_route_id", null: false
    t.datetime "updated_at", null: false
    t.index ["transit_route_id", "direction", "station_ref"], name: "index_transit_route_stations_on_route_direction_ref", unique: true
    t.index ["transit_route_id", "direction", "stop_sequence"], name: "index_transit_route_stations_on_route_direction_sequence", unique: true
    t.index ["transit_route_id"], name: "index_transit_route_stations_on_transit_route_id"
  end

  create_table "transit_routes", force: :cascade do |t|
    t.string "branch_of_route_id"
    t.string "color"
    t.datetime "created_at", null: false
    t.string "geojson_path"
    t.string "line_ref", null: false
    t.string "name", null: false
    t.string "name_en"
    t.string "route_id", null: false
    t.string "system_id", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_of_route_id"], name: "index_transit_routes_on_branch_of_route_id"
    t.index ["system_id", "route_id"], name: "index_transit_routes_on_system_id_and_route_id", unique: true
  end

  create_table "trip_stop_times", force: :cascade do |t|
    t.time "arrival_time"
    t.datetime "created_at", null: false
    t.time "departure_time"
    t.string "drop_off_type", default: "regular", null: false
    t.string "pickup_type", default: "regular", null: false
    t.bigint "schedule_trip_id", null: false
    t.string "station_ref", null: false
    t.integer "stop_sequence", null: false
    t.datetime "updated_at", null: false
    t.index ["schedule_trip_id", "station_ref"], name: "index_trip_stop_times_on_schedule_trip_id_and_station_ref", unique: true
    t.index ["schedule_trip_id", "stop_sequence"], name: "index_trip_stop_times_on_schedule_trip_id_and_stop_sequence", unique: true
    t.index ["schedule_trip_id"], name: "index_trip_stop_times_on_schedule_trip_id"
  end

  add_foreign_key "headway_rules", "schedule_datasets"
  add_foreign_key "headway_rules", "service_calendars"
  add_foreign_key "headway_rules", "transit_routes"
  add_foreign_key "schedule_trips", "schedule_datasets"
  add_foreign_key "schedule_trips", "service_calendars"
  add_foreign_key "schedule_trips", "transit_routes"
  add_foreign_key "service_calendars", "schedule_datasets"
  add_foreign_key "transit_route_stations", "transit_routes"
  add_foreign_key "trip_stop_times", "schedule_trips"
end
