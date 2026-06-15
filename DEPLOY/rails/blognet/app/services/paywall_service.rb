# frozen_string_literal: true

class PaywallService
  def self.can_read?(post:, viewer_token:, user: nil)
    new(post:, viewer_token:, user:).can_read?
  end

  def initialize(post:, viewer_token:, user: nil)
    @post = post
    @blog = post.blog
    @viewer_token = viewer_token
    @user = user
  end

  def can_read?
    return true unless @blog.paywall_enabled?
    return true if @user && (@post.user == @user || subscribed?)
    return true unless @post.paywalled?

    views = ArticleView.where(post: @post, viewer_token: @viewer_token).exists? ||
      metered_views < @blog.free_article_limit
    track_view! if views
    views
  end

  def metered_views
    ArticleView.where(viewer_token: @viewer_token)
               .joins(:post)
               .where(posts: { blog_id: @blog.id, paywalled: true })
               .count
  end

  def track_view!
    ArticleView.find_or_create_by!(post: @post, viewer_token: @viewer_token)
  end

  private

  def subscribed?
    return false unless @user

    Subscription.where(blog: @blog, user: @user).any?(&:active?)
  end
end