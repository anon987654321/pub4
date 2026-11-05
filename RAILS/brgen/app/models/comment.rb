# frozen_string_literal: true

class Comment < ApplicationRecord
  include Shared::Votable
  include Shared::CommentThreading
  # A reply names people as often as a post does. The concern reads :content
  # and :user_id, both columns here, and skips :title, which comments lack.
  include Shared::Mentionable
  tracks_activity created: "CommentCreated", source_vertical: "social", actor: :user

  belongs_to :user
  # counter_cache is opt-in per type on a polymorphic belongs_to: Rails only
  # maintains it where the column exists, and posts is the one that has it.
  belongs_to :commentable, polymorphic: true, touch: true, counter_cache: :comments_count

  include Shared::RichTextLength

  # content holds Tiptap's HTML; the maximum measures the text inside it.
  # A tombstone has no words left to measure.
  validates :content, presence: true, length: { minimum: 1 }, unless: :tombstoned?
  validates_rich_text_length :content, maximum: 10_000
  # A reply belongs to its parent's thread. parent_id comes from the form, and a parent
  # from another post put this reply under a thread its writer may not be able to read.
  validate :parent_on_the_same_thread, if: -> { parent_id.present? && will_save_change_to_parent_id? }

  # posts#show subscribes to [post, "comments"]: a new comment lands in place,
  # under its parent when it is a reply, and a deleted one leaves.
  after_create_commit :broadcast_to_thread
  after_destroy_commit :broadcast_removal
  # The count on every card and page showing the post. The counter cache
  # increments with SQL, so the post runs no callback of its own for it.
  after_commit :broadcast_commentable_counts, on: [ :create, :destroy ]

  # Editing is bounded as messages are (Message::EDIT_WINDOW): a comment that
  # can be rewritten hours later is one its replies may no longer answer.
  EDIT_WINDOW = 15.minutes

  before_update :stamp_edited_at

  BEST_SQL = Arel.sql("SUM(COALESCE(votes.value, 0)) DESC")
  CONTROVERSIAL_SQL = Arel.sql("ABS(SUM(votes.value)) ASC")
  HAS_UPVOTE_SQL = Arel.sql("COUNT(CASE WHEN votes.value =  1 THEN 1 END) > 0")
  HAS_DOWNVOTE_SQL = Arel.sql("COUNT(CASE WHEN votes.value = -1 THEN 1 END) > 0")

  scope :kept,          -> { where(removed_at: nil) }
  scope :best,          -> { kept.left_joins(:votes).group(:id).order(BEST_SQL) }
  scope :top,           -> { best }
  scope :new_first,     -> { kept.order(created_at: :desc) }
  scope :controversial, -> {
    kept.left_joins(:votes).group(:id)
      .having(HAS_UPVOTE_SQL)
      .having(HAS_DOWNVOTE_SQL)
      .order(CONTROVERSIAL_SQL)
  }

  def depth
    d = 0
    ancestor_id = parent_id
    while ancestor_id
      d += 1
      ancestor_id = Comment.where(id: ancestor_id).pick(:parent_id)
    end
    d
  end

  LONG_THREAD_THRESHOLD = 20

  def long_thread?
    direct_reply_ids = Comment.where(parent_id: id).pluck(:id)
    total = direct_reply_ids.size + Comment.where(parent_id: direct_reply_ids).count
    total > LONG_THREAD_THRESHOLD
  end

  # Ids of the comments on one commentable whose thread is long, from one query.
  # A post page asked long_thread? of every comment and reply it drew, two
  # queries each; the comment partial asks this once per page instead.
  def self.long_thread_ids(commentable_type, commentable_id)
    replies = where(commentable_type:, commentable_id:).where.not(parent_id: nil)
    children = replies.pluck(:parent_id, :id).group_by(&:first).transform_values { |rows| rows.map(&:last) }
    long = children.select { |_id, kids| kids.size + kids.sum { children.fetch(_1, []).size } > LONG_THREAD_THRESHOLD }
    long.keys.to_set
  end

  def editable_by?(user)
    user.present? && user.id == user_id && !tombstoned? && removed_at.nil? && created_at > EDIT_WINDOW.ago
  end

  def edited? = edited_at.present?

  # A live comment by someone else on a community post: what a moderator of
  # that community may take down (comments#remove).
  def removable_by_moderator_of_thread?(user)
    user.present? && user_id != user.id && commentable_type == "Post" && !tombstoned? && removed_at.nil?
  end

  # By key when the post is not loaded: strict loading refuses the lazy read.
  def thread_community_id
    return unless commentable_type == "Post"
    return commentable&.community_id if association(:commentable).loaded?

    Post.unscoped.where(id: commentable_id).pick(:community_id)
  end

  def has_thread_summary?
    thread_summary.present? && summary_updated_at.present?
  end

  # Where a comment goes on the post page: under its parent when it is a reply,
  # else at the end of the thread. Public for PostCatchUpsController's view.
  def thread_target = parent_id ? ActionView::RecordIdentifier.dom_id(Comment.new(id: parent_id), :replies) : "comments"

  # Public because ModerationWorkflow removes with update_columns, which runs
  # no callback.
  def broadcast_removal
    stream = thread_stream
    broadcast_remove_to(stream) if stream
  rescue StandardError => e
    Rails.logger.warn("Comment#broadcast_removal #{id}: #{e.class}: #{e.message}")
  end

  # A tombstone takes the comment's place on every open page; its replies stay.
  def broadcast_tombstone
    stream = thread_stream
    return unless stream

    Current.set(user: nil, session: nil) do
      broadcast_replace_to(stream, target: ActionView::RecordIdentifier.dom_id(self),
                                   partial: "comments/comment", locals: { comment: self })
    end
  rescue StandardError => e
    Rails.logger.warn("Comment#broadcast_tombstone #{id}: #{e.class}: #{e.message}")
  end

  private

  # Rendered for nobody, and marked so: on the creating request Current.user is
  # the writer, and the partial would hand every reader the writer's delete
  # button. The writer's own response appends their copy, with the button;
  # live_comments_controller keeps it when this one arrives after it.
  def broadcast_to_thread
    stream = thread_stream
    return unless stream

    broadcast_remove_to(stream, target: "comments_empty") unless parent_id
    Current.set(user: nil, session: nil) do
      broadcast_append_to(
        stream, target: thread_target, partial: "comments/comment", locals: { comment: self },
        attributes: { "data-viewer-neutral": "" }
      )
    end
  rescue StandardError => e
    Rails.logger.warn("Comment#broadcast_to_thread #{id}: #{e.class}: #{e.message}")
  end

  # By key when the commentable is not loaded: a comment found by id for its
  # deletion has none, and strict loading refuses the lazy read.
  def thread_stream
    record = if association(:commentable).loaded?
      commentable
    else
      commentable_type.to_s.safe_constantize&.unscoped&.find_by(id: commentable_id)
    end
    [ record, "comments" ] if record
  end

  # By key: a comment found by id for its deletion has no commentable loaded,
  # and strict loading refuses the lazy read. Posts are the commentable with
  # live counts.
  def broadcast_commentable_counts
    return unless commentable_type == "Post"

    Post.unscoped.find_by(id: commentable_id)&.broadcast_live_counts
  end

  # Changed words mark the comment edited; a summary or vote does not.
  def stamp_edited_at
    self.edited_at = Time.current if will_save_change_to_content?
  end

  # By key: a lazy load of parent raises under strict loading.
  def parent_on_the_same_thread
    same = Comment.where(id: parent_id, commentable_type:, commentable_id:).exists?
    errors.add(:parent_id, :invalid) unless same
  end
end
