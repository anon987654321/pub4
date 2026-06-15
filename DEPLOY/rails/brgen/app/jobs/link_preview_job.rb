# frozen_string_literal: true
# AN606: Link preview via OpenGraph (demo/fallback)

class LinkPreviewJob < ApplicationJob
  include Shared::ExternalApiRetry
  queue_as :default

  def perform(post_id, url)
    post = Post.find(post_id)
    metadata = fetch_metadata(url)
    post.update!(link_preview: metadata)
    post.broadcast_replace_to post.community, target: dom_id(post, :preview), partial: "posts/link_preview", locals: { post: post }
  end

  private

  def fetch_metadata(url)
    if ENV["OG_FETCH_ENABLED"] == "true"
      require "open-uri"
      html = URI.open(url, read_timeout: 5).read
      title = html[/property="og:title" content="([^"]+)"/, 1]
      image = html[/property="og:image" content="([^"]+)"/, 1]
      description = html[/property="og:description" content="([^"]+)"/, 1]
      { url: url, title: title, image: image, description: description }
    else
      { url: url, title: "Preview", image: nil, description: "Demo preview — enable OG_FETCH_ENABLED for live fetch" }
    end
  rescue StandardError => e
    { url: url, title: url, error: e.message }
  end
end