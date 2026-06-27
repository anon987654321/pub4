xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0" do
  xml.channel do
    xml.title @blog ? "#{@blog.name} — Blognet" : "Blognet"
    xml.link @blog ? blog_feed_url(@blog, format: :rss) : feed_url(format: :rss)
    xml.description @blog ? "Latest posts from #{@blog.name}" : "Latest published posts across Blognet"
    xml.language "en-us"
    xml.lastBuildDate @posts.first&.published_at&.to_time&.rfc2822 if @posts.any?
    @posts.each do |post|
      xml.item do
        xml.title post.title
        xml.link blog_post_url(post.blog, post)
        xml.description do
          xml.cdata! post.body.to_plain_text.truncate(500)
        end
        xml.pubDate post.published_at.to_time.rfc2822 if post.published_at
        xml.guid blog_post_url(post.blog, post), isPermaLink: true
        xml.author post.user.email_address if post.user
      end
    end
  end
end