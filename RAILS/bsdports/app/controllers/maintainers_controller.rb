# frozen_string_literal: true

class MaintainersController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]

  def index
    scope = Maintainer.order(:name).includes(:ports)
    scope = apply_live_search(scope, columns: %w[name email], vertical: "maintainers") if live_search_query.present?
    @pagy, @maintainers = pagy(scope)
    finish_live_search(partial: "maintainers/live_search_results")
  end

  def show
    @maintainer = Maintainer.find(params[:id])
    @maintainer.record_activity!("MaintainerViewed", source_vertical: "bsdports") unless passive_request?
    # The page is the maintainer and a page of ports; an import that changes
    # either moves one of these. The page number lives in the URL, and :usec
    # keeps a same-second import from expanding to an unchanged key.
    return unless stale?(etag: [
      @maintainer.cache_key_with_version,
      @maintainer.ports.maximum(:updated_at)&.to_fs(:usec), @maintainer.ports.count
    ])

    @pagy, @ports = pagy(@maintainer.ports.order(:name))
  end
end
