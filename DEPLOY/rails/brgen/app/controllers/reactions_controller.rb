# frozen_string_literal: true

class ReactionsController < ApplicationController
  before_action :require_real_user

  def create
    @target = GlobalID::Locator.locate_signed!(params.require(:target_gid))
    @kind = params[:kind].presence || "like"
    existing = Reaction.find_by(user: Current.user, reactable: @target, kind: @kind)
    @active = existing.nil?
    @active ? Reaction.create!(user: Current.user, reactable: @target, kind: @kind) : existing.destroy!
    respond_to do |f|
      f.html { redirect_back fallback_location: root_path }
      f.turbo_stream
      f.json { render json: { active: @active, kind: @kind } }
    end
  end
end
