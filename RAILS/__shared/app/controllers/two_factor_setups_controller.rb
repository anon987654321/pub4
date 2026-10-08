# frozen_string_literal: true

# AN207: TOTP two-factor setup and verification

class TwoFactorSetupsController < ::ApplicationController
  include Shared::TwoFactorAuth

  before_action :require_user_session

  def show
    @user = Current.user
    @user.enable_otp! unless @user.otp_secret.present?
    @provisioning_uri = generate_otp_provisioning_uri(@user)
    @qr = build_qr(@provisioning_uri) if @provisioning_uri
  end

  def create
    if verify_totp(Current.user, params[:code].to_s)
      session[:two_factor_verified_at] = Time.current.to_i
      redirect_to account_path, notice: t("shared.flash.two_factor_enabled")
    else
      redirect_to two_factor_setup_path, alert: t("shared.flash.invalid_code")
    end
  end

  def update
    if verify_totp(Current.user, params[:code].to_s)
      Current.user.disable_otp!
      session.delete(:two_factor_verified_at)
      redirect_to account_path, notice: t("shared.flash.two_factor_disabled")
    else
      redirect_to two_factor_setup_path, alert: t("shared.flash.invalid_code")
    end
  end

  def verify
    if verify_totp(Current.user, params[:code].to_s)
      session[:two_factor_verified_at] = Time.current.to_i
      redirect_to after_authentication_url, notice: t("shared.flash.verified")
    else
      redirect_to two_factor_setup_path, alert: t("shared.flash.invalid_code")
    end
  end

  private

  def build_qr(uri)
    return unless defined?(RQRCode::QRCode)

    RQRCode::QRCode.new(uri).as_svg(module_size: 4)
  end
end
