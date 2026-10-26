# frozen_string_literal: true

# One like per person and thing. The reactions table and its unique index on
# user, target and kind were already in amber's schema with no model, so a like
# was only a counter, and one person could raise it as fast as the write limit.
class Reaction < ApplicationRecord
  belongs_to :user
  belongs_to :reactable, polymorphic: true
end
