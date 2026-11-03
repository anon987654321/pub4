# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :current_user, :current_cart, :cart_count, :cart_subtotal_ore, :current_kitchen

  before_action :set_locale

  rescue_from ActiveRecord::RecordNotFound, with: :redirect_to_root_on_missing_record

  private

  # Norwegian first; ?locale=en flips to the English mirror (APP_SPEC §6/§10).
  def set_locale
    requested = params[:locale].to_s.to_sym
    I18n.locale = I18n.available_locales.include?(requested) ? requested : I18n.default_locale
  end

  # Phone-number auth: the signed, permanent cookie holds the Session token.
  def current_user
    return @current_user if defined?(@current_user)

    token = cookies.signed[:session_token]
    @current_user = token.present? ? Session.find_by(token: token)&.user : nil
  end

  # One open cart per identity (APP_SPEC §4): keyed by user when signed in,
  # else by the anonymous browser session.
  def current_cart
    return @current_cart if defined?(@current_cart)

    @current_cart = Cart.for(current_user, cart_session_key)
  end

  # Badge count for the tab bar + pay-bar — rendered app-wide from the layout,
  # so the aggregation lives here, not in a view.
  def cart_count
    current_cart.cart_items.sum(:quantity)
  end

  def cart_subtotal_ore
    current_cart.subtotal_ore
  end

  # The one kitchen's record is the only home of its address and opening
  # hours; the footer reads it rather than keeping a copy in the locales.
  def current_kitchen
    return @current_kitchen if defined?(@current_kitchen)

    @current_kitchen = Kitchen.first
  end

  # Cookie-store sessions may not expose an id before their first write, so we
  # fall back to a random key persisted in the session cookie itself — Cart.for
  # needs a stable, non-blank identity for anonymous baskets.
  def cart_session_key
    session.id.to_s.presence || (session[:cart_key] ||= SecureRandom.hex(16))
  end

  # Staff board + courier runs gate on roles; admin may always step in.
  def require_role!(role)
    return if current_user && (current_user.public_send("#{role}?") || current_user.admin?)

    redirect_to root_path, alert: t("auth.not_authorized")
  end

  def redirect_to_root_on_missing_record
    redirect_to root_path, alert: t("flash.not_found")
  end
end
