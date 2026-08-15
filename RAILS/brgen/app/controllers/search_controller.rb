# frozen_string_literal: true

class SearchController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: :index

  def index
    @query = live_search_query
    @results = {}
    return if @query.blank?

    @results[:people] = apply_live_search(
      User.where(bot: false, guest: false, deleted_at: nil),
      columns: %w[username display_name],
      vertical: "people"
    )
    @results[:posts] = apply_live_search(Post.kept, columns: %w[title content], vertical: "feed")
    @results[:listings] = apply_live_search(
      Marketplace::Listing.live.includes(:category),
      columns: %w[title description location],
      vertical: "marketplace"
    )
    @results[:channels] = apply_live_search(Tv::Channel.all, columns: %w[name description], vertical: "tv")
    @results[:videos] = apply_live_search(Tv::Video.published, columns: %w[title description], vertical: "tv")
    @results[:sets] = apply_live_search(Playlist::Set.publicly_listed, columns: %w[name description], vertical: "playlist")
    @results[:restaurants] = apply_live_search(Takeaway::Restaurant.active, columns: %w[name city cuisine_type], vertical: "takeaway")
    @results[:places] = apply_live_search(Place.all, columns: %w[name kind], vertical: "maps")

    # html/turbo_stream declare themselves but render nothing here, so the
    # fallthrough below handles them. Without them respond_to knows only json,
    # and a plain browser navigation to /search?q=... raises UnknownFormat —
    # every visitor who typed a query and pressed enter got a 406.
    respond_to do |format|
      format.json do
        render json: {
          query: @query,
          suggestions: search_suggestions,
          results: @results.transform_values { |scope| scope.limit(8).map { |record| { id: record.id, type: record.class.name, label: global_search_label(record) } } },
        }
      end
      format.html {}
      format.turbo_stream {}
    end
    return if performed?

    finish_live_search(partial: "search/live_search_results")
  end

  private

  def global_search_label(record)
    case record
    when Post then record.title
    when Marketplace::Listing then record.title
    when Tv::Channel then record.name
    when Tv::Video then record.title
    when Playlist::Set then record.name
    when Takeaway::Restaurant then record.name
    when Place then record.name
    else record.try(:title) || record.try(:name) || record.id.to_s
    end
  end
end
