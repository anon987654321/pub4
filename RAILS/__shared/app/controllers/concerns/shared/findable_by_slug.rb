# frozen_string_literal: true

module Shared
  # Controller-side companion to Shared::Sluggable. Resolves a record from a route
  # segment that is normally a slug (to_param returns the slug) but may still be a
  # numeric id from a link created before slugs shipped, or a bookmarked /posts/123.
  # Slug lookup wins; a miss falls back to find(id), which raises RecordNotFound for
  # a genuinely unknown segment so the 404 behaviour is unchanged.
  #
  #   @post = find_by_slug_or_id(Post.includes(:user), params[:id])
  #
  # A show page reached by its id answers with a permanent redirect to its slug,
  # so a record has one URL rather than two that each call themselves canonical:
  #
  #   return if redirect_id_to_slug(@post)
  module FindableBySlug
    extend ActiveSupport::Concern

    private

    def find_by_slug_or_id(relation, param)
      relation.find_by(slug: param) || relation.find(param)
    end

    # True when it redirected, so the action can stop. Called from the show
    # action after its visibility check and never from the finder: a redirect
    # issued first would put the slug, which is the title, of a record the reader
    # may not see into a Location header.
    def redirect_id_to_slug(record)
      return false unless request.get? || request.head?
      return false if record.to_param == params[:id].to_s

      redirect_to url_for(id: record.to_param, params: request.query_parameters), status: :moved_permanently
      true
    end
  end
end
