# frozen_string_literal: true

module Shared
  # Controller-side companion to Shared::Sluggable. Resolves a record from a route
  # segment that is normally a slug (to_param returns the slug) but may still be a
  # numeric id from a link created before slugs shipped, or a bookmarked /posts/123.
  # Slug lookup wins; a miss falls back to find(id), which raises RecordNotFound for
  # a genuinely unknown segment so the 404 behaviour is unchanged.
  #
  #   @post = find_by_slug_or_id(Post.includes(:user), params[:id])
  module FindableBySlug
    extend ActiveSupport::Concern

    private

    def find_by_slug_or_id(relation, param)
      relation.find_by(slug: param) || relation.find(param)
    end
  end
end
