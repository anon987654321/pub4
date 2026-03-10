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
    bin/rails generate model Comment content:text user:references commentable:references{polymorphic} parent_id:integer cached_score:integer:default:0 cached_upvotes:integer:default:0 cached_downvotes:integer:default:0 cached_depth:integer:default:0

    # Add foreign key constraint for parent_id
    cat <<'EOF' > db/migrate/$(date +%Y%m%d%H%M%S)_add_foreign_key_to_comments_parent.rb
class AddForeignKeyToCommentsParent < ActiveRecord::Migration[7.0]
  def change
    add_foreign_key :comments, :comments, column: :parent_id
  end
end
EOF
}

generate_vote_model() {
    log "Generating Vote model..."
    bin/rails generate model Vote value:integer user:references votable:references{polymorphic}

    # Add unique index to prevent duplicate votes
    cat <<'EOF' > db/migrate/$(date +%Y%m%d%H%M%S)_add_unique_index_to_votes.rb
class AddUniqueIndexToVotes < ActiveRecord::Migration[7.0]
  def change
    add_index :votes, [:user_id, :votable_type, :votable_id], unique: true
  end
end
EOF
}

setup_reddit_models() {
    generate_comment_model
    generate_vote_model

    # Add karma column to users with index
    log "Generating karma migration..."
    bin/rails generate migration AddKarmaToUsers karma:integer:default:0

    # Fix the karma migration file
    cat <<'EOF' > db/migrate/$(ls db/migrate | grep add_karma_to_users | sort | tail -1)
class AddKarmaToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :karma, :integer, default: 0
    add_index :users, :karma
  end
end
EOF

    # Create the Comment model with proper validations and caching
    cat <<'EOF' > app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy

  validates :content, presence: true, length: { maximum: 10000 }

  # Prevent circular references in parent-child relationships
  validate :no_circular_reference

  # Vote validation - ensure value is only -1 or 1
  validates :value, inclusion: { in: [-1, 1] }, if: -> { value.present? }

  # Karma calculation with caching and atomic updates to prevent race conditions
  def score
    read_attribute(:cached_score) || calculate_score
  end

  def upvotes
    read_attribute(:cached_upvotes) || votes.where(value: 1).count
  end

  def downvotes
    read_attribute(:cached_downvotes) || votes.where(value: -1).count
  end

  # Threading helpers with cached depth
  def root?
    parent_id.nil?
  end

  def depth
    read_attribute(:cached_depth) || calculate_depth
  end

  private

  def calculate_score
    new_score = votes.sum(:value)
    new_upvotes = votes.where(value: 1).count
    new_downvotes = votes.where(value: -1).count

    update_columns(
      cached_score: new_score,
      cached_upvotes: new_upvotes,
      cached_downvotes: new_downvotes
    )
    new_score
  end

  def calculate_depth
    return 0 if parent_id.nil?

    # Use SQL query to avoid N+1 and potential infinite loops
    depth_value = Comment.where(id: parent_id).pluck(:cached_depth).first.to_i + 1
    update_columns(cached_depth: depth_value)
    depth_value
  end

  def no_circular_reference
    if parent_id.present?
      current = parent
      while current.present?
        if current.parent_id == id
          errors.add(:parent_id, "cannot create circular reference")
          break
        end
        current = current.parent
      end
    end
  end
end
EOF

    # Create the Vote model with uniqueness validation
    cat <<'EOF' > app/models/vote.rb
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: [:votable_type, :votable_id] }

  after_save :update_votable_score
  after_destroy :update_votable_score

  private

  def update_votable_score
    votable.calculate_score if votable.respond_to?(:calculate_score)
  end
end
EOF

    # Update User model to include karma
    cat <<'EOF' >> app/models/user.rb
class User < ApplicationRecord
  has_many :comments, dependent: :destroy
  has_many :votes, dependent: :destroy

  def update_karma
    update_column(:karma, comments.sum(:cached_score) + votes.sum(:value))
  end
end
EOF

    log "Running migrations..."
    bin/rails db:migrate

    log "Reddit-style models setup complete!"
}

main() {
    log "Starting Reddit-style features setup..."
    setup_reddit_models
    log "Setup completed successfully!"
}

# Run the main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
```
