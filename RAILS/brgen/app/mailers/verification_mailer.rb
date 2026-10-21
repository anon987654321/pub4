# frozen_string_literal: true

# Compatibility entry point retained for existing Brgen mailer callers/tests.
# The body, tokens, URL and translations live in the shared engine.
class VerificationMailer
  def self.verify(user)
    host = Rails.application.routes.default_url_options[:host].presence ||
      Rails.application.config.action_mailer.default_url_options[:host].presence ||
      "brgen.no"
    Shared::VerificationMailer.verify(user, host)
  end
end
