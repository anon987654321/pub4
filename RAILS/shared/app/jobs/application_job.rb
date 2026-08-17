# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Run this job in the caller's process instead of enqueuing it.
  #
  # Nothing on vm23 runs the queue. Solid Queue needs its own process, none is
  # registered, and no job has ever executed: brgen had 1670 rows enqueued and
  # 0 finished when that was first measured. `perform_later` there does not mean
  # "soon", it means "never", and the twelve job classes reached from live
  # request paths are twelve features that look like they work.
  #
  # Most of them can wait for that to be settled — a blurhash arrives late, a
  # fediverse post does not federate. Password reset cannot. The controller says
  # "we sent you an email", no email is ever sent, and the account is gone. So
  # the jobs already marked `queue_as :critical` — the code had named them
  # before anyone noticed nothing ran — run here and now.
  #
  # This is affordable precisely because those jobs are mail, and mail goes to
  # smtpd on 127.0.0.1:25. The request pays a local handoff, not a network round
  # trip. Do not reach for this for anything that renders media or calls an API.
  #
  # Two behaviours come with it, both deliberate:
  #
  # - Errors are logged, not raised. `raise_delivery_errors = true` in
  #   production would otherwise turn a mail failure into a 500 on the
  #   password-reset form, which both breaks the page and tells an attacker the
  #   address exists. The neutral notice is the correct response either way.
  # - The inherited `retry_on StandardError, wait: :polynomially_longer` is
  #   overridden. Inline, that waits inside the request: three attempts would
  #   hold the connection open for twenty seconds before answering.
  #
  # When a worker exists, delete the `run_inline!` calls. Nothing else changes.
  def self.run_inline!
    return unless ENV.fetch("RUN_JOBS_INLINE", "true") == "true"

    self.queue_adapter = :inline

    # Registered after retry_on, and ActiveSupport::Rescuable checks handlers in
    # reverse order of definition, so this one wins for these classes only.
    rescue_from(StandardError) do |error|
      Rails.logger.error("#{self.class.name} failed inline: #{error.class}: #{error.message}")
    end
  end
end
