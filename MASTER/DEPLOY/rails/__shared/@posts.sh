cd "$BASE_DIR"

echo "Generating Posts, Communities, and Comments..."

bundle add friendly_id
bundle install

bin/rails generate model Community name:string description:text
bin/rails generate model Post title:string content:text user:references community:references
bin/rails generate model Comment content:text user:references post:references
bin/rails db:migrate

# Community model
cat <<EOF > app/models/community.rb
class Community < ApplicationRecord
  has_many :posts, class_name: "Post"

  validates :name, presence: true

  extend FriendlyId
  friendly_id :name, use: :slugged
end
EOF

# Post model
cat <<EOF > app/models/post.rb
class Post < ApplicationRecord
  belongs_to :user
  belongs_to :community, class_name: "Community"

  has_many :comments, class_name: "Comment", dependent: :destroy
  has_many :post_visibilities
  has_many :visible_users, through: :post_visibilities, source: :user
  has_many :reactions, as: :reactable, dependent: :destroy

  validates :title, :content, presence: true

  extend FriendlyId
  friendly_id :title, use: :slugged

  after_create :set_expiry
  after_update_commit { broadcast_replace_to "posts" }

  def visible_to?(user)
    self.visible_users.include?(user)
  end

  def set_expiry
    ExpiryJob.set(wait_until: self.expiry_time).perform_later(self.id) if self.expiry_time.present?
  end
end
EOF

# Comment model
cat <<EOF > app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :post, class_name: "Post"
  belongs_to :user

  validates :content, presence: true

  extend FriendlyId
  friendly_id :content, use: :slugged
end
EOF

# PostsController
cat <<EOF > app/controllers/posts_controller.rb
class PostsController < ApplicationController
  before_action :set_post, only: [:show, :edit, :update, :destroy]
  before_action :authenticate_user!

  def create
    @post = current_user.posts.new(post_params)
    if @post.save
      params[:post][:visible_user_ids].each do |user_id|
        @post.post_visibilities.create(user_id: user_id)
      end
      @post.visible_users.each do |user|
        Notification.create(user: user, post: @post, message: "You have a new private post")
      end
      respond_to do |format|
        format.html { redirect_to @post, notice: t('posts.create.success') }
        format.turbo_stream
      end
    else
      render :new
    end
  end

  def update
    if @post.update(post_params)
      respond_to do |format|
        format.html { redirect_to main_community_post_path(@post.community, @post) }
        format.turbo_stream
      end
    else
      render :edit
    end
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :content, :community_id, :user_id, :expiry_time, visible_user_ids: [])
  end
end
EOF

# CommentsController
cat <<EOF > app/controllers/comments_controller.rb
class CommentsController < ApplicationController
  def create
    @comment = Comment.new(comment_params)

    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to main_community_post_path(@comment.post.community, @comment.post) }
      end
    else
      render :new
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:content, :post_id, :user_id)
  end
end
EOF

# Turbo Stream Views
mkdir -p app/views/posts app/views/comments

cat <<EOF > app/views/posts/_post.html.erb
<%= turbo_frame_tag dom_id(post) do %>
  <div class="post" id="post_<%= post.id %>">
    <h2><%= link_to post.title, main_community_post_path(post.community, post) %></h2>
    <p><%= post.content %></p>
  </div>
<% end %>
EOF

cat <<EOF > app/views/comments/_comment.html.erb
<%= turbo_frame_tag dom_id(comment) do %>
  <div class="comment" id="comment_<%= comment.id %>">
    <p><%= comment.content %></p>
  </div>
<% end %>
EOF

cat <<EOF > app/views/posts/create.turbo_stream.erb
<%= turbo_stream.append "posts", partial: "posts/post", locals: { post: @post } %>
EOF

cat <<EOF > app/views/posts/update.turbo_stream.erb
<%= turbo_stream.replace @post, partial: "posts/post", locals: { post: @post } %>
EOF

cat <<EOF > app/views/comments/create.turbo_stream.erb
<%= turbo_stream.append "comments", partial: "comments/comment", locals: { comment: @comment } %>
EOF

# FriendlyId for SEO-friendly URLs
echo "Installing FriendlyId for SEO-friendly URLs..."

bundle add friendly_id
bundle install
bin/rails generate friendly_id
commit_to_git "Installed FriendlyId for SEO-friendly URLs."

cat <<EOF > app/models/user.rb
class User < ApplicationRecord
  extend FriendlyId
  friendly_id :username, use: :slugged
end
EOF

cat <<EOF > app/models/community.rb
class Community < ApplicationRecord
  has_many :posts, class_name: "Post"

  validates :name, presence: true

  extend FriendlyId
  friendly_id :name, use: :slugged
end
EOF

cat <<EOF > app/models/post.rb
class Post < ApplicationRecord
  belongs_to :user
  belongs_to :community, class_name: "Community"

  has_many :comments, class_name: "Comment", dependent: :destroy
  has_many :post_visibilities
  has_many :visible_users, through: :post_visibilities, source: :user
  has_many :reactions, as: :reactable, dependent: :destroy

  validates :title, :content, presence: true

  extend FriendlyId
  friendly_id :title, use: :slugged
end
EOF

cat <<EOF > app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :post, class_name: "Post"
  belongs_to :user

  validates :content, presence: true

  extend FriendlyId
  friendly_id :content, use: :slugged
end
EOF

commit_to_git "Set up FriendlyId for SEO-friendly URLs for User, Community, Post, and Comment models."

# I18n and Babosa for translation and transliteration
echo "Setting up I18n and Babosa for translation and transliteration..."
bundle add babosa

cat <<EOF > config/initializers/locale.rb
I18n.available_locales = [:en, :no]
I18n.default_locale = :en

require "babosa"
EOF

commit_to_git "Set up I18n and Babosa for translation and transliteration."

# Add Private Posts feature
echo "Adding private posts feature..."
cat <<EOF > app/models/post.rb
class Post < ApplicationRecord
  belongs_to :user
  has_many :post_visibilities
  has_many :visible_users, through: :post_visibilities, source: :user
  has_many :comments, dependent: :destroy
  has_many :reactions, as: :reactable, dependent: :destroy

  validates :content, presence: true

  after_create :set_expiry
  after_update_commit { broadcast_replace_to "posts" }

  def visible_to?(user)
    self.visible_users.include?(user)
  end

  def set_expiry
    ExpiryJob.set(wait_until: self.expiry_time).perform_later(self.id) if self.expiry_time.present?
  end
end
EOF

cat <<EOF > app/controllers/posts_controller.rb
class PostsController < ApplicationController
  before_action :set_post, only: [:show, :edit, :update, :destroy]
  before_action :authenticate_user!

  def create
    @post = current_user.posts.new(post_params)
    if @post.save
      params[:post][:visible_user_ids].each do |user_id|
        @post.post_visibilities.create(user_id: user_id)
      end
      @post.visible_users.each do |user|
        Notification.create(user: user, post: @post, message: "You have a new private post")
      end
      respond_to do |format|
        format.html { redirect_to @post, notice: t('posts.create.success') }
        format.turbo_stream
      end
    else
      render :new
    end
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:content, :expiry_time, visible_user_ids: [])
  end
end
EOF

commit_to_git "Added private posts feature."
