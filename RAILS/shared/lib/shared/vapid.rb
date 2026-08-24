# frozen_string_literal: true

module Shared
  module Vapid
    module_function

    def subject
      "mailto:#{ENV.fetch("VAPID_SUBJECT", "admin@brgen.no")}"
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
