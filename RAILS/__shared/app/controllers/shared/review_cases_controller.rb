# frozen_string_literal: true

module Shared
  class ReviewCasesController < ApplicationController
    before_action :require_current_user

    def create
      @target = GlobalID::Locator.locate_signed!(params.require(:target_gid))
      @review_case = Shared::ReviewCase.create!(
        reporter: current_user,
        reviewable: @target,
        reason: params[:reason].presence || "other",
        notes: params[:notes],
      )

      respond_to do |format|
        format.html { redirect_back fallback_location: main_app.root_path, notice: t("shared.flash.sent_for_review") }
        format.turbo_stream
        format.json { render json: { id: @review_case.id, state: @review_case.state }, status: :created }
      end
    end

    def update
      @review_case = Shared::ReviewCase.find(params[:id])
      action = params[:review_action].to_s
      action == "ignore" ? @review_case.ignore!(current_user) : @review_case.close!(current_user)

      respond_to do |format|
        format.html { redirect_back fallback_location: main_app.root_path }
        format.turbo_stream
        format.json { render json: { id: @review_case.id, state: @review_case.state } }
      end
    end

    private

    def require_current_user
      return if respond_to?(:current_user, true) && current_user

      redirect_to main_app.root_path, alert: t("shared.flash.sign_in_required")
    end
  end
end
