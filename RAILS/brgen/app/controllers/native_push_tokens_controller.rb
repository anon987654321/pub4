# frozen_string_literal: true

# The iOS shell posts its APNs token here after the reader allows
# notifications, and again on later launches. A token already held by another
# account moves to this one: the device changed hands, not the token.
class NativePushTokensController < ApplicationController
  # Once per launch is the honest rate; this caps a client minting tokens.
  rate_limit to: 30, within: 1.hour, only: :create, by: -> { Current.user.id }

  def create
    record = NativePushToken.find_or_initialize_by(token: params.require(:token).to_s.downcase)
    record.update!(user: Current.user, environment: params[:environment].presence || "production")
    head :created
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    head :unprocessable_entity
  end

  def destroy
    Current.user.native_push_tokens.find_by(token: params[:token].to_s.downcase)&.destroy
    head :ok
  end
end
