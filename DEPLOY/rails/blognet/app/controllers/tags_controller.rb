# frozen_string_literal: true

class TagsController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index autocomplete]

  def index
    scope = Tag.order(:name)
    scope = apply_live_search(scope, columns: %w[name], vertical: "tags") if live_search_query.present?
    @pagy, @tags = pagy(scope)
    finish_live_search(partial: "tags/live_search_results")
  end

  def autocomplete
    scope = Tag.order(:name)
    tags = apply_live_search(scope, columns: %w[name], vertical: "tags").limit(12)
    render json: tags.pluck(:name)
  end
end