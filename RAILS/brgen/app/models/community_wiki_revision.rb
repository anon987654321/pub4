# frozen_string_literal: true

# What a wiki page said before an edit, and who was holding the pen.
class CommunityWikiRevision < ApplicationRecord
  belongs_to :page, class_name: "CommunityWikiPage", counter_cache: false, inverse_of: :revisions
  # Optional: an account can be deleted, and losing the account must not take
  # the page's history with it.
  belongs_to :user, optional: true

  validates :body, presence: true
end
