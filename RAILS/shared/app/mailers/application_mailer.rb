# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  # smtpd DKIM-signs brgen.no only. A localhost From is rejected or junked;
  # every auth mailer inherits this. Override with MAIL_FROM in /etc/<app>.env
  # if a different mailbox is wanted; keep the domain brgen.no or DKIM breaks.
  default from: -> { ENV.fetch("MAIL_FROM", "Brgen <no-reply@brgen.no>") }
  layout "mailer"
end
