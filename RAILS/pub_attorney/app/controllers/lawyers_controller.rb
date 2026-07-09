# frozen_string_literal: true

class LawyersController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]

  def index
    scope = Lawyer.order(rating: :desc)
    scope = apply_live_search(scope, columns: %w[name specialty bio], vertical: "lawyers") if live_search_query.present?
    @pagy, @lawyers = pagy(scope)
    finish_live_search(partial: "lawyers/live_search_results")
  end

  def show
    @lawyer = Lawyer.find(params[:id])
    @cases = @lawyer.cases.order(created_at: :desc).limit(5)
  end
end