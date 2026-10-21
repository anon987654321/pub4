# frozen_string_literal: true

module Shared
  # Shared email-registration policy. Each host keeps its own account model and
  # guest-history behavior, while validation, verification and email delivery stay
  # one contract. Marketing consent is deliberately absent from account creation.
  module EmailRegistration
    extend ActiveSupport::Concern

    private

    def signup_terms_accepted?
      params[:accept_terms] == "1" && params[:accept_age] == "1"
    end

    def prepare_email_registration(attributes)
      @user = User.new(attributes)
      @user.guest = false if @user.has_attribute?(:guest)
      @user.require_email_verification = true
      @user
    end

    def send_signup_verification!(user)
      user.generate_email_verification!
      Shared::VerificationMailer.verify(user, request.host).deliver_later
    end

    def render_signup_terms_error(attributes)
      @user = User.new(attributes)
      @user.errors.add(:base, t("legal.accept_terms"))
      render :new, status: :unprocessable_entity
    end
  end
end
