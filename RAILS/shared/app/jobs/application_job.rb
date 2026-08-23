# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Retry what a second attempt can fix, and only that. `retry_on StandardError`
  # covered every exception a job can raise, so a typo, a validation failure or
  # a bad remote payload became three delayed copies of the same exception with
  # polynomial backoff between them — the bug arrives later and three times over
  # instead of once. ComposeNewsletterEditionJob is the worked example: it
  # raised AssociationNotFoundError on a name that does not exist, and every
  # scheduled run spent three attempts proving that again.
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3
  retry_on ActiveRecord::LockWaitTimeout, wait: 2.seconds, attempts: 3
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 5.seconds, attempts: 3
  retry_on Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, wait: 5.seconds, attempts: 3

  # The record the job was serialized against is gone. Retrying cannot bring it
  # back, and the work no longer has a subject.
  discard_on ActiveJob::DeserializationError

  # Run this job in the caller's process instead of enqueuing it.
  #
  # Only brgen runs a queue. `rc.d/brgen_jobs` is enabled and its supervisor,
  # scheduler, worker and dispatcher are up; amber and bsdports have no worker
  # registered, so `perform_later` in those two still means "never". Password
  # reset cannot wait on that: the controller says "we sent you an email", no
  # email is ever sent, and the account is gone. So the jobs marked
  # `queue_as :critical` run here and now, in every app.
  #
  # Keeping this on brgen too is deliberate. A worker that exists can still be
  # shed — vps-deploy stops it for the duration of CI because vm23 is 1 GB — and
  # a password reset must not depend on which minute of a deploy it arrives in.
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
  # - Nothing retries. The `retry_on` list above waits between attempts, and
  #   inline that wait happens inside the request — a mail timeout would hold
  #   the connection open for fifteen seconds before answering.
  #
  # Delete the `run_inline!` calls once every app has a worker that survives a
  # deploy. Nothing else changes.
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
