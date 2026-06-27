xml.instruct! :xml, version: "1.0"
xml.feed xmlns: "http://www.w3.org/2005/Atom" do
  xml.title @blog ? "#{@blog.name} — Blognet" : "Blognet"
  xml.link rel: "self", href: (@blog ? blog_feed_url(@blog, format: :atom) : feed_url(format: :atom))
  xml.link href: (@blog ? blog_url(@blog) : root_url)
  xml.updated((@posts.first&.published_at || Time.current).iso8601)
  xml.id @blog ? blog_url(@blog) : root_url
  @posts.each do |post|
    xml.entry do
      xml.title post.title
      xml.link rel: "alternate", href: blog_post_url(post.blog, post)
      xml.id blog_post_url(post.blog, post)
      xml.updated post.published_at.iso8601 if post.published_at
      xml.summary post.body.to_plain_text.truncate(500)
      xml.author do
        xml.name post.user&.email_address || "Blognet"
      end
    end
  end
end