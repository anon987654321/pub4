# Social Sharing Helper
module SocialSharingHelper
  def social_share_buttons(options = {})
    url = options[:url] || request.original_url
    title = options[:title] || content_for(:title) || "Check this out"
    render partial: "shared/social_share", locals: { url: url, title: title }
  end
  def share_metadata(options = {})
    content_for :head do
      tag.meta(property: "og:url", content: options[:url]) +
      tag.meta(property: "og:title", content: options[:title]) +
      tag.meta(property: "og:description", content: options[:description]) +
      tag.meta(property: "og:image", content: options[:image]) +
      tag.meta(name: "twitter:card", content: "summary_large_image")
    end
  end
end
