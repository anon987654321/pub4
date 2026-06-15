# frozen_string_literal: true

# AN201: Rails 8 authentication baseline (resume_session, has_secure_password, Session model).
# Guest users when +guest+ column exists (brgen family). Single engine source — apps alias `Authentication`.
module Shared
  module Authentication
    extend ActiveSupport::Concern

    included do
      before_action :resume_session
      helper_method :authenticated?, :current_user, :guest?
    end

    class_methods do
      def allow_unauthenticated_access(**options)
        skip_before_action :resume_session, **options
      end
    end

    private

    def authenticated?
      Current.user.present? && !guest?
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
        ip_address: request.remote_ip
      )
      Current.user = user
      cookies.signed.permanent[:session_id] = { value: Current.session.id, httponly: true, same_site: :lax }
    end

    def terminate_session
      Current.session&.destroy
      cookies.delete(:session_id)
      reset_session
      Current.session = nil
      Current.user = find_or_create_guest_user
    end

    def after_authentication_url
      root_path
    end

    def require_real_user
      return if authenticated?

      redirect_to new_session_path, alert: "Sign in to continue"
    end

    def require_user_session
      return if Current.user.present?

      redirect_to new_session_path, alert: "Sign in to continue"
    end

    alias_method :require_authentication, :resume_session

    def find_session_by_cookie
      ::Session.find_by(id: cookies.signed[:session_id])
    end

    def supports_guests?
      ::User.column_names.include?("guest")
    end

    def find_or_create_guest_user
      return anonymous_user unless supports_guests?

      guest_id = session[:guest_user_id]
      return create_guest_user unless guest_id

      ::User.find_by(id: guest_id, guest: true) || create_guest_user
    end

    def anonymous_user
      ::User.order(:id).first || raise(ActiveRecord::RecordNotFound, "No users — run db:seed")
    end

    def create_guest_user
      guest = ::User.create!(
        email_address: "guest_#{SecureRandom.hex(8)}@guest.local",
        password: SecureRandom.hex(16),
        guest: true
      )
      session[:guest_user_id] = guest.id
      guest
    end
  end
end