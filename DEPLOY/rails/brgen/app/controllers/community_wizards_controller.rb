# frozen_string_literal: true

class CommunityWizardsController < ApplicationController
  before_action :require_real_user

  STEPS = %w[basics rules category privacy preview].freeze

  def show
    @step = (params[:step] || session[:community_wizard_step] || STEPS.first)
    @step = STEPS.include?(@step) ? @step : STEPS.first
    session[:community_wizard_step] = @step
    @draft = session[:community_wizard_draft] ||= {}
    @community = Community.new(@draft)
  end

  def update
    draft = (session[:community_wizard_draft] ||= {})
    draft.merge!(wizard_params)
    session[:community_wizard_draft] = draft

    current = params[:step].to_s
    next_step = STEPS[(STEPS.index(current) || -1) + 1]

    if next_step.nil?
      community = Community.new(draft)
      community.user = Current.user
      if community.save
        session.delete(:community_wizard_draft)
        session.delete(:community_wizard_step)
        redirect_to community, notice: "Community created."
      else
        @step = "preview"
        @draft = draft
        @community = community
        render :show, status: :unprocessable_entity
      end
    else
      redirect_to community_wizard_path(step: next_step)
    end
  end

  private

  def wizard_params
    params.fetch(:community, {}).permit(:name, :description).to_h.compact_blank
  end
end