```zsh
#!/usr/bin/env zsh
set -euo pipefail

# Reddit-style social features: Comments, Votes, Karma
# Shared across brgen, amber, and other social apps

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

generate_comment_model() {
    log "Generating Comment model..."

    # Single migration with all constraints
    local migration_timestamp=$(date +%Y%m%d%H%M%S)
    cat <<EOF > db/migrate/${migration_timestamp}_create_comments.rb
class CreateComments < ActiveRecord::Migration[7.0]
  def change
    create_table :comments do |t|
      t.text :content
      t.references :user, null: false, foreign_key: true
      t.references :commentable, polymorphic: true, null: false
      t.references :parent, foreign_key: { to_table: :comments }
      t.integer :cached_score, default: 0
      t.integer :cached_upvotes, default: 0
      t.integer :cached_downvotes, default: 0
      t.integer :cached_depth, default: 0

      t.timestamps
    end

    add_index :comments, [:commentable_type, :commentable_id]
    add_index :comments, :parent_id
    add_index :comments, :cached_score
  end
end
EOF
}

generate_vote_model() {
    log "Generating Vote model..."

    local migration_timestamp=$(date +%Y%m%d%H%M%S)
    cat <<EOF > db/migrate/${migration_timestamp}_create_votes.rb
class CreateVotes < ActiveRecord::Migration[7.0]
  def change
    create_table :votes do |t|
      t.integer :value, null: false
      t.references :user, null: false, foreign_key: true
      t.references :votable, polymorphic: true, null: false

      t.timestamps
    end

    add_index :votes, [:user_id, :votable_type, :votable_id], unique: true
    add_index :votes, [:votable_type, :votable_id]
    add_check_constraint :votes, "value IN (1, -1)", name: "vote_value_check"
  end
end
EOF
}

setup_reddit_models() {
    # Check if migrations already exist
    if [[ -n $(find db/migrate -name "*create_comments*" 2>/dev/null) ]]; then
        log "Comments migration already exists, skipping..."
    else
        generate_comment_model
    fi

    if [[ -n $(find db/migrate -name "*create_votes*" 2>/dev/null) ]]; then
        log "Votes migration already exists, skipping..."
    else
        generate_vote_model
    fi

    # Add karma column to users with index
    if [[ -z $(find db/migrate -name "*add_karma_to_users*" 2>/dev/null) ]]; then
        log "Generating karma migration..."
        local karma_timestamp=$(date +%Y%m%d%H%M%S)
        cat <<EOF > db/migrate/${karma_timestamp}_add_karma_to_users.rb
class AddKarmaToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :karma, :integer, default: 0
    add_index :users, :karma
  end
end
EOF
    else
        log "Karma migration already exists, skipping..."
    fi

    # Create models with proper validations
    mkdir -p app/models

    cat <<'EOF' > app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy

  validates :content, presence: true
  validates :user_id, presence: true
  validates :commentable_type, presence: true
  validates :commentable_id, presence: true

  validate :no_circular_reference
  validate :parent_belongs_to_same_commentable

  after_create :update_cached_depth
  after_save :update_commentable_comments_count, if: :saved_change_to_parent_id?

  # Efficient scoring with database-level aggregation
  def recalc_score!
    new_score = votes.sum(:value)
    new_upvotes = votes.where(value: 1).count
    new_downvotes = votes.where(value: -1).count

    update_columns(
      cached_score: new_score,
      cached_upvotes: new_upvotes,
      cached_downvotes: new_downvotes
    )
  end

  def update_cached_depth
    depth = calculate_depth
    update_columns(cached_depth: depth) if cached_depth != depth
  end

  def calculate_depth
    return 0 unless parent
    parent.cached_depth + 1
  end

  def no_circular_reference
    return unless parent_id && parent_id == id
    errors.add(:parent_id, "cannot reference itself")
  end

  def parent_belongs_to_same_commentable
    return unless parent && commentable
    return if parent.commentable == commentable
    errors.add(:parent_id, "must belong to the same commentable")
  end

  def update_commentable_comments_count
    return unless commentable.respond_to?(:update_comments_count)
    commentable.update_comments_count
  end

  def vote_by_user(user)
    votes.find_by(user: user)
  end
end
EOF

    cat <<'EOF' > app/models/vote.rb
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :user_id, presence: true
  validates :votable_type, presence: true
  validates :votable_id, presence: true
  validates :value, inclusion: { in: [1, -1] }
  validates :user_id, uniqueness: { scope: [:votable_type, :votable_id] }

  after_save :update_votable_score
  after_destroy :update_votable_score

  private

  def update_votable_score
    votable.recalc_score! if votable.respond_to?(:recalc_score!)

    # Update user karma if voting on a comment
    if votable_type == "Comment"
      user.update_karma!
    end
  end
end
EOF

    # Add karma methods to User model
    if [[ -f app/models/user.rb ]]; then
        cat <<'EOF' >> app/models/user.rb

# Karma methods for User model
def update_karma!
  new_karma = comments.sum(:cached_score)
  update_columns(karma: new_karma) if karma != new_karma
end

def voted_on?(votable)
  votes.exists?(votable: votable)
end

def vote_for(votable, value)
  transaction do
    existing_vote = votes.find_by(votable: votable)

    if existing_vote
      if existing_vote.value == value
        existing_vote.destroy!
      else
        existing_vote.update!(value: value)
      end
    else
      votes.create!(votable: votable, value: value)
    end
  end
end
EOF
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_reddit_models
    log "Reddit-style social features setup complete!"
fi
```
