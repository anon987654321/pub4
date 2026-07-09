# frozen_string_literal: true

class ReactionsController < ApplicationController
  before_action :require_real_user

  def create
    @target = GlobalID::Locator.locate_signed!(params.require(:target_gid))
    @kind = params[:kind].presence || "like"
    @active = Shared::ReactionToggle.call(user: Current.user, reactable: @target, kind: @kind)
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path }
      format.turbo_stream
      format.json { render json: { active: @active, kind: @kind } }
    end
  end
end