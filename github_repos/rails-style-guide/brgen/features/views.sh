#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly APP_DIR="/home/brgen/app"
echo "==> [views] Writing all templates"
cd "$APP_DIR"

mkdir -p app/views/{home,posts,comments,communities,layouts}

ruby - <<'RUBY'
views = {}

views["app/views/layouts/application.html.erb"] = <<~'ERB'
  <!DOCTYPE html>
  <html lang="no">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title><%= content_for?(:title) ? "#{yield :title} — brgen" : "brgen" %></title>
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body>

  <nav>
    <%= link_to "brgen", root_path, class: "logo" %>
    <div class="nav-links">
      <%= link_to "communities", communities_path %>
      <%= link_to "posts",       posts_path %>
      <% if authenticated? %>
        <%= link_to "inbox",   conversations_path %>
        <%= link_to "sign out", session_path, data: { turbo_method: :delete } %>
      <% else %>
        <%= link_to "sign in",  new_session_path %>
      <% end %>
    </div>
  </nav>

  <div class="page">
    <% if notice %><div class="flash-notice"><%= notice %></div><% end %>
    <% if alert  %><div class="flash-alert"><%=  alert  %></div><% end %>
    <%= yield %>
  </div>

  </body>
  </html>
ERB

views["app/views/home/index.html.erb"] = <<~'ERB'
  <div class="main-col">
    <div class="sort-tabs">
      <span class="sort-tab active">hot</span>
      <%= link_to "fresh", posts_path(sort: "fresh"), class: "sort-tab" %>
    </div>

    <% if @posts.any? %>
      <% @posts.each do |post| %>
        <%= render "posts/post", post: post %>
      <% end %>
    <% else %>
      <div class="empty">
        <p>No posts yet. <%= authenticated? ? link_to("Create one", new_post_path) : link_to("Sign in to post", new_session_path) %>.</p>
      </div>
    <% end %>
  </div>

  <div class="side-col">
    <div class="sidebar-card">
      <h3>Communities</h3>
      <ul>
        <% @communities.each do |c| %>
          <li><%= link_to c.name, community_path(c) %></li>
        <% end %>
      </ul>
      <% if authenticated? %>
        <div style="margin-top:12px"><%= link_to "+ New community", new_community_path, class: "btn btn-ghost" %></div>
      <% end %>
    </div>
    <% if authenticated? %>
      <div class="sidebar-card">
        <%= link_to "New post", new_post_path, class: "btn", style: "width:100%;text-align:center" %>
      </div>
    <% end %>
  </div>
ERB

views["app/views/posts/_post.html.erb"] = <<~'ERB'
  <%= turbo_frame_tag dom_id(post) do %>
  <div class="post-card">
    <div class="vote-col">
      <% if authenticated? %>
        <%= button_to "▲", post_vote_path(post), params: { vote: { value: 1 } },
              class: "vote-btn #{post.upvoted_by?(Current.user) ? "active-up" : ""}" %>
      <% else %>
        <span class="vote-btn">▲</span>
      <% end %>
      <span class="vote-score"><%= post.score %></span>
      <% if authenticated? %>
        <%= button_to "▼", post_vote_path(post), params: { vote: { value: -1 } },
              class: "vote-btn down #{post.downvoted_by?(Current.user) ? "active-down" : ""}" %>
      <% else %>
        <span class="vote-btn">▼</span>
      <% end %>
    </div>

    <div class="post-body">
      <div class="post-meta">
        <% if post.community %>
          <%= link_to post.community.name, community_path(post.community), class: "community" %>
          <span>•</span>
        <% end %>
        posted by <span><%= post.author_name %></span>
        <span>•</span>
        <%= time_ago_in_words(post.created_at) %> ago
      </div>
      <div class="post-title"><%= link_to post.title, post %></div>
      <div class="post-actions">
        <%= link_to "#{post.comment_count} comments", post_path(post) %>
        <% if authenticated? && post.user == Current.user %>
          <%= link_to "edit",   edit_post_path(post) %>
          <%= button_to "delete", post, method: :delete, data: { turbo_confirm: "Delete this post?" }, class: "vote-btn" %>
        <% end %>
      </div>
    </div>
  </div>
  <% end %>
ERB

views["app/views/posts/index.html.erb"] = <<~'ERB'
  <div class="main-col">
    <div class="page-header">
      <h1>All Posts</h1>
      <% if authenticated? %><%= link_to "+ New Post", new_post_path, class: "btn" %><% end %>
    </div>

    <div class="sort-tabs">
      <%= link_to "hot",   posts_path,               class: "sort-tab #{params[:sort].blank? ? "active" : ""}" %>
      <%= link_to "fresh", posts_path(sort: "fresh"), class: "sort-tab #{params[:sort] == "fresh" ? "active" : ""}" %>
      <%= link_to "top",   posts_path(sort: "top"),   class: "sort-tab #{params[:sort] == "top"   ? "active" : ""}" %>
    </div>

    <% if @posts.any? %>
      <% @posts.each do |post| %>
        <%= render "posts/post", post: post %>
      <% end %>
    <% else %>
      <div class="empty">No posts yet.</div>
    <% end %>
  </div>

  <div class="side-col">
    <div class="sidebar-card">
      <h3>Communities</h3>
      <ul>
        <% Community.popular.limit(8).each do |c| %>
          <li><%= link_to c.name, community_path(c) %></li>
        <% end %>
      </ul>
    </div>
  </div>
ERB

views["app/views/posts/show.html.erb"] = <<~'ERB'
  <% content_for :title, @post.title %>

  <div class="main-col">
    <div class="post-show">
      <div style="display:flex;gap:16px;align-items:flex-start">
        <div class="vote-col" style="background:var(--surface2);border-radius:var(--radius);padding:12px 0;min-width:40px;align-items:center;display:flex;flex-direction:column;gap:4px">
          <% if authenticated? %>
            <%= button_to "▲", post_vote_path(@post), params: { vote: { value: 1 } },
                  class: "vote-btn #{@post.upvoted_by?(Current.user) ? "active-up" : ""}" %>
          <% else %>
            <span class="vote-btn">▲</span>
          <% end %>
          <span class="vote-score"><%= @post.score %></span>
          <% if authenticated? %>
            <%= button_to "▼", post_vote_path(@post), params: { vote: { value: -1 } },
                  class: "vote-btn down #{@post.downvoted_by?(Current.user) ? "active-down" : ""}" %>
          <% else %>
            <span class="vote-btn">▼</span>
          <% end %>
        </div>

        <div style="flex:1;min-width:0">
          <div class="post-meta">
            <% if @post.community %>
              <%= link_to @post.community.name, community_path(@post.community), class: "community" %> •
            <% end %>
            posted by <%= @post.author_name %> • <%= time_ago_in_words(@post.created_at) %> ago
          </div>
          <h1 style="font-size:1.3rem;font-weight:600;margin-bottom:12px"><%= @post.title %></h1>
          <% if @post.content.present? %>
            <div class="post-content"><%= @post.content %></div>
          <% end %>
        </div>
      </div>
    </div>

    <div class="comments-section">
      <% if authenticated? %>
        <div class="comment-form-wrap" id="comment_form">
          <h3 style="font-size:0.85rem;color:var(--text-dim);margin-bottom:12px">Comment as <%= Current.user.username || "guest" %></h3>
          <%= form_with model: [@post, @new_comment], data: { turbo: true } do |f| %>
            <div class="field"><%= f.text_area :content, placeholder: "What do you think?", rows: 4 %></div>
            <%= f.submit "Comment", class: "btn" %>
          <% end %>
        </div>
      <% end %>

      <div id="comments">
        <% if @comments.any? %>
          <% @comments.each do |comment| %>
            <%= render "comments/comment", comment: comment %>
          <% end %>
        <% else %>
          <div class="empty">No comments yet. Be first.</div>
        <% end %>
      </div>
    </div>
  </div>

  <div class="side-col">
    <div class="sidebar-card">
      <h3>About</h3>
      <% if @post.community %>
        <p style="color:var(--text-dim);font-size:0.875rem"><%= @post.community.description.presence || @post.community.name %></p>
        <div style="margin-top:12px"><%= link_to "View community", community_path(@post.community), class: "btn btn-ghost" %></div>
      <% else %>
        <p style="color:var(--text-dim);font-size:0.875rem">brgen — Bergen community platform</p>
      <% end %>
    </div>
  </div>
ERB

views["app/views/posts/new.html.erb"] = <<~'ERB'
  <div class="form-wrap">
    <h1 style="margin-bottom:20px"><%= @post.new_record? ? "New Post" : "Edit Post" %></h1>

    <%= form_with model: [@community, @post].compact do |f| %>
      <% if @post.errors.any? %>
        <div class="flash-alert" style="grid-column:auto">
          <% @post.errors.full_messages.each do |msg| %><div><%= msg %></div><% end %>
        </div>
      <% end %>

      <div class="field">
        <%= f.label :community_id, "Community (optional)" %>
        <%= f.collection_select :community_id, Community.order(:name), :id, :name,
              { include_blank: "— no community —" } %>
      </div>

      <div class="field">
        <%= f.label :title %>
        <%= f.text_field :title, placeholder: "Title", autofocus: true %>
      </div>

      <div class="field">
        <%= f.label :content, "Body (optional)" %>
        <%= f.text_area :content, placeholder: "Text (optional)", rows: 8 %>
      </div>

      <div style="display:flex;gap:12px;align-items:center">
        <%= f.submit @post.new_record? ? "Post" : "Save", class: "btn" %>
        <%= link_to "Cancel", @post.new_record? ? posts_path : @post, class: "btn btn-ghost" %>
      </div>
    <% end %>
  </div>
ERB

views["app/views/comments/_comment.html.erb"] = <<~'ERB'
  <%= turbo_frame_tag dom_id(comment) do %>
  <div class="comment" style="margin-left:<%= [comment.depth * 16, 64].min %>px">
    <div class="comment-meta">
      <span class="author"><%= comment.user&.username || "anon" %></span>
      <span> • <%= time_ago_in_words(comment.created_at) %> ago</span>
      <% if authenticated? %>
        •
        <%= link_to "reply", "#reply-#{comment.id}", style: "font-size:0.75rem;color:var(--text-dim)" %>
        <% if comment.user == Current.user %>
          <%= button_to "delete", comment, method: :delete, data: { turbo_confirm: "Delete?" }, class: "vote-btn", style: "font-size:0.7rem;color:var(--text-dim)" %>
        <% end %>
      <% end %>
    </div>
    <div class="comment-body"><%= comment.content %></div>

    <% if authenticated? %>
      <div id="reply-<%= comment.id %>" style="display:none;margin-top:8px">
        <%= form_with url: post_comments_path(comment.commentable.is_a?(Post) ? comment.commentable : comment.commentable), data: { turbo: true } do |f| %>
          <%= f.hidden_field :parent_id, value: comment.id %>
          <div class="field"><%= f.text_area :content, placeholder: "Reply...", rows: 3, style: "font-size:0.875rem" %></div>
          <%= f.submit "Reply", class: "btn", style: "padding:6px 14px;font-size:0.8rem" %>
        <% end %>
      </div>
    <% end %>

    <% comment.replies.best.each do |reply| %>
      <%= render "comments/comment", comment: reply %>
    <% end %>
  </div>
  <% end %>
ERB

views["app/views/communities/index.html.erb"] = <<~'ERB'
  <div class="main-col">
    <div class="page-header">
      <h1>Communities</h1>
      <% if authenticated? %><%= link_to "+ New", new_community_path, class: "btn" %><% end %>
    </div>

    <% if @communities.any? %>
      <% @communities.each do |c| %>
        <div class="post-card" style="padding:16px 20px;display:block">
          <div style="display:flex;align-items:center;justify-content:space-between">
            <div>
              <div style="font-weight:600;font-size:1rem"><%= link_to c.name, community_path(c), style: "color:var(--text)" %></div>
              <% if c.description.present? %>
                <div style="color:var(--text-dim);font-size:0.875rem;margin-top:4px"><%= c.description %></div>
              <% end %>
            </div>
            <div style="color:var(--text-dim);font-size:0.8rem"><%= c.posts.count %> posts</div>
          </div>
        </div>
      <% end %>
    <% else %>
      <div class="empty">No communities yet. <%= link_to "Create one", new_community_path if authenticated? %></div>
    <% end %>
  </div>

  <div class="side-col"></div>
ERB

views["app/views/communities/show.html.erb"] = <<~'ERB'
  <% content_for :title, @community.name %>

  <div class="main-col">
    <div style="background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:20px;margin-bottom:16px">
      <h1 style="font-size:1.4rem;margin-bottom:6px"><%= @community.name %></h1>
      <% if @community.description.present? %>
        <p style="color:var(--text-dim);font-size:0.9rem"><%= @community.description %></p>
      <% end %>
      <div style="margin-top:12px;display:flex;gap:12px;font-size:0.8rem;color:var(--text-dim)">
        <span><strong style="color:var(--text)"><%= @community.posts.count %></strong> posts</span>
      </div>
    </div>

    <% if authenticated? %>
      <div style="margin-bottom:16px"><%= link_to "+ New post in #{@community.name}", new_community_post_path(@community), class: "btn" %></div>
    <% end %>

    <% if @posts.any? %>
      <% @posts.each do |post| %>
        <%= render "posts/post", post: post %>
      <% end %>
    <% else %>
      <div class="empty">No posts yet in this community.</div>
    <% end %>
  </div>

  <div class="side-col">
    <div class="sidebar-card">
      <h3>About <%= @community.name %></h3>
      <p style="font-size:0.875rem;color:var(--text-dim)"><%= @community.description.presence || "No description." %></p>
      <% if authenticated? %>
        <div style="margin-top:12px"><%= link_to "New post", new_community_post_path(@community), class: "btn", style: "width:100%;text-align:center" %></div>
      <% end %>
    </div>
  </div>
ERB

views["app/views/communities/new.html.erb"] = <<~'ERB'
  <div class="form-wrap">
    <h1 style="margin-bottom:20px">New Community</h1>
    <%= form_with model: @community do |f| %>
      <% if @community.errors.any? %>
        <div class="flash-alert" style="grid-column:auto">
          <% @community.errors.full_messages.each do |msg| %><div><%= msg %></div><% end %>
        </div>
      <% end %>
      <div class="field">
        <%= f.label :name %>
        <%= f.text_field :name, placeholder: "e.g. bergen, tech, musikk" %>
      </div>
      <div class="field">
        <%= f.label :description %>
        <%= f.text_area :description, placeholder: "What is this community about?", rows: 3 %>
      </div>
      <div style="display:flex;gap:12px">
        <%= f.submit "Create", class: "btn" %>
        <%= link_to "Cancel", communities_path, class: "btn btn-ghost" %>
      </div>
    <% end %>
  </div>
ERB

views.each do |path, content|
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
  puts "  wrote #{path}"
end
RUBY

echo "==> [views] done"
