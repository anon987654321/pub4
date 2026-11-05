# frozen_string_literal: true

# One notification as an email, for the kinds a person turned email on for on
# the account page. It says what happened and links to it, and to the page
# where the choice is changed.
class NotificationMailer < ApplicationMailer
  # brgen.no is the one domain with working mail (see EmailSubscriptionMailer).
  default from: "Brgen <letters@brgen.no>"

  def notice(notification)
    @notification = notification
    host = ENV.fetch("APP_HOST", "brgen.no")
    @open_url = "https://#{host}#{notification.push_path}"
    @preferences_url = account_url(host:, protocol: "https")
    reader = notification.user
    I18n.with_locale(reader.locale.presence || I18n.default_locale) do
      mail to: reader.email_address, subject: notification.title
    end
  end
end
