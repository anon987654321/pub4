# frozen_string_literal: true

class LawyersController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  def index
    @pagy, @lawyers = pagy(Lawyer.order(rating: :desc))
  end

  def show
    @lawyer = Lawyer.find(params[:id])
    @cases = @lawyer.cases.order(created_at: :desc).limit(5)
  end
end