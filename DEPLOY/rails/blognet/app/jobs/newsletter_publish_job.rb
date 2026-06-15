# frozen_string_literal: true

class NewsletterPublishJob < ApplicationJob
  queue_as :mailers

  def perform(post_id)
    post = Post.find(post_id)
    return unless post.published?

    post.blog.newsletter_subscriptions.active.find_each do |sub|
      NewsletterMailer.new_post(sub, post).deliver_later
    end

    Shared::EventEmitter.call("blognet.newsletter.sent", post_id:, blog_id: post.blog_id) if defined?(Shared::EventEmitter)
  end
end