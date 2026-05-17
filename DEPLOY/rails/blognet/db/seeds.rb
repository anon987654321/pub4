user = User.find_or_create_by!(email_address: "admin@blognet.example") do |u|
  u.password = u.password_confirmation = "password123"
end

blog = Blog.find_or_create_by!(slug: "demo-blog") do |b|
  b.name        = "Demo Blog"
  b.description = "A demonstration blog"
  b.user        = user
  b.published   = true
end

5.times do |i|
  Post.find_or_create_by!(slug: "post-#{i + 1}") do |p|
    p.title     = "Post #{i + 1}: Getting Started with Rails 8"
    p.body      = "Rails 8 ships with Solid Cache, Solid Queue, and Solid Cable out of the box. This post covers what changed."
    p.blog      = blog
    p.user      = user
    p.published = true
  end
end
puts "Seeded #{Post.count} posts"
