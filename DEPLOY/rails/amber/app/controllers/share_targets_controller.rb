# frozen_string_literal: true

class ShareTargetsController < ApplicationController
  def create
    session[:share_target_payload] = {
      title: params[:title].presence,
      text: params[:text].presence,
      url: params[:url].presence
    }.compact
    redirect_to authenticated? ? new_item_path : new_session_path
  end
end