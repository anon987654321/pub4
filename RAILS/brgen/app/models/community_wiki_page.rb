# frozen_string_literal: true

# A community's own reference page — the rules behind the rules, the local
# glossary, what the weekly thread is for.
class CommunityWikiPage < ApplicationRecord
  belongs_to :community
  belongs_to :updated_by, class_name: "User", optional: true
  # The history is the point: an edit that guts a page has to be recoverable by
  # the next moderator who reads it, not by whoever kept a copy.
  has_many :revisions, -> { order(created_at: :desc) },
           class_name: "CommunityWikiRevision", foreign_key: :page_id,
           dependent: :destroy, inverse_of: :page

  validates :title, presence: true, length: { maximum: 120 }
  validates :body, presence: true, length: { maximum: 40_000 }
  validates :slug, presence: true, uniqueness: { scope: :community_id },
                   format: { with: /\A[a-z0-9][a-z0-9\-]*\z/, message: "must be url-safe" }

  before_validation :assign_slug

  def to_param = slug

  # Writing keeps what it replaced. Called instead of update! so no caller can
  # save a page and forget the revision — a history with holes reads as if the
  # missing edits never happened.
  def revise!(body:, user:)
    transaction do
      revisions.create!(body: self[:body], user: updated_by) if persisted? && body != self[:body]
      update!(body: body, updated_by: user)
    end
  end

  # A revert is a new revision, never a deletion of the ones after it: a wiki
  # whose history can be edited is a wiki nobody can audit.
  def revert_to!(revision, user:)
    revise!(body: revision.body, user: user)
  end

  private

  def assign_slug
    return if slug.present?

    base = title.to_s.parameterize.presence || "page"
    candidate = base
    suffix = 2
    while self.class.where(community_id: community_id, slug: candidate).where.not(id: id).exists?
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end
    self.slug = candidate
  end
end
