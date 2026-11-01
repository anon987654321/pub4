# frozen_string_literal: true

require File.expand_path("../../../__shared/config/environments/development.rb", __dir__)

# Use the dedicated queue database in development as well as production.
# Without this connection Solid Queue falls back to the primary database,
# making local job and recurring-scheduler behaviour differ from the deployed app.
Rails.application.configure do
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
end
