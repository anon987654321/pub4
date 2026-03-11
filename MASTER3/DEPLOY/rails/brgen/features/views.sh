#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"

echo "==> [views] ERB templates"
cd "$APP_DIR"

mkdir -p app/views/{communities,posts,comments,shared}

cat > app/views/communities/index.html.erb << 'ERB'
<section class="communities">
  <header>
    <h1><%= t("brgen.communities") %></h1>
  </header>

  <div class="community-grid">
    <% @communities.each do |community| %>
      <article class="community-card">
        <%= link_to community_path(community) do %>
          <h2><%= community.name %></h2>
          <p><%= community.description %></p>
        <% end %>
      </article>
    <% end %>
  </div>
</section>
ERB

cat > app/views/posts/index.html.erb << 'ERB'
<section class="posts">
  <header>
    <h1><%= t("brgen.posts") %></h1>
    <%= link_to t("brgen.new_post"), new_post_path if user_signed_in? %>
  </header>

  <% @posts.each do |post| %>
    <article class="post">
      <h2><%= link_to post.title, post_path(post) %></h2>
      <p class="meta"><%= t("brgen.posted_by", user: post.user.username) %> &bull; karma: <%= post.karma %></p>
    </article>
  <% end %>

  <%== pagy_nav(@pagy) if @pagy %>
</section>
ERB

cat > app/views/posts/show.html.erb << 'ERB'
<section class="post-show">
  <article class="post">
    <h1><%= @post.title %></h1>
    <p class="meta"><%= t("brgen.posted_by", user: @post.user.username) %></p>
    <div class="content"><%= simple_format @post.content %></div>

    <div class="vote-controls">
      <%= button_to t("brgen.upvote"),   upvote_post_path(@post),   method: :post if user_signed_in? %>
      <span class="karma"><%= @post.karma %></span>
      <%= button_to t("brgen.downvote"), downvote_post_path(@post), method: :post if user_signed_in? %>
    </div>
  </article>

  <section class="comments">
    <h2><%= t("brgen.comments") %></h2>

    <% if user_signed_in? %>
      <%= form_with url: post_comments_path(@post), local: false do |f| %>
        <%= f.text_area :content, placeholder: t("brgen.add_comment") %>
        <%= f.submit %>
      <% end %>
    <% end %>

    <% @comments.each do |comment| %>
      <article class="comment">
        <p><%= comment.content %></p>
        <p class="meta"><%= comment.user.username %></p>
      </article>
    <% end %>
  </section>
</section>
ERB

echo "==> [views] done"
