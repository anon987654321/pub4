# frozen_string_literal: true

class TagsController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index autocomplete]

  def index
    scope = Tag.popular
    scope = apply_live_search(scope, columns: %w[name], vertical: "tags") if live_search_query.present?
    @pagy, @tags = pagy(scope)

    render_live_search(collection: @tags, partial: "tags/tag") if request.format.turbo_stream?
  end

  def autocomplete
    tags = Tag.autocomplete(live_search_query)
    render json: tags.map { |tag| { id: tag.id, name: tag.name, posts_count: tag.posts_count } }
  end
end