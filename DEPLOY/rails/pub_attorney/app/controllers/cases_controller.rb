# frozen_string_literal: true

class CasesController < ApplicationController
  before_action :require_authentication
  before_action :set_case, only: %i[show]

  def index
    @pagy, @cases = pagy(Current.user.cases.includes(:lawyer).order(created_at: :desc))
  end

  def show
    @documents = @case.documents.order(created_at: :desc)
  end

  private

  def set_case
    @case = Current.user.cases.find(params[:id])
  end
end