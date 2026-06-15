# frozen_string_literal: true

class EmailSubscriptionsController < ApplicationController
  skip_before_action :require_real_user, raise: false

  def create
    sub = EmailSubscription.find_or_initialize_by(email: params[:email_subscription][:email])
    if sub.new_record?
      sub.city                = params[:email_subscription][:city].presence
      sub.locale              = I18n.locale.to_s
      sub.agreed_to_marketing = params[:email_subscription][:agreed_to_marketing] == "1"
      sub.interests           = params[:email_subscription][:interests].presence
      if sub.save
        EmailSubscriptionConfirmationJob.perform_later(sub.id)
        redirect_back fallback_location: root_path, notice: "Check your inbox to confirm."
      else
        redirect_back fallback_location: root_path, alert: sub.errors.full_messages.first
      end
    else
      redirect_back fallback_location: root_path, notice: "Already subscribed."
    end
  end

  def confirm
    sub = EmailSubscription.find_by!(token: params[:token])
    if sub.confirmed?
      redirect_to root_path, notice: "Already confirmed."
    else
      sub.confirm!
      redirect_to root_path, notice: "Subscribed! You'll receive city updates."
    end
  end

  def destroy
    sub = EmailSubscription.find_by!(token: params[:token])
    sub.destroy!
    redirect_to root_path, notice: "Unsubscribed."
  end
end
