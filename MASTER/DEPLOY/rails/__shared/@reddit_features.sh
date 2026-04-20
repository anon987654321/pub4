#!/usr/bin/env zsh
set -euo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

timestamp() { date +%Y%m%d%H%M%S; }

migrations_dir=db/migrate
models_dir=app/models

migration_exists() { [[ -e $1 ]]; }

write_migration() {
  local file=$1; shift
  cat <<'EOF' > "$file"
$@
EOF
}

generate_comment_migration() {
  local ts=$(timestamp)
  local file="$migrations_dir/${ts}_create_comments.rb"
  write_migration "$file" "
class CreateComments < ActiveRecord::Migration[7.0]
  def change    create_table :comments do |t|
      t.text :content
      t.references :user, null: false, foreign_key: true
      t.references :commentable, polymorphic: true, null: false
      t.references :parent, foreign_key: { to_table: :comments }
      t.integer :cached_score, default: 0
      t.integer :cached_upvotes, default: 0      t.integer :cached_downvotes, default: 0
      t.integer :cached_depth, default: 0
      t.timestamps
    end
    add_index :comments, [:commentable_type, :commentable_id]
    add_index :comments, :parent_id    add_index :comments, :cached_score  end
end
"
  log "Generating Comment migration..."
  log "Created $file"
}

generate_vote_migration() {
  local ts=$(timestamp)
  local file="$migrations_dir/${ts}_create_votes.rb"
  write_migration "$file" "
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
    add_check_constraint :votes, 'value IN (1, -1)', name: 'vote_value_check'
  end
end
"
  log "Generating Vote migration..."
  log "Created $file"
}

generate_karma_migration() {
  local ts=$(timestamp)
  local file="$migrations_dir/${ts}_add_karma_to_users.rb"
  write_migration "$file" "
class AddKarmaToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :karma, :integer, default: 0
    add_index :users, :karma
  end
end
"
  log "Generating Karma migration..."
  log "Created $file"
}

write_comment_model() {
  mkdir -p "$models_dir"
  cat <<'EOF' > "$models_dir/comment.rb"
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

  def recalc_score!
    update_columns(
      cached_score: votes.sum(:value),
      cached_upvotes: votes.where(value: 1).count,
      cached_downvotes: votes.where(value: -1).count
    )
  end

  def update_cached_depth
    depth = calculate_depth
    update_columns(cached_depth: depth) if cached_depth != depth
  end

  def calculate_depth
    parent&.cached_depth.to_i + 1
  end

  def no_circular_reference
    errors.add(:parent_id, "cannot reference itself") if parent_id == id
  end

  def parent_belongs_to_same_commentable
    errors.add(:parent_id, "must belong to the same commentable") unless parent&.commentable == commentable
  end

  def update_commentable_comments_count
    commentable&.update_comments_count if commentable.respond_to?(:update_comments_count)
  end

  def vote_by_user(user)
    votes.find_by(user: user)
  end
end
EOF
}

write_vote_model() {
  cat <<'EOF' > "$models_dir/vote.rb"
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
    user.update_karma! if votable_type == "Comment"
  end
end
EOF
}

ensure_user_model() {
  [[ -f "$models_dir/user.rb" ]] || return
  cat <<'EOF' >> "$models_dir/user.rb"

# Karma methods
def update_karma!
  new_karma = comments.sum(:cached_score)
  update_columns(karma: new_karma) if karma != new_karma
end

def voted_on?(votable)
  votes.exists?(votable: votable)
end

def vote_for(votable, value)
  transaction do
    existing = votes.find_by(votable: votable)
    if existing
      existing.destroy! if existing.value == value
      existing.update!(value: value) unless existing.value == value
    else
      votes.create!(votable: votable, value: value)
    end
  end
end
EOF
}

setup_reddit_models() {
  [[ -e "$migrations_dir/create_comments.rb" ]] || generate_comment_migration
  [[ -e "$migrations_dir/create_votes.rb" ]] || generate_vote_migration
  [[ -e "$migrations_dir/add_karma_to_users.rb" ]] || generate_karma_migration

  write_comment_model
  write_vote_model
  ensure_user_model

  log "Reddit-style social features setup complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_reddit_models
fi