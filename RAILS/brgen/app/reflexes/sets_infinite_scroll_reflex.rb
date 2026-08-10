# frozen_string_literal: true

class SetsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "playlist/sets/card", as: :set

  private

  def scope
    scope = Playlist::Set.publicly_listed
    return scope unless element.dataset["q"].present?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
    set_ids = scope.where("name LIKE ? OR description LIKE ?", term, term).pluck(:id)
    track_ids = Playlist::Track.where("name LIKE ? OR artist LIKE ?", term, term).pluck(:playlist_set_id)
    scope.where(id: (set_ids + track_ids).uniq)
  end
end
