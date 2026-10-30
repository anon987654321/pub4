# frozen_string_literal: true

class PushSubscriptionsController < ApplicationController
  # The page re-posts its subscription on each load, and a refused repeat is
  # harmless; this caps junk endpoints, not readers.
  rate_limit to: 30, within: 1.hour, only: :create, by: -> { Current.user.id }

  def create
    data = JSON.parse(request.body.read)
    Current.user.push_subscriptions.find_or_create_by!(endpoint: data["endpoint"]) do |s|
      s.p256dh = data.dig("keys", "p256dh")
      s.auth = data.dig("keys", "auth")
    end
    head :created
  rescue JSON::ParserError => e
    Ground::Swallow.log(e, context: "PushSubscriptionsController.create")
    head :bad_request
  end

  def destroy
    Current.user.push_subscriptions.find_by(endpoint: params[:endpoint])&.destroy
    head :ok
  end
end
