# frozen_string_literal: true

class MaintainersController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]

  def index
    scope = Maintainer.order(:name).includes(:ports)
    scope = apply_live_search(scope, columns: %w[name email], vertical: "maintainers") if live_search_query.present?
    @maintainers = scope
    finish_live_search(partial: "maintainers/live_search_results")
  end

  def show
    @maintainer = Maintainer.find(params[:id])
    @pagy, @ports = pagy(@maintainer.ports.order(:name))
    @maintainer.record_activity!("MaintainerViewed", source_vertical: "bsdports")
  end
end
