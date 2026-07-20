# frozen_string_literal: true

module Shared
  class AnonymousPost
    LIMIT = 2

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

      [LIMIT - quota.post_count, 0].max
    end

    private

    def guest?
      return @user.guest? if @user.respond_to?(:guest?)

      @user.respond_to?(:guest) && @user.guest
    end

    def fingerprint
      cookie = @request.cookie_jar.signed[:browser_fingerprint]
      return cookie if cookie.present?

      Digest::SHA256.hexdigest([@request.user_agent, @request.headers["Accept-Language"]].compact.join("|"))
    end

    def quota
      @quota ||= AnonymousPostQuota.find_or_create_by!(fingerprint: fingerprint)
    end
  end
end
