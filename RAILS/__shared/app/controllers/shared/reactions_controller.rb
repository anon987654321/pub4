# frozen_string_literal: true

module Shared
  class ReactionsController < ApplicationController
    before_action :require_current_user

    def create
      # globalid ships locate_signed and no bang form, so every reaction raised
      # NoMethodError. A bad or expired signature answers nil: not found.
      @target = GlobalID::Locator.locate_signed(params.require(:target_gid)) or raise ActiveRecord::RecordNotFound
      @kind = params[:kind].presence || "like"
      @active = Shared::ReactionToggle.call(user: current_user, reactable: @target, kind: @kind)

      respond_to do |format|
        format.html {
 redirect_back fallback_location: main_app.root_path,
notice: t(@active ? "shared.flash.reaction_added" : "shared.flash.reaction_removed") }
        format.turbo_stream
        format.json { render json: { active: @active, kind: @kind } }
      end
    end

    private

    def require_current_user
      return if respond_to?(:current_user, true) && current_user

      redirect_to main_app.root_path, alert: t("shared.flash.sign_in_required")
    end
  end
end
