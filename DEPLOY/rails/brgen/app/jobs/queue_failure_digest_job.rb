# frozen_string_literal: true

class QueueFailureDigestJob < ApplicationJob
  queue_as :bulk

  ADMIN_EMAIL = ENV.fetch("BRGEN_ADMIN_EMAIL", "admin@brgen.no")

  def perform
    rows = failed_execution_rows
    return if rows.empty?

    body = Shared::QueueFailureSummary.call(rows, app: "brgen")
    QueueFailureMailer.daily_digest(body, to: ADMIN_EMAIL).deliver_now
    Shared::EventEmitter.call("brgen.queue.dead_letter_digest", body:) if defined?(Shared::EventEmitter)
  end

  private

  def failed_execution_rows
    connection = queue_connection
    sql = <<~SQL
      SELECT j.class_name, j.queue_name, COUNT(*) AS failures, MAX(f.created_at) AS last_failed_at
      FROM solid_queue_failed_executions f
      JOIN solid_queue_jobs j ON j.id = f.job_id
      GROUP BY j.class_name, j.queue_name
      ORDER BY failures DESC, last_failed_at DESC
    SQL
    connection.exec_query(sql).to_a.map { |row| row.transform_keys(&:to_sym) }
  rescue StandardError
    []
  end

  def queue_connection
    if defined?(SolidQueue::Job) && SolidQueue::Job.respond_to?(:connection)
      SolidQueue::Job.connection
    else
      ActiveRecord::Base.connection
    end
  end
end
