#!/usr/bin/env bash
set -euo pipefail

log() {
  printf "[%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

timestamp() {
  date +%Y%m%d%H%M%S%N | cut -c1-17  # nanosecond precision, trimmed to avoid filename length issues
}

migrations_dir=db/migrate
models_dir=app/models

migration_exists() {
  shopt -s nullglob
  local matches=($1)
  (( ${#matches[@]} ))
}

write_migration() {
  local file=$1
  shift
  mkdir -p "$(dirname "$file")"
  {
    printf "%s\n" "$*"
  } >"$file"
}

generate_migration() {
  local ts file name content
  ts=$(timestamp)
  name=$1
  file="${migrations_dir}/${ts}_$name.rb"
  content=$2
  write_migration "$file" "$content"
  log "Generated $name migration: $file"
}

generate_comment_migration() {
  generate_migration "create_comments" "
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
    add_index :comments, %i[commentable_type commentable_id]
    add_index :comments, :parent_id
    add_index :comments, :cached_score
  end
end
"
}

generate_vote_migration() {
  generate_migration "create_votes" "
class CreateVotes < ActiveRecord::Migration[7.0]
  def change
    create_table :votes do |t|
      t.integer :value, null: false
      t.references :user, null: false, foreign_key: true
      t.references :votable, polymorphic: true, null: false
      t.timestamps
    end
    add_index :votes, %i[user_id votable_type votable_id], unique: true
    add_index :votes, %i[votable_type votable_id]
    add_check_constraint :votes, 'value IN (1, -1)', name: 'vote_value_check'
  end
end
"
}

generate_karma_migration() {
  generate_migration "add_karma_to_users" "
class AddKarmaToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :karma, :integer, default: 0
    add_index :users, :karma
  end
end
"
}

write_model() {
  local target=$1
  local content=$2
  [[ -f "$target" ]] && return
  mkdir -p "$(dirname "$target")"
  cat >"$target" <<<"$content"
}

write_comment_model() {
  write_model "${models_dir}/comment.rb" 'class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy

  validates :content, :user_id, :commentable_type, :commentable_id, presence: true

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
end'
}

write_vote_model() {
  write_model "${models_dir}/vote.rb" 'class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :user_id, :votable_type, :votable_id, presence: true
  validates :value, inclusion: { in: [1, -1] }
  validates :user_id, uniqueness: { scope: %i[votable_type votable_id] }

  after_save :update_votable_score
  after_destroy :update_votable_score

  private

  def update_votable_score
    votable.recalc_score! if votable.respond_to?(:recalc_score!)
    user.update_karma! if votable_type == "Comment"
  end
end'
}

ensure_user_model() {
  local target="${models_dir}/user.rb"
  [[ -f "$target" ]] || return
  if ! grep -q "def update_karma!" "$target"; then
    cat >>"$target" <<'EOF'

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
    log "Extended user model with karma methods"
  fi
}

setup_reddit_models() {
  migration_exists "$migrations_dir/*_create_comments.rb"   || generate_comment_migration
  migration_exists "$migrations_dir/*_create_votes.rb"      || generate_vote_migration
  migration_exists "$migrations_dir/*_add_karma_to_users.rb" || generate_karma_migration

  write_comment_model
  write_vote_model
  ensure_user_model

  log "Reddit-style social features setup complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_reddit_models
fi