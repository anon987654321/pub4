# frozen_string_literal: true

class DraftsController < ApplicationController
  def update
    session[:drafts] ||= {}
    session[:drafts][params[:id].to_s] = draft_params
    head :no_content
  end

  private

  def draft_params
    params.to_unsafe_h.except("controller", "action", "id", "authenticity_token", "_method")
  end
end
