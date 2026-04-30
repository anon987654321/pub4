Devise.setup do |config|
  require "devise/orm/active_record"

  config.mailer_sender = "#{I18n.t(:noreply)}@brgen.no"

  config.secret_key = "94bc132b610b69a4cbd9358a8177ce91f32d5d1ed080920805ccde74f1d61744b046c293faaf87bb3cea99449f4eba77eae60e7159e7406f800171cbc9a0d6b4"

  config.authentication_keys = [:username]
  config.case_insensitive_keys = [:username]
  config.strip_whitespace_keys = [:username]

  config.skip_session_storage = [:http_auth]

  config.stretches = Rails.env.test? ? 1 : 10

  config.reconfirmable = true

  config.reset_password_within = 6.hours

  config.sign_out_via = :delete
end

