# frozen_string_literal: true

module Shared
  # A burst ceiling on every write, so no create, update or destroy in any app
  # is unlimited by omission.
  #
  # Per-action rate_limit declarations stay where a controller needs a tighter
  # or a named limit (posts, messages, uploads, sign-in). This is the floor under
  # all of them: 120 writes a minute to one controller from one identity is far
  # above a person and useful only to a script. Guests count by IP, because a
  # client that drops its cookie mints a new guest on every POST and would
  # otherwise never repeat a key.
  #
  # A controller whose legitimate traffic is burstier raises its own ceiling with
  # `self.write_throttle_limit = n`; one whose callers are servers with their own
  # limit (the fediverse inbox) opts out with `skip_write_throttle`. Controllers
  # outside ApplicationSetup — webhooks, browser report beacons — include it
  # themselves and count by IP.
  module WriteThrottle
    extend ActiveSupport::Concern

    included do
      class_attribute :write_throttle_limit, default: 120
      class_attribute :write_throttle_window, default: 1.minute
      before_action :throttle_writes, unless: :write_throttle_exempt?
    end

    class_methods do
      def skip_write_throttle
        self.write_throttle_limit = nil
      end
    end

    private

    def write_throttle_exempt?
      write_throttle_limit.nil? || request.get? || request.head?
    end

    def throttle_writes
      key = [ "write-throttle", controller_path, write_throttle_identity ].join(":")
      count = Rails.cache.increment(key, 1, expires_in: write_throttle_window)
      return unless count && count > write_throttle_limit

      ActiveSupport::Notifications.instrument("write_throttle.shared", controller: controller_path, count:)
      if request.format.html? && respond_to?(:flash, true)
        redirect_back_or_to "/", alert: t("shared.flash.rate_limited")
      else
        head :too_many_requests
      end
    end

    def write_throttle_identity
      user = Current.user if defined?(Current) && Current.respond_to?(:user)
      return "u#{user.id}" if user&.id && !(user.respond_to?(:guest?) && user.guest?)

      request.remote_ip
    end
  end
end
