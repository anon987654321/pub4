#!/usr/bin/env zsh
# @social.sh — sourced via @shared_functions.sh
set -euo pipefail


# Social: votes + threaded comments
# Restored from pub3/@reddit_features.sh. Call after db:migrate.

setup_votes_and_comments() {
  bin/rails generate model Vote value:integer user:references \
    votable:references{polymorphic}:index --no-test-framework
  bin/rails generate model Comment content:text user:references \
    commentable:references{polymorphic}:index parent_id:integer \
    likes_count:integer --no-test-framework
  bin/rails db:migrate

  mkdir -p app/models/concerns

  cat > app/models/concerns/votable.rb << 'RUBY'
module Votable
  extend ActiveSupport::Concern
  included do
    has_many :votes, as: :votable, dependent: :destroy
  end
  def score          = votes.sum(:value)
  def upvotes        = votes.where(value: 1).count
  def downvotes      = votes.where(value: -1).count
  def voted_by?(u)   = votes.find_by(user: u)&.value
  def upvoted_by?(u) = voted_by?(u) == 1
end
RUBY

  cat > app/models/concerns/commentable.rb << 'RUBY'
module Commentable
  extend ActiveSupport::Concern
  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end
  def root_comments  = comments.where(parent_id: nil)
  def comment_count  = comments.count
end
RUBY

  cat > app/models/vote.rb << 'RUBY'
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true
  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: %i[votable_type votable_id] }
end
RUBY

  cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy
  validates :content, presence: true, length: { maximum: 10_000 }
  scope :roots,        -> { where(parent_id: nil) }
  scope :best,         -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value,0)) DESC") }
  scope :recent,       -> { order(created_at: :desc) }
  def score = votes.sum(:value)
  def depth = parent ? parent.depth + 1 : 0
end
RUBY

  cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  def create
    @commentable = find_commentable
    @comment = @commentable.comments.build(comment_params)
    @comment.user = Current.user
    @comment.save ? redirect_back(fallback_location: root_path) : redirect_back(fallback_location: root_path, alert: @comment.errors.full_messages.to_sentence)
  end

  def destroy
    @comment = Comment.find(params[:id])
    redirect_back(fallback_location: root_path, alert: "Unauthorized") and return unless @comment.user == Current.user
    @comment.destroy
    redirect_back fallback_location: root_path
  end

  private

  def find_commentable
    if params[:post_id]
      Post.find(params[:post_id])
    elsif params[:video_id]
      Video.find(params[:video_id])
    end
  end

  def comment_params = params.require(:comment).permit(:content, :parent_id)
end
RUBY

  cat > app/controllers/votes_controller.rb << 'RUBY'
class VotesController < ApplicationController
  def create
    @votable = find_votable
    vote = @votable.votes.find_or_initialize_by(user: Current.user)
    vote.value = params[:value].to_i.clamp(-1, 1)
    vote.save
    redirect_back fallback_location: root_path
  end

  private

  def find_votable
    if params[:post_id]
      Post.find(params[:post_id])
    elsif params[:comment_id]
      Comment.find(params[:comment_id])
    elsif params[:video_id]
      Video.find(params[:video_id])
    end
  end
end
RUBY

  log_ok "Votes + threaded comments set up"
}

# Social: hashtags
# Restored from pub3/@twitter_features.sh.

setup_hashtags() {
  bin/rails generate model Hashtag name:string:uniq usage_count:integer --no-test-framework
  bin/rails generate model Tagging taggable:references{polymorphic}:index \
    hashtag:references --no-test-framework
  bin/rails db:migrate

  cat > app/models/hashtag.rb << 'RUBY'
class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy
  validates :name, presence: true, uniqueness: true,
            format: { with: /\A[a-zA-Z0-9_]+\z/ }
  before_validation { self.name = name.to_s.downcase.gsub(/[^a-z0-9_]/, "") }
  scope :trending, -> { where("updated_at > ?", 24.hours.ago).order(usage_count: :desc).limit(10) }
  def to_param = name
end
RUBY

  cat > app/models/tagging.rb << 'RUBY'
class Tagging < ApplicationRecord
  belongs_to :taggable, polymorphic: true
  belongs_to :hashtag
  validates :hashtag_id, uniqueness: { scope: %i[taggable_type taggable_id] }
  after_create  { hashtag.increment!(:usage_count) }
  after_destroy { hashtag.decrement!(:usage_count) if hashtag.usage_count&.positive? }
end
RUBY

  mkdir -p app/models/concerns
  cat > app/models/concerns/taggable.rb << 'RUBY'
module Taggable
  extend ActiveSupport::Concern
  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :hashtags, through: :taggings
  end

  def tag_with(text)
    text.to_s.scan(/#([a-zA-Z0-9_]+)/).flatten.uniq.each do |name|
      tag = Hashtag.find_or_create_by!(name: name.downcase)
      taggings.find_or_create_by!(hashtag: tag)
    end
  end
end
RUBY

  log_ok "Hashtags set up"
}

# Social: direct messaging
# Restored from pub2/@instant_messaging.sh, adapted for Rails 8 auth.

setup_messaging() {
  bin/rails generate model Conversation --no-test-framework
  bin/rails generate model ConversationParticipant conversation:references \
    user:references last_read_at:datetime --no-test-framework
  bin/rails generate model Message conversation:references user:references \
    content:text read:boolean --no-test-framework
  bin/rails db:migrate

  cat > app/models/conversation.rb << 'RUBY'
class Conversation < ApplicationRecord
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy

  scope :for_user, ->(u) { joins(:conversation_participants).where(conversation_participants: { user: u }) }

  def self.between(u1, u2)
    joins(:conversation_participants)
      .where(conversation_participants: { user_id: [u1.id, u2.id] })
      .group("conversations.id")
      .having("COUNT(DISTINCT conversation_participants.user_id) = 2")
      .first
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user: user)
    messages.where("created_at > ?", participant&.last_read_at || Time.at(0)).count
  end

  def mark_read!(user)
    conversation_participants.find_by(user: user)&.update(last_read_at: Time.current)
  end
end
RUBY

  cat > app/models/message.rb << 'RUBY'
class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user
  validates :content, presence: true
  scope :recent, -> { order(created_at: :asc) }
  after_create_commit { broadcast_append_to conversation }
end
RUBY

  cat > app/controllers/conversations_controller.rb << 'RUBY'
class ConversationsController < ApplicationController
  def index
    @conversations = Conversation.for_user(Current.user).includes(:participants, :messages)
  end

  def show
    @conversation = Conversation.find(params[:id])
    @conversation.mark_read!(Current.user)
    @messages = @conversation.messages.recent
    @message = Message.new
  end

  def create
    other = User.find(params[:user_id])
    @conversation = Conversation.between(Current.user, other) ||
      Conversation.create!.tap { |c| c.participants << [Current.user, other] }
    redirect_to @conversation
  end
end
RUBY

  cat > app/controllers/messages_controller.rb << 'RUBY'
class MessagesController < ApplicationController
  def create
    @conversation = Conversation.find(params[:conversation_id])
    @message = @conversation.messages.build(content: params.dig(:message, :content), user: Current.user)
    @message.save ? redirect_to(@conversation) : redirect_back(fallback_location: @conversation)
  end
end
RUBY

  log_ok "Direct messaging set up"
}
