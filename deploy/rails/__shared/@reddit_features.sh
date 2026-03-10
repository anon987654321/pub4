```ruby
#!/usr/bin/env zsh
set -euo pipefail

# Reddit-style social features: Comments, Votes, Karma
# Shared across brgen, amber, and other social apps

setup_reddit_models() {
  # Comment model with threading (parent_id for nested comments)
  bin/rails generate model Comment content:text user:references commentable:references{polymorphic} parent_id:integer

  # Vote model (upvote/downvote on posts, comments, listings)
  bin/rails generate model Vote value:integer user:references votable:references{polymorphic}

  # Add karma column to users
  bin/rails generate migration AddKarmaToUsers karma:integer:default:0

  log "Reddit models generated"
}

generate_comment_model() {
  log "Configuring Comment model with threading"

  cat <<'EOF' > app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy

  validates :content, presence: true, length: { maximum: 10000 }

  # Karma calculation
  def score
    votes.sum(:value)
  end

  def upvotes
    votes.where(value: 1).count
  end

  def downvotes
    votes.where(value: -1).count
  end

  # Threading helpers
  def root?
    parent_id.nil?
  end

  def depth
    parent&.depth.to_i + 1
  end

  # Sort comments Reddit-style
  scope :best, -> {
    select("comments.*, COALESCE(SUM(votes.value), 0) AS total_score")
      .left_joins(:votes)
      .group("comments.id")
      .order("total_score DESC")
  }
  scope :top, -> { best }
  scope :new, -> { order(created_at: :desc) }
  scope :old, -> { order(created_at: :asc) }
  scope :controversial, -> {
    select("comments.*,
            COUNT(CASE WHEN votes.value = 1 THEN 1 END) AS upvote_count,
            COUNT(CASE WHEN votes.value = -1 THEN 1 END) AS downvote_count")
      .left_joins(:votes)
      .group("comments.id")
      .order("ABS(upvote_count - downvote_count) ASC, (upvote_count + downvote_count) DESC")
  }
end
EOF
}
```
