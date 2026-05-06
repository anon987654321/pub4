module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :resume_session
    helper_method :authenticated?, :current_user
  end

  class_methods do
    # Rails 8 compat: controllers can declare they don't need auth enforcement
    def allow_unauthenticated_access(**options)
      skip_before_action :resume_session, **options rescue nil
    end
  end

  private

  def authenticated?
    Current.user.present? && !Current.user.guest?
  end

  def current_user
    Current.user
  end

  def resume_session
    Current.session = find_session_by_cookie
    if Current.session
      Current.user = Current.session.user
    else
      Current.user = find_or_create_guest_user
    end
  end

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:session_id])
  end

  def find_or_create_guest_user
    guest_id = session[:guest_user_id]
    if guest_id
      User.find_by(id: guest_id, guest: true) || create_guest_user
    else
      create_guest_user
    end
  end

  def create_guest_user
    guest = User.create!(
      email_address: "guest_#{SecureRandom.hex(8)}@guest.local",
      password: SecureRandom.hex(16),
      guest: true
    )
    session[:guest_user_id] = guest.id
    guest
  end

  def require_real_user
    unless authenticated?
      redirect_to new_session_path, alert: "Sign in to continue"
    end
  end

  # Rails 8 compat alias
  alias_method :require_authentication, :resume_session
end
