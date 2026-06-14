# frozen_string_literal: true

class QueueFailureMailer < ApplicationMailer
  def daily_digest(body, to:)
    mail(to:, subject: "Brgen queue dead letter digest", body:)
  end
end
