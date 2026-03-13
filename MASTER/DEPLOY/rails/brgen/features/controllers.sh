#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"
echo "==> [controllers] All app controllers"
cd "$APP_DIR"

mkdir -p app/controllers/concerns

cat > app/controllers/concerns/authentication.rb << 'RUBY'
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :resume_session
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :resume_session, **options rescue nil
    end
  end

  private

  def authenticated?
    Current.user.present? && !Current.user.guest?
  end

  def current_user
    Current.user
  end

  def resume_session
    Current.session = find_session_by_cookie
    if Current.session
      Current.user = Current.session.user
    else
      Current.user = find_or_create_guest_user
    end
  end

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:session_id])
  end

  def find_or_create_guest_user
    guest_id = session[:guest_user_id]
    if guest_id
      User.find_by(id: guest_id, guest: true) || create_guest_user
    else
      create_guest_user
    end
  end

  def create_guest_user
    guest = User.create!(
      email_address: "guest_#{SecureRandom.hex(8)}@guest.local",
      password: SecureRandom.hex(16),
      guest: true
    )
    session[:guest_user_id] = guest.id
    guest
  end

  def require_real_user
    unless authenticated?
      redirect_to new_session_path, alert: "Sign in to continue"
    end
  end

  alias_method :require_authentication, :resume_session
end
RUBY

cat > app/controllers/home_controller.rb << 'RUBY'
class HomeController < ApplicationController
  def index
    @posts = if authenticated?
               Current.user.timeline_posts.hot.includes(:user, :community, :votes).limit(50)
             else
               Post.hot.includes(:user, :community, :votes).limit(50)
             end
    @communities = Community.popular.limit(10)
  end
end
RUBY

cat > app/controllers/posts_controller.rb << 'RUBY'
class PostsController < ApplicationController
  before_action :require_real_user, only: [:new, :create, :edit, :update, :destroy]
  before_action :set_post,          only: [:show, :edit, :update, :destroy]
  before_action :set_community,     only: [:new, :create]

  def index
    @posts = Post.hot.includes(:user, :community, :votes)
  end

  def show
    @comments    = @post.comments.where(parent_id: nil).best.includes(:user, :votes, replies: [:user, :votes])
    @new_comment = Comment.new
  end

  def new
    @post = Post.new(community: @community)
  end

  def create
    @post           = Post.new(post_params)
    @post.user      = Current.user
    @post.community = @community if @community
    if @post.save
      redirect_to @post, notice: "Posted."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @post.update(post_params)
      redirect_to @post
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_path
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def set_community
    @community = Community.find_by(id: params[:community_id])
  end

  def post_params
    params.require(:post).permit(:title, :content, :community_id)
  end
end
RUBY

cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  before_action :require_real_user
  before_action :set_commentable

  def create
    @comment           = @commentable.comments.build(comment_params)
    @comment.user      = Current.user
    @comment.parent_id = params[:parent_id] if params[:parent_id]

    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: root_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("comment_form", partial: "comments/form", locals: { comment: @comment, commentable: @commentable }) }
        format.html         { redirect_back fallback_location: root_path, alert: @comment.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    @comment = Comment.find(params[:id])
    @comment.destroy if @comment.user == Current.user
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@comment)) }
      format.html         { redirect_back fallback_location: root_path }
    end
  end

  private

  def set_commentable
    if params[:post_id]
      @commentable = Post.find(params[:post_id])
    elsif params[:comment_id]
      @commentable = Comment.find(params[:comment_id])
    end
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
RUBY

cat > app/controllers/communities_controller.rb << 'RUBY'
class CommunitiesController < ApplicationController
  before_action :require_real_user, only: [:new, :create]
  before_action :set_community,     only: [:show]

  def index
    @communities = Community.popular.includes(:user)
  end

  def show
    @posts = @community.posts.hot.includes(:user, :votes)
  end

  def new
    @community = Community.new
  end

  def create
    @community      = Community.new(community_params)
    @community.user = Current.user
    if @community.save
      redirect_to @community, notice: "Community created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_community    = @community = Community.find(params[:id])
  def community_params = params.require(:community).permit(:name, :description)
end
RUBY

cat > app/controllers/votes_controller.rb << 'RUBY'
class VotesController < ApplicationController
  before_action :require_authentication

  ALLOWED = %w[Post Comment].freeze

  def create
    votable = find_votable
    vote    = votable.votes.find_or_initialize_by(user: Current.user)

    if vote.persisted? && vote.value == params[:vote][:value].to_i
      vote.destroy
    else
      vote.update!(value: params[:vote][:value])
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def find_votable
    type = params[:votable_type].to_s.classify
    raise ArgumentError unless ALLOWED.include?(type)
    type.constantize.find(params[:votable_id])
  end
end
RUBY

cat > app/controllers/follows_controller.rb << 'RUBY'
class FollowsController < ApplicationController
  before_action :require_real_user

  def create
    user = User.find(params[:user_id])
    Current.user.follow!(user)
    redirect_back fallback_location: root_path
  end

  def destroy
    user = User.find(params[:user_id])
    Current.user.unfollow!(user)
    redirect_back fallback_location: root_path
  end
end
RUBY

cat > app/controllers/conversations_controller.rb << 'RUBY'
class ConversationsController < ApplicationController
  before_action :require_real_user

  def index
    @conversations = Conversation.for_user(Current.user)
                                 .includes(:participants, :messages)
                                 .order("messages.created_at DESC")
  end

  def show
    @conversation = Conversation.for_user(Current.user).find(params[:id])
    @conversation.mark_read_for!(Current.user)
    @messages = @conversation.messages.recent.limit(50).reverse
    @message  = Message.new
  end

  def create
    other         = User.find(params[:user_id])
    @conversation = Conversation.find_or_create_direct(Current.user, other)
    redirect_to @conversation
  end
end
RUBY

cat > app/controllers/messages_controller.rb << 'RUBY'
class MessagesController < ApplicationController
  before_action :require_real_user
  before_action :set_conversation

  def create
    @message        = @conversation.messages.build(message_params)
    @message.sender = Current.user

    if @message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @conversation }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id])
  end

  def message_params
    params.require(:message).permit(:content, :message_type)
  end
end
RUBY

echo "==> [controllers] done"
