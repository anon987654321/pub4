# frozen_string_literal: true

class ShareTargetsController < ApplicationController
  def create
    session[:share_target_draft] = params[:text].presence || params[:url].presence || params[:title].presence
    redirect_to authenticated? ? root_path : new_session_path
  end
end