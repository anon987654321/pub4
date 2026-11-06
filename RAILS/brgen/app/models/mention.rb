# frozen_string_literal: true

# A polymorphic join: this post named that user. Shared::Mentionable writes
# the row from @username in title and content.
class Mention < ApplicationRecord
  belongs_to :mentionable, polymorphic: true, inverse_of: :mentions
  belongs_to :mentioned_user, class_name: "User"

  # One row per named user per post, which is the promise `mention_test` makes
  # twice — "the same handle twice is one row", and an unchanged mention on edit
  # writing nothing. Shared::Mentionable already de-duplicates the handles, so
  # this guards the second writer rather than the one that exists; the table
  # carries no unique index, so nothing else does.
  validates :mentioned_user_id, uniqueness: { scope: %i[mentionable_type mentionable_id] }

  def self.extract(text)
    text.to_s.scan(/(?<![a-zA-Z0-9_])@([a-zA-Z0-9_]+)/).flatten.uniq
  end
end
