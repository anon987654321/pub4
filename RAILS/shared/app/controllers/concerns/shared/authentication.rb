# frozen_string_literal: true

require "bcrypt"

# AN201: Rails 8 authentication baseline (resume_session, has_secure_password, Session model).
# Guest users when +guest+ column exists (brgen family). Single engine source — apps alias `Authentication`.
module Shared
  module Authentication
    extend ActiveSupport::Concern

    included do
      before_action :resume_session
      # A request that is not a GET intends to write something, and writing needs
      # an id. The three GET actions that also write call ensure_guest_user!
      # themselves.
      before_action :ensure_guest_user!, unless: :read_only_request?
      after_action :remember_persisted_guest
      helper_method :authenticated?, :current_user, :guest?
    end

    class_methods do
      # Public pages still run resume_session when guests are supported so
      # anonymous visitors get a soft Current.user (Craigslist-style: use the
      # product without signup). require_real_user remains the identity gate.
      def allow_unauthenticated_access(**options)
        if ::User.column_names.include?("guest")
          # It reads like a control and does nothing here: guests already get a soft
          # Current.user, so skipping resume_session would only deny them one. Say so
          # where the author is — dev and test — so it is not a silent no-op; stay
          # quiet in production, where it would be boot noise on every controller.
          if defined?(Rails) && (Rails.env.development? || Rails.env.test?)
            Rails.logger&.warn("[auth] allow_unauthenticated_access is a no-op in #{name}: " \
                               "guests get a soft Current.user by design — gate identity-bound " \
                               "actions with require_real_user instead.")
          end
          return
        end

        skip_before_action :resume_session, **options
      end
    end

    private

    def authenticated?
      return Current.user.present? && !guest? if supports_guests?

      Current.session.present?
    end

    def guest?
      supports_guests? && Current.user&.guest?
    end

    def current_user
      Current.user
    end

    def resume_session
      Current.session = find_session_by_cookie
      Current.user = Current.session&.user || find_or_create_guest_user
    end

    def start_new_session_for(user)
      previous_guest_id = session[:guest_user_id]
      reset_session
      session[:previous_guest_user_id] = previous_guest_id if previous_guest_id

      Current.session = user.sessions.create!(
        user_agent: request.user_agent,
        ip_address: request.remote_ip,
      )
      Current.user = user
      # domain: :all for the same reason as the session cookie (see
      # shared/config/initializers/session_store.rb): the verticals are
      # subdomains, and a host-only cookie signed you out on the way to them.
      cookies.signed.permanent[:session_id] = {
        value: Current.session.id, httponly: true, same_site: :lax, domain: :all
      }
    end

    def terminate_session
      Current.session&.destroy
      # Same domain as it was written with, or the browser keeps the old one
      # and sign-out silently does nothing on the next request.
      cookies.delete(:session_id, domain: :all)
      reset_session
      Current.session = nil
      Current.user = find_or_create_guest_user
    end

    def after_authentication_url
      root_path
    end

    # Sessions live in the main application's router. `new_session_path` on its
    # own resolves against whichever route set is in scope, which inside a
    # mounted engine is the engine's — and no engine has a sessions route. So a
    # guest reaching any guarded action on a vertical got
    #
    #   ActionController::UrlGenerationError (No route matches
    #     {action: "new", controller: "sessions"})
    #
    # which is a 500 where a sign-in redirect belonged. Two callers had already
    # worked around it one at a time with `main_app.new_session_path`
    # (takeaway/reviews, application_helper); this is the cause they were
    # working around. Resolving against Rails.application works from both an
    # engine and the main app, where `main_app` is not defined.
    def sign_in_path
      Rails.application.routes.url_helpers.new_session_path
    end

    # Real account only (email/password session). Identity-bound actions:
    # permanent profile edits, ownership admin, account settings.
    def require_real_user
      return if authenticated?

      redirect_to sign_in_path, alert: t("shared.flash.sign_in_required")
    end

    # Any usable identity including soft guests. Core product actions
    # (post, message, list, swipe, cart) use this — no signup required.
    def require_user_session
      return if Current.user.present?

      redirect_to sign_in_path, alert: t("shared.flash.sign_in_required")
    end

    def require_authentication
      require_real_user
    end

    def find_session_by_cookie
      ::Session.includes(:user).find_by(id: cookies.signed[:session_id])
    end

    def supports_guests?
      ::User.column_names.include?("guest")
    end

    # A row per uncookied request, and almost none of them are anybody.
    #
    # Measured on production 2026-08-14: brgen writes 10,461 guest rows a day.
    # Of the 10,463 created in the preceding 24 hours, ZERO had a session row
    # and ONE had authored a post. The table holds 206,497 guests against 719
    # real users, and 146,885 of them are old enough to prune.
    #
    # This is the other half of the finding recorded at GUEST_BCRYPT_COST below.
    # That pass measured what each row COST — 1,025 ms of BCrypt on every
    # uncookied request — fixed the cost, and noted in passing that it "had also
    # written 102,778 throwaway guest rows". The rows kept being written and the
    # count has doubled since.
    #
    # OPENBSD/etc/daily.local prunes about 20,000 a night against 10,000
    # arriving, so the table stays bounded. That is the mitigation. This is the
    # fix: nothing is written until something is on the other end.
    #
    # The first uncookied request gets an UNSAVED ::User. It answers every read a
    # view or a policy makes — display_name, guest?, empty associations — and its
    # nil id makes the rate limiters fall back to their IP bucket, which is the
    # right bucket for a visitor with no identity yet. A marker goes in the
    # session at the same time; a browser that keeps cookies returns it on the
    # next request, and that is the evidence worth a row. A crawler that discards
    # cookies never comes back and never costs anything.
    #
    # Real browsers are persisted almost immediately and nothing about the
    # product changes for them: the page they land on fetches the ambient chat
    # frame, and that fetch is a second HTTP request carrying the cookie the
    # first response just set.
    #
    # What needed care is the handful of places that need an id rather than a
    # user — Conversation#join!, mark_read_for!, anything building a row with a
    # foreign key. ensure_guest_user! covers them, wired as a before_action for
    # every non-GET and called explicitly by the three GET actions that write.
    #
    # Measured before and after on the same numbers this comment quotes, so the
    # claim is checkable: guest rows per day, and participant rows per day as the
    # control that the chat path is unaffected.
    def find_or_create_guest_user
      return nil unless supports_guests?

      guest_id = session[:guest_user_id]
      if guest_id
        found = ::User.find_by(id: guest_id, guest: true)
        return found if found
      end

      # Second sighting: the cookie came back, so there is a browser here.
      return create_guest_user if session[:guest_pending]

      session[:guest_pending] = true
      build_guest_user
    end

    # Persist the soft guest, for callers that need an id rather than a user.
    #
    # A GET that writes a row is the interesting case and there are three of
    # them: the ambient chat widget and the geo room both join the visitor to a
    # conversation, and a channel page seeds and joins. They call this directly.
    # Everything else is covered by the before_action, on the rule that a request
    # which is not a GET is a request that intends to write something.
    #
    # Idempotent, and a no-op for real users and already-saved guests.
    def ensure_guest_user!
      user = Current.user
      return user unless user&.new_record?

      user.save!
      session.delete(:guest_pending)
      session[:guest_user_id] = user.id
      user
    end

    def read_only_request?
      request.get? || request.head?
    end

    # An unsaved guest that a write persisted on its own has to be remembered, or
    # the next request builds a fresh one and the author loses what they just
    # wrote. `user: Current.user` is how every create site here attaches the
    # actor, and ActiveRecord saves an unsaved belongs_to target before saving
    # the owner — so this fires even where ensure_guest_user! was never called.
    def remember_persisted_guest
      return unless supports_guests?

      user = Current.user
      return unless user&.persisted? && user.guest?
      return if session[:guest_user_id] == user.id

      session.delete(:guest_pending)
      session[:guest_user_id] = user.id
    end

    # A guest's password exists only to satisfy has_secure_password. It is random,
    # never shown to anyone, and can never be used to sign in — `authenticated?`
    # is false for guests by definition, and the address is guest_*@guest.local.
    #
    # Assigning it through `password=` hashed it at BCrypt::Engine.cost, which is
    # 12 in production and measures 1,025 ms on vm23's single core. Every request
    # without a session cookie paid that: crawlers, uptime probes, robots.txt,
    # manifest.json, every asset fetched without credentials. Measured 2026-08-01
    # on 275,334 logged brgen requests — 38.9% of them landed in one 900-1100 ms
    # bucket, and the same endpoint answered in 18-24 ms once a cookie existed.
    # It had also written 102,778 throwaway guest rows, 99.3% of the users table.
    #
    # Cost 4 (BCrypt's minimum) takes 5 ms and is exactly as unusable. Real
    # passwords are untouched — this bypasses the setter for guests only, and any
    # guest that later becomes a real account gets a full-cost digest then.
    GUEST_BCRYPT_COST = BCrypt::Engine::MIN_COST

    def build_guest_user
      guest = ::User.new(
        email_address: "guest_#{SecureRandom.hex(8)}@guest.local",
        guest: true,
      )
      guest.password_digest = BCrypt::Password.create(SecureRandom.hex(16), cost: GUEST_BCRYPT_COST)
      guest
    end

    def create_guest_user
      guest = build_guest_user
      guest.save!
      session.delete(:guest_pending)
      session[:guest_user_id] = guest.id
      guest
    end
  end
end
