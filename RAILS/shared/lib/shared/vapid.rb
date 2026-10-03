# frozen_string_literal: true

module Shared
  module Vapid
    module_function

    # The contact a push service writes to about this app's pushes. Each app has
    # its own env file, so VAPID_SUBJECT is per app; unset, it is admin@ the
    # app's own mail host, because bsdports.org pushes signed as brgen.no point
    # the push service at the wrong operator.
    def subject(mail_host = default_mail_host)
      value = ENV["VAPID_SUBJECT"].to_s.strip
      value = "admin@#{mail_host}" if value.empty?
      value.match?(/\A(mailto|https):/) ? value : "mailto:#{value}"
    end

    def default_mail_host
      options = defined?(Rails) && Rails.respond_to?(:application) && Rails.application &&
                Rails.application.config.action_mailer.default_url_options
      host = options ? options[:host].to_s : ""
      host.empty? ? "brgen.no" : host
    end

    def public_key
      ENV.fetch("VAPID_PUBLIC_KEY", "")
    end

    def private_key
      ENV.fetch("VAPID_PRIVATE_KEY", "")
    end

    def configured?
      !public_key.empty? && !private_key.empty?
    end

    def webpush_options
      return {} unless configured?

      { subject:, public_key:, private_key: }
    end
  end
end
