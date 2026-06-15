# frozen_string_literal: true

class ShareTargetsController < ApplicationController
  allow_unauthenticated_access only: :create

  def create
    payload = {
      title: params[:title].presence,
      text: params[:text].presence,
      url: params[:url].presence
    }.compact

    session[:share_target_payload] = payload

    if authenticated?
      redirect_to new_post_path(shared: payload[:text] || payload[:url] || payload[:title])
    else
      redirect_to new_session_path, alert: "Sign in to finish sharing into Brgen."
    end
  end
end