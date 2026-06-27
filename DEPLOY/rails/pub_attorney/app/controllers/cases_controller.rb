# frozen_string_literal: true

class CasesController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_authentication
  before_action :set_case, only: %i[show]

  def index
    scope = Current.user.cases.includes(:lawyer).order(created_at: :desc)
    scope = apply_live_search(scope, columns: %w[title status description], vertical: "cases") if live_search_query.present?
    @pagy, @cases = pagy(scope)
    finish_live_search(partial: "cases/live_search_results")
  end

  def show
    @documents = @case.documents.order(created_at: :desc)
  end

  private

  def set_case
    @case = Current.user.cases.find(params[:id])
  end
end