#!/usr/bin/env ruby
# Generate complete blognet.sh script

output = []

# Header
output << <<~'HEADER'
#!/usr/bin/env zsh
set -euo pipefail

readonly APP_NAME="blognet"
readonly APP_PORT="3004"
readonly BASE_DIR="${HOME}/rails/${APP_NAME}"

source "${0:a:h}/__shared.sh"

log "═══════════════════════════════════════════════════════════════"
log "  BLOGNET - AI-Powered Multi-Tenant Blogging Platform"
log "═══════════════════════════════════════════════════════════════"

setup_full_app "${APP_NAME}"

command_exists "ruby"
command_exists "node"
command_exists "psql"

HEADER

# Gems
output << <<~'GEMS'
log "Installing gems..."
install_gem "devise"
install_gem "friendly_id"
install_gem "acts_as_tenant"
install_gem "pagy"
install_gem "faker"
install_gem "ruby-openai"
install_gem "anthropic"

GEMS

# Models
output << <<~'MODELS'
log "Generating models..."

bin/rails generate devise:install
bin/rails generate devise User

bin/rails generate model Blog name:string subdomain:string:uniq description:text theme:string user:references
bin/rails generate model Post title:string slug:string:uniq content:text excerpt:text published:boolean published_at:datetime views:integer category:string ai_generated:boolean user:references blog:references
bin/rails generate model Comment content:text approved:boolean user:references post:references blog:references
bin/rails generate model Tag name:string slug:string:uniq
bin/rails generate model Tagging post:references tag:references

MODELS

# Model files
output << <<~'MODELFILES'
cat > app/models/blog.rb <<'RUBY'
class Blog < ApplicationRecord
  belongs_to :user
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true

  before_validation :generate_subdomain, on: :create

  THEMES = %w[minimal dark colorful professional].freeze

  private

  def generate_subdomain
    self.subdomain ||= name.parameterize if name.present?
  end
end
RUBY

cat > app/models/post.rb <<'RUBY'
class Post < ApplicationRecord
  extend FriendlyId

  belongs_to :user
  belongs_to :blog
  has_many :comments, dependent: :destroy
  has_many :taggings, dependent: :destroy
  has_many :tags, through: :taggings

  friendly_id :title, use: :slugged

  validates :title, presence: true
  validates :content, presence: true

  scope :published, -> { where(published: true).order(published_at: :desc) }
  scope :drafts, -> { where(published: false).order(created_at: :desc) }

  before_save :set_excerpt

  private

  def set_excerpt
    self.excerpt ||= content&.truncate(200) if content.present?
  end
end
RUBY

cat > app/models/comment.rb <<'RUBY'
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post
  belongs_to :blog

  validates :content, presence: true

  scope :approved, -> { where(approved: true) }
  scope :pending, -> { where(approved: false) }
end
RUBY

MODELFILES

# Controllers
output << <<~'CONTROLLERS'
mkdir -p app/controllers/tenants

cat > app/controllers/home_controller.rb <<'RUBY'
class HomeController < ApplicationController
  def index
    @blogs = Blog.includes(:user).order(created_at: :desc).limit(12)
  end
end
RUBY

cat > app/controllers/tenants/posts_controller.rb <<'RUBY'
module Tenants
  class PostsController < ApplicationController
    before_action :set_blog
    before_action :set_post, only: %i[show edit update destroy generate_ai]
    before_action :authenticate_user!, except: %i[index show]

    def index
      @pagy, @posts = pagy(@blog.posts.published, items: 12)
    end

    def show
      @post.increment!(:views)
      @comments = @post.comments.approved.order(created_at: :desc)
    end

    def new
      @post = @blog.posts.build
    end

    def create
      @post = @blog.posts.build(post_params)
      @post.user = current_user

      if @post.save
        redirect_to tenants_post_path(@post), notice: "Post created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @post.update(post_params)
        redirect_to tenants_post_path(@post), notice: "Post updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @post.destroy
      redirect_to tenants_posts_path, notice: "Post deleted."
    end

    def generate_ai
      content = AiContentService.new(@post).generate
      @post.update(content: content, ai_generated: true)
      redirect_to tenants_post_path(@post), notice: "AI content generated."
    end

    private

    def set_blog
      @blog = Blog.find_by!(subdomain: request.subdomain)
    end

    def set_post
      @post = @blog.posts.friendly.find(params[:id])
    end

    def post_params
      params.require(:post).permit(:title, :content, :category, :published)
    end
  end
end
RUBY

cat > app/controllers/tenants/comments_controller.rb <<'RUBY'
module Tenants
  class CommentsController < ApplicationController
    before_action :set_blog
    before_action :set_post
    before_action :authenticate_user!

    def create
      @comment = @post.comments.build(comment_params)
      @comment.user = current_user
      @comment.blog = @blog

      if @comment.save
        redirect_to tenants_post_path(@post), notice: "Comment submitted."
      else
        redirect_to tenants_post_path(@post), alert: "Failed to submit."
      end
    end

    private

    def set_blog
      @blog = Blog.find_by!(subdomain: request.subdomain)
    end

    def set_post
      @post = @blog.posts.friendly.find(params[:post_id])
    end

    def comment_params
      params.require(:comment).permit(:content)
    end
  end
end
RUBY

CONTROLLERS

# Services
output << <<~'SERVICES'
mkdir -p app/services

cat > app/services/ai_content_service.rb <<'RUBY'
class AiContentService
  def initialize(post)
    @post = post
  end

  def generate
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY", ""))

    response = client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "system", content: "You are a professional blog writer." },
          { role: "user", content: "Write about: #{@post.title}" }
        ],
        temperature: 0.7,
        max_tokens: 2000
      }
    )

    response.dig("choices", 0, "message", "content")
  rescue => e
    Rails.logger.error("AI failed: #{e.message}")
    "Failed to generate content."
  end
end
RUBY

SERVICES

# Routes
output << <<~'ROUTES'
cat > config/routes.rb <<'RUBY'
Rails.application.routes.draw do
  devise_for :users

  constraints(lambda { |req| req.subdomain.present? && req.subdomain != "www" }) do
    scope module: :tenants do
      root "posts#index"
      resources :posts do
        member { post :generate_ai }
        resources :comments, only: [:create]
      end
    end
  end

  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
RUBY

ROUTES

# Views - this will be very long, so I'll create a helper
File.write('G:/pub/rails/blognet.sh', output.join("\n"))
puts "Basic structure created. Now adding views..."
