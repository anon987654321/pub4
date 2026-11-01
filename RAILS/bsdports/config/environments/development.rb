# frozen_string_literal: true

require File.expand_path("../../../__shared/config/environments/development.rb", __dir__)

Rails.application.configure do
  # Keep development on the same dedicated SQLite queue database as production.
  # Without this, local jobs do not exercise the queue database declared in
  # config/database.yml.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
end
