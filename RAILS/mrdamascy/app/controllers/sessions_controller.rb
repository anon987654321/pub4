# frozen_string_literal: true

class SessionsController < ApplicationController
  # Mock OTP — fixed per APP_SPEC §2/§11. No SMS gateway, no extra gem.
  MOCK_CODE = "1234"

  # A requested code is good for this long; an old one left in a shared
  # browser must not sign the next person in.
  CODE_TTL = 5.minutes

  # A fixed code proves nothing, so it may only open accounts while identity
  # itself is mocked: development, test, or the Vipps mock the demo runs.
  # With real Vipps Login live it would let anyone become any customer.
  def self.sms_mocked? = Rails.env.local? || VippsClient.mock_mode?

  # Guessing a code or spraying phone numbers costs a visitor ten tries.
  rate_limit to: 10, within: 10.minutes, only: %i[request_code create], name: "phone_sign_in",
             with: -> { redirect_to new_session_path, alert: t("auth.too_many_attempts") }

  def new
    redirect_to(root_path, notice: t("flash.welcome")) if current_user
  end

  # Mock-SMS: the fixed code is stored in the session for #create; in
  # development the login page shows it as a dev notice (APP_SPEC §6).
  def request_code
    @phone = params[:phone]
    phone = @phone.to_s.gsub(/\D/, "")
    if !phone.match?(/\A\d{8,12}\z/)
      refuse_sign_in(t("auth.phone_invalid"), :unprocessable_entity)
    elsif !self.class.sms_mocked?
      refuse_sign_in(t("auth.sms_unavailable"), :service_unavailable)
    else
      send_code(phone)
    end
  end

  # Verifies the code this session requested for this phone, find-or-creates
  # the user by phone, and drops a signed permanent session cookie. Posting
  # the fixed code for a phone that never asked for one used to sign in as
  # anybody, so the code is bound to the session that requested it.
  def create
    phone = params[:phone].to_s.gsub(/\D/, "")
    if requested_code?(phone, params[:code].to_s.strip)
      sign_in_by_phone(phone)
    else
      # A wrong code keeps the code form, with the phone as typed.
      @phone = params[:phone]
      @code_requested = session[:otp_phone].present?
      refuse_sign_in(t("auth.code_invalid"), :unprocessable_entity)
    end
  end

  # --- "Logg inn med Vipps" (the zero-typing path, APP_SPEC §12) -----------
  #
  # One tap on the checkout: Vipps verifies the phone, gives back the
  # customer's name and (with the address scope) their registered address —
  # so the confirm screen arrives prefilled and "Betal med Vipps" is the
  # only button left to press. No OTP, no forms, no card fields.

  # Start the OAuth2 dance. Mock mode bounces to our own stand-in page
  # instead of Vipps' consent screen; the state check runs in both modes.
  def vipps_auth
    return redirect_to(root_path, notice: t("flash.welcome")) if current_user

    session[:vipps_login_state] = SecureRandom.hex(16)
    if params[:to].present?
      session[:vipps_login_to] = params[:to].to_s
    else
      session.delete(:vipps_login_to) # a stale ?to=checkout must not trap the next login
    end

    if VippsClient.mock_mode?
      redirect_to vipps_login_mock_path(state: session[:vipps_login_state],
                                        to: session[:vipps_login_to].to_s)
    else
      redirect_to VippsClient.login_authorize_url(
        redirect_uri: session_vipps_callback_url,
        state: session[:vipps_login_state],
        nonce: SecureRandom.hex(8)
      ), allow_other_host: true
    end
  end

  # OAuth2 redirect back. Mock mode fakes the code with the phone the mock
  # page posted; real mode exchanges it for a userinfo profile. Both land on
  # the same find-or-create → sign-in → return_to handoff.
  def vipps_callback
    return login_state_mismatch unless valid_login_state?

    profile =
      if VippsClient.mock_mode?
        mock_login_profile
      else
        real_login_profile
      end

    return login_state_mismatch if profile.nil? || profile[:phone].blank?

    begin
      user = User.find_or_create_by!(phone: profile[:phone]) do |fresh|
        fresh.name = profile[:name]
      end
      apply_login_profile!(user, profile)
    rescue ActiveRecord::RecordInvalid
      # A phone outside our 8–12 digit rule (odd foreign numbers) is a login
      # problem, not a 500 — send the visitor back to try the SMS route.
      return login_state_mismatch
    end

    sign_in!(user)
    clear_login_state

    destination = session.delete(:vipps_login_to) == "checkout" ? checkout_path : root_path
    redirect_to destination, notice: t("auth.welcome", name: user.display_name)
  end

  def destroy
    Session.find_by(token: cookies.signed[:session_token])&.destroy
    cookies.delete(:session_token)
    redirect_to root_path, notice: t("flash.logged_out")
  end

  private

  def refuse_sign_in(message, status)
    flash.now[:alert] = message
    render :new, status:
  end

  # The code form follows, with the phone kept editable (sessions/new).
  def send_code(phone)
    remember_code!(phone)
    @code_requested = true
    flash.now[:notice] = Rails.env.development? ? t("auth.mock_code", code: MOCK_CODE) : t("auth.code_sent")
    render :new
  end

  def sign_in_by_phone(phone)
    user = User.find_or_create_by!(phone:) { |fresh| fresh.name = params[:name].presence }
    sign_in!(user)
    session.delete(:otp_phone)
    session.delete(:otp_code)
    session.delete(:otp_sent_at)
    redirect_to root_path, notice: t("flash.welcome")
  end

  # The mock code, bound to the phone and the moment this session asked.
  def remember_code!(phone)
    session[:otp_phone] = phone
    session[:otp_code] = MOCK_CODE
    session[:otp_sent_at] = Time.current.to_i
  end

  # The code this session asked for, for this phone, while identity is mocked.
  def requested_code?(phone, code)
    return false unless self.class.sms_mocked? && phone.match?(/\A\d{8,12}\z/) && code.present?
    return false unless Time.current.to_i - session[:otp_sent_at].to_i <= CODE_TTL

    phone == session[:otp_phone].to_s &&
      ActiveSupport::SecurityUtils.secure_compare(code, session[:otp_code].to_s)
  end

  def valid_login_state?
    params[:state].to_s.present? &&
      ActiveSupport::SecurityUtils.secure_compare(
        params[:state].to_s, session[:vipps_login_state].to_s
      )
  end

  def login_state_mismatch
    clear_login_state
    redirect_to new_session_path, alert: t("auth.login_failed")
  end

  def clear_login_state
    session.delete(:vipps_login_state)
  end

  # Mock profile: the stand-in page supplies phone (+ optional name).
  def mock_login_profile
    phone = params[:phone].to_s.gsub(/\D/, "")
    return nil unless phone.match?(/\A\d{8,12}\z/)

    { phone: phone, name: params[:name].presence, address: nil, postcode: nil }
  end

  # Real profile: code → token → userinfo (verified Vipps data). The phone
  # is normalised to the 8-digit local form so the Vipps identity and the
  # OTP identity are the same customer row.
  def real_login_profile
    tokens = VippsClient.exchange_login_code!(
      code: params[:code].to_s,
      redirect_uri: session_vipps_callback_url
    )
    info = VippsClient.login_userinfo!(access_token: tokens["access_token"])
    address = info["address"].is_a?(Hash) ? info["address"] : {}

    {
      phone: VippsClient.login_phone(info["phone_number"]),
      name: info["name"].presence,
      address: address["formatted"].presence || address["street_address"].presence,
      postcode: address["postal_code"].presence
    }
  rescue VippsClient::NotAvailable
    nil
  end

  # Vipps data is a gift, not an overwrite: fill blanks, never clobber what
  # the customer already typed (their chosen name, their address spelling).
  def apply_login_profile!(user, profile)
    updates = {}
    updates[:name] = profile[:name] if profile[:name].present? && user.name.blank?
    updates[:default_address] = profile[:address] if profile[:address].present? && user.default_address.blank?
    updates[:default_postcode] = profile[:postcode] if profile[:postcode].present? && user.default_postcode.blank?
    user.update!(updates) if updates.any?
  end
end
