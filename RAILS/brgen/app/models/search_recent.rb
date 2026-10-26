# frozen_string_literal: true

# What this reader searched for lately, shown when the search palette opens
# with nothing typed yet. One row per (user, query): a repeat search moves the
# row to the top instead of accumulating, so the table is exactly as large as
# the history it represents and the (user_id, query) unique index is the dedup.
#
# Only committed searches are recorded — a full-page /search?q= visit — never
# the palette's per-keystroke live-search streams. The palette keeps its
# results in a turbo_stream fragment request, which is a suggestion being
# tried, not a search having happened.
class SearchRecent < ApplicationRecord
  belongs_to :user

  MAX_STORED_LENGTH = 200
  SHOWN_LIMIT = 5

  validates :query, presence: true, length: { maximum: MAX_STORED_LENGTH }
  validates :last_searched_at, presence: true

  class << self
    # Record one committed search. Guests are skipped by the caller (their rows
    # would grow a table the prune job would only have to clean up); a nil user
    # or a blank query records nothing rather than raising, because search
    # should never fail on bookkeeping.
    def record!(user, query)
      text = query.to_s.strip
      return nil if user.nil? || user.guest? || text.blank?
      return nil if text.length > MAX_STORED_LENGTH

      row = find_by(user_id: user.id, query: text)
      if row
        row.update!(last_searched_at: Time.current)
      else
        begin
          row = create!(user_id: user.id, query: text, last_searched_at: Time.current)
        rescue ActiveRecord::RecordNotUnique
          # Two tabs committed the same query in the same instant. The row the
          # other request wrote is the one both wanted.
          row = find_by(user_id: user.id, query: text)
          row&.update!(last_searched_at: Time.current)
        end
      end
      row
    end

    # Newest first, most recent use at the top. `id` as the tiebreak keeps two
    # searches recorded in the same second in a stable order.
    def recent_for(user, limit: SHOWN_LIMIT)
      return none if user.nil?

      where(user_id: user.id).order(last_searched_at: :desc, id: :desc).limit(limit)
    end
  end
end
