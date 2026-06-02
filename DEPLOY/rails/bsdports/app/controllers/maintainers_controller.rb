# frozen_string_literal: true

class MaintainersController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  def index
    @maintainers = Maintainer.order(:name).includes(:ports)
  end

  def show
    @maintainer = Maintainer.find(params[:id])
    @pagy, @ports = pagy(@maintainer.ports.order(:name))
  end
end
