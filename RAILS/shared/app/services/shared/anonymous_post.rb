# frozen_string_literal: true

module Shared
  class AnonymousPost
    # Soft guest quota — enough for real use, low enough to slow spray spam.
    # Sign-up removes the cap entirely (allowed? returns true for non-guests).
    LIMIT = 15

    def initialize(request:, user:)
      @request = request
      @user = user
    end

    def allowed?
      return true unless guest?

      quota.post_count < LIMIT
    end

    def record_post!
      return unless guest?

      quota.increment!(:post_count)
    end

    def remaining
      return unless guest?

      [ LIMIT - quota.post_count, 0 ].max
    end

    private

    def guest?
      return @user.guest? if @user.respond_to?(:guest?)

      @user.respond_to?(:guest) && @user.guest
    end

    def fingerprint
      cookie = @request.cookie_jar.signed[:browser_fingerprint]
      return cookie if cookie.present?

      # Fallback for visitors whose browser never ran browser_fingerprint_
      # controller.js. User agent + language alone is not a browser: every
      # no-JS visitor on the same Chrome build and locale shared one 15-post
      # allowance, so one of them could spend everyone else's. Adding the IP
      # narrows it to something closer to a single household.
      traits = [ @request.user_agent, @request.headers["Accept-Language"], @request.remote_ip ]
      Digest::SHA256.hexdigest(traits.compact.join("|"))
    end

    def quota
      @quota ||= AnonymousPostQuota.find_or_create_by!(fingerprint:)
    end
  end
end
