#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"

echo "==> [controllers] Posts, comments, communities, votes"
cd "$APP_DIR"

cat > app/controllers/posts_controller.rb << 'RUBY'
class PostsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_post, only: [:show, :edit, :update, :destroy, :upvote, :downvote]
  before_action :authorize_user!, only: [:edit, :update, :destroy]

  def index  = @posts = Post.all.includes(:user, :community).hot.page(params[:page])
  def show   = @comments = @post.comments.best
  def new    = @post = current_user.posts.build
  def edit; end

  def create
    @post = current_user.posts.build(post_params)
    if @post.save
      redirect_to @post, notice: t("brgen.post_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @post.update(post_params)
      redirect_to @post, notice: t("brgen.post_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_path, notice: t("brgen.post_deleted")
  end

  def upvote   = @post.upvote_by(current_user).then { respond_to_vote }
  def downvote = @post.downvote_by(current_user).then { respond_to_vote }

  private

  def set_post       = @post = Post.find(params[:id])
  def authorize_user! = redirect_to(posts_path, alert: t("brgen.unauthorized")) unless @post.user == current_user
  def post_params    = params.require(:post).permit(:title, :content, :community_id, :anonymous)

  def respond_to_vote
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @post }
      format.json { render json: { score: @post.karma } }
    end
  end
end
RUBY

cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_commentable
  before_action :set_comment, only: [:destroy]
  before_action :authorize_user!, only: [:destroy]

  def create
    @comment = @commentable.comments.build(comment_params)
    @comment.user = current_user
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @commentable, notice: t("brgen.comment_created") }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @comment.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @commentable, notice: t("brgen.comment_deleted") }
    end
  end

  private

  def set_commentable  = @commentable = Post.find(params[:post_id])
  def set_comment      = @comment = Comment.find(params[:id])
  def authorize_user!  = redirect_to(@commentable, alert: t("brgen.unauthorized")) unless @comment.user == current_user
  def comment_params   = params.require(:comment).permit(:content, :parent_id)
end
RUBY

cat > app/controllers/communities_controller.rb << 'RUBY'
class CommunitiesController < ApplicationController
  def index = @communities = Community.all.order(:name)

  def show
    @community = Community.find_by!(slug: params[:id])
    @posts = @community.posts.includes(:user).hot.page(params[:page])
  end
end
RUBY

cat > app/controllers/votes_controller.rb << 'RUBY'
class VotesController < ApplicationController
  before_action :authenticate_user!

  ALLOWED_VOTABLE_TYPES = %w[Post Comment].freeze

  def create
    find_votable.upvote_by(current_user).then { |v| render json: { score: v.karma } }
  end

  def destroy
    find_votable.downvote_by(current_user).then { |v| render json: { score: v.karma } }
  end

  private

  def find_votable
    type = params[:votable_type]
    raise ArgumentError, "Invalid votable type" unless ALLOWED_VOTABLE_TYPES.include?(type)
    type.constantize.find(params[:votable_id])
  end
end
RUBY

echo "==> [controllers] done"
