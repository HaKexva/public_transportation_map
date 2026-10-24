# frozen_string_literal: true

# TDX bus Schedule / Route / RouteFare rows for one RouteName, refreshed daily
# by Transit::RefreshBusSnapshotJob (see Transit::BusTdxSnapshot).
class BusRouteTimetable < ApplicationRecord
end
