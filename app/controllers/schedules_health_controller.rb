# frozen_string_literal: true

class SchedulesHealthController < ActionController::Base
  # The weekly timetable is meant to stay in place. This only fails when there
  # is no active dataset at all. /up stays a liveness check.
  def show
    dataset = ScheduleDataset.tdx.active.order(imported_at: :desc, id: :desc).first
    if dataset
      render plain: "ok", status: :ok
    else
      render plain: "stale schedule dataset (none)", status: :service_unavailable
    end
  end
end
