# frozen_string_literal: true

class QueueFailureMailer < ApplicationMailer
  def daily_digest(body, to:)
    mail(to:, subject: t("mailer.queue_failure_digest_subject"), body:)
  end
end
