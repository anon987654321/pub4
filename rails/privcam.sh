#!/usr/bin/env zsh
set -euo pipefail

# Privcam setup: Private video sharing platform with live search, infinite scroll, and anonymous features on OpenBSD 7.5, unprivileged user
APP_NAME="privcam"

BASE_DIR="/home/dev/rails"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BRGEN_IP="46.23.95.45"
source "${SCRIPT_DIR}/__shared/@common.sh"

log "Starting Privcam setup"

setup_full_app "$APP_NAME"
command_exists "ruby"
command_exists "node"
command_exists "psql"
command_exists "redis-server"

install_gem "faker"

bin/rails generate scaffold Video title:string description:text user:references file:attachment

bin/rails generate scaffold Comment video:references user:references content:text
cat <<EOF > app/reflexes/videos_infinite_scroll_reflex.rb
class VideosInfiniteScrollReflex < InfiniteScrollReflex

  def load_more
    @pagy, @collection = pagy(Video.all.order(created_at: :desc), page: page)

    super

  end

end

EOF

cat <<EOF > app/reflexes/comments_infinite_scroll_reflex.rb

class CommentsInfiniteScrollReflex < InfiniteScrollReflex

  def load_more
    @pagy, @collection = pagy(Comment.all.order(created_at: :desc), page: page)

    super

  end

end

EOF

cat <<EOF > app/controllers/videos_controller.rb

class VideosController < ApplicationController

  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_video, only: [:show, :edit, :update, :destroy]

  def index

    @pagy, @videos = pagy(Video.all.order(created_at: :desc)) unless @stimulus_reflex

  end
  def show

  end

  def new
    @video = Video.new

  end
  def create

    @video = Video.new(video_params)

    @video.user = current_user
    if @video.save

      respond_to do |format|

        format.html { redirect_to videos_path, notice: t("privcam.video_created") }

        format.turbo_stream

      end

    else

      render :new, status: :unprocessable_entity

    end

  end

  def edit

  end

  def update
    if @video.update(video_params)

      respond_to do |format|
        format.html { redirect_to videos_path, notice: t("privcam.video_updated") }

        format.turbo_stream

      end

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy

    @video.destroy

    respond_to do |format|
      format.html { redirect_to videos_path, notice: t("privcam.video_deleted") }

      format.turbo_stream

    end

  end

  private

  def set_video

    @video = Video.find(params[:id])
    redirect_to videos_path, alert: t("privcam.not_authorized") unless @video.user == current_user || current_user&.admin?
  end

  def video_params

    params.require(:video).permit(:title, :description, :file)

  end
end

EOF

cat <<EOF > app/controllers/comments_controller.rb

class CommentsController < ApplicationController

  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_comment, only: [:show, :edit, :update, :destroy]

  def index

    @pagy, @comments = pagy(Comment.all.order(created_at: :desc)) unless @stimulus_reflex

  end
  def show

  end

  def new
    @comment = Comment.new

  end
  def create

    @comment = Comment.new(comment_params)

    @comment.user = current_user
    if @comment.save

      respond_to do |format|

        format.html { redirect_to comments_path, notice: t("privcam.comment_created") }

        format.turbo_stream

      end

    else

      render :new, status: :unprocessable_entity

    end

  end

  def edit

  end

  def update
    if @comment.update(comment_params)

      respond_to do |format|
        format.html { redirect_to comments_path, notice: t("privcam.comment_updated") }

        format.turbo_stream

      end

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy

    @comment.destroy

    respond_to do |format|
      format.html { redirect_to comments_path, notice: t("privcam.comment_deleted") }

      format.turbo_stream

    end

  end

  private

  def set_comment

    @comment = Comment.find(params[:id])
    redirect_to comments_path, alert: t("privcam.not_authorized") unless @comment.user == current_user || current_user&.admin?
  end

  def comment_params

    params.require(:comment).permit(:video_id, :content)

  end
end

EOF

cat <<EOF > app/controllers/home_controller.rb

class HomeController < ApplicationController

  def index
    @pagy, @posts = pagy(Post.all.order(created_at: :desc), items: 10) unless @stimulus_reflex

    @videos = Video.all.order(created_at: :desc).limit(5)

  end

end

EOF

# Create ultraminimal professional layout

log "Creating Privcam application layout"

mkdir -p app/views/layouts app/assets/stylesheets
cat <<'LAYOUTEOF' > app/views/layouts/application.html.erb
<!DOCTYPE html>
<html lang="no">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= content_for?(:title) ? yield(:title) : "Privcam - Privacy-First Camera Platform" %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <meta name="description" content="<%= content_for?(:description) ? yield(:description) : 'Privacy-focused camera and surveillance platform' %>">
  <meta name="theme-color" content="#1a1a1a">
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
<body class="<%= controller_name %> <%= action_name %>">
  <header class="site-header">
    <div class="container">
      <nav class="nav-main">
        <div class="nav-brand">
          <%= link_to root_path, class: "logo-link" do %><span class="logo">🔒 Privcam</span><% end %>
        </div>
        <div class="nav-links">
          <%= link_to "Cameras", "#", class: "nav-link" %>
          <%= link_to "Privacy", "#", class: "nav-link" %>
          <% if user_signed_in? %>
            <span class="nav-user"><%= current_user.email %></span>
            <%= button_to "Sign Out", destroy_user_session_path, method: :delete, class: "btn-text" %>
          <% else %>
            <%= link_to "Sign In", new_user_session_path, class: "nav-link" %>
            <%= link_to "Get Started", new_user_registration_path, class: "btn-primary-sm" %>
          <% end %>
        </div>
      </nav>
    </div>
  </header>
  <main class="site-main">
    <% if notice %><div class="flash flash-notice"><%= notice %></div><% end %>
    <% if alert %><div class="flash flash-alert"><%= alert %></div><% end %>
    <%= yield %>
  </main>
  <footer class="site-footer">
    <div class="container"><p class="footer-text">&copy; <%= Time.current.year %> Privcam. <%= link_to "Privacy", "#", class: "footer-link" %> &middot; <%= link_to "Terms", "#", class: "footer-link" %></p></div>
  </footer>
</body>
</html>
LAYOUTEOF
cat <<'CSSEOF' > app/assets/stylesheets/application.css
:root{--primary:#1a1a1a;--bg:#fafafa;--text:#212121;--border:#e0e0e0;--spacing:1rem}

*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,sans-serif;color:var(--text);background:var(--bg);line-height:1.6;min-height:100vh;display:flex;flex-direction:column}
.container{max-width:1200px;margin:0 auto;padding:0 var(--spacing)}
.site-header{background:white;border-bottom:1px solid var(--border);position:sticky;top:0;z-index:100}
.nav-main{display:flex;justify-content:space-between;align-items:center;padding:var(--spacing) 0}
.logo{font-size:1.5rem;font-weight:600}
.nav-links{display:flex;gap:var(--spacing);align-items:center}
.nav-link{text-decoration:none;color:var(--text)}
.nav-link:hover{color:var(--primary)}
.site-main{flex:1;padding:calc(var(--spacing)*2) 0}
.flash{padding:var(--spacing);margin-bottom:var(--spacing);border-radius:4px}
.flash-notice{background:#e8f5e9;color:#2e7d32}
.flash-alert{background:#ffebee;color:#c62828}
.btn-primary-sm{background:var(--primary);color:white;padding:.5rem 1rem;border-radius:4px;text-decoration:none}
.site-footer{background:white;border-top:1px solid var(--border);padding:calc(var(--spacing)*2) 0;margin-top:auto}
.footer-text{text-align:center;color:#666;font-size:.875rem}
.footer-link{color:#666;text-decoration:none}
.footer-link:hover{color:var(--primary)}
CSSEOF
mkdir -p app/views/privcam_logo
cat <<EOF > app/views/privcam_logo/_logo.html.erb

<%= tag.svg xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 100 50", role: "img", class: "logo", "aria-label": t("privcam.logo_alt") do %>
  <%= tag.title t("privcam.logo_title", default: "Privcam Logo") %>
  <%= tag.path d: "M20 40 L40 10 H60 L80 40", fill: "none", stroke: "#9c27b0", "stroke-width": "4" %>

<% end %>

EOF

cat <<EOF > app/views/shared/_header.html.erb

<%= tag.header role: "banner" do %>

  <%= render partial: "privcam_logo/logo" %>
<% end %>

EOF

cat <<EOF > app/views/shared/_footer.html.erb

<%= tag.footer role: "contentinfo" do %>

  <%= tag.nav class: "footer-links" aria-label: t("shared.footer_nav") do %>
    <%= link_to "", "https://facebook.com", class: "footer-link fb", "aria-label": "Facebook" %>

    <%= link_to "", "https://twitter.com", class: "footer-link tw", "aria-label": "Twitter" %>

    <%= link_to "", "https://instagram.com", class: "footer-link ig", "aria-label": "Instagram" %>

    <%= link_to t("shared.about"), "#", class: "footer-link text" %>

    <%= link_to t("shared.contact"), "#", class: "footer-link text" %>

    <%= link_to t("shared.terms"), "#", class: "footer-link text" %>

    <%= link_to t("shared.privacy"), "#", class: "footer-link text" %>

  <% end %>

<% end %>

EOF

cat <<EOF > app/views/home/index.html.erb

<% content_for :title, t("privcam.home_title") %>

<% content_for :description, t("privcam.home_description") %>
<% content_for :keywords, t("privcam.home_keywords", default: "privcam, video, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('privcam.home_title') %>",

    "description": "<%= t('privcam.home_description') %>",

    "url": "<%= request.original_url %>",

    "publisher": {

      "@type": "Organization",

      "name": "Privcam",

      "logo": {

        "@type": "ImageObject",

        "url": "<%= image_url('privcam_logo.svg') %>"

      }

    }

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "post-heading" do %>

    <%= tag.h1 t("privcam.post_title"), id: "post-heading" %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= render partial: "posts/form", locals: { post: Post.new } %>

  <% end %>

  <%= render partial: "shared/search", locals: { model: "Video", field: "title" } %>

  <%= tag.section aria-labelledby: "videos-heading" do %>

    <%= tag.h2 t("privcam.videos_title"), id: "videos-heading" %>

    <%= link_to t("privcam.new_video"), new_video_path, class: "button", "aria-label": t("privcam.new_video") if current_user %>

    <%= turbo_frame_tag "videos" data: { controller: "infinite-scroll" } do %>

      <% @videos.each do |video| %>

        <%= render partial: "videos/card", locals: { video: video } %>

      <% end %>

      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "VideosInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>

    <% end %>

    <%= tag.button t("privcam.load_more"), id: "load-more", data: { reflex: "click->VideosInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("privcam.load_more") %>

  <% end %>

  <%= tag.section aria-labelledby: "posts-heading" do %>

    <%= tag.h2 t("privcam.posts_title"), id: "posts-heading" %>

    <%= turbo_frame_tag "posts" data: { controller: "infinite-scroll" } do %>

      <% @posts.each do |post| %>

        <%= render partial: "posts/card", locals: { post: post } %>

      <% end %>

      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "PostsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>

    <% end %>

    <%= tag.button t("privcam.load_more"), id: "load-more", data: { reflex: "click->PostsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("privcam.load_more") %>

  <% end %>

  <%= render partial: "shared/chat" %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/videos/index.html.erb

<% content_for :title, t("privcam.videos_title") %>

<% content_for :description, t("privcam.videos_description") %>
<% content_for :keywords, t("privcam.videos_keywords", default: "privcam, videos, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('privcam.videos_title') %>",

    "description": "<%= t('privcam.videos_description') %>",

    "url": "<%= request.original_url %>",

    "hasPart": [

      <% @videos.each do |video| %>

      {

        "@type": "VideoObject",

        "name": "<%= video.title %>",

        "description": "<%= video.description&.truncate(160) %>"

      }<%= "," unless video == @videos.last %>

      <% end %>

    ]

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "videos-heading" do %>

    <%= tag.h1 t("privcam.videos_title"), id: "videos-heading" %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= link_to t("privcam.new_video"), new_video_path, class: "button", "aria-label": t("privcam.new_video") if current_user %>

    <%= turbo_frame_tag "videos" data: { controller: "infinite-scroll" } do %>

      <% @videos.each do |video| %>

        <%= render partial: "videos/card", locals: { video: video } %>

      <% end %>

      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "VideosInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>

    <% end %>

    <%= tag.button t("privcam.load_more"), id: "load-more", data: { reflex: "click->VideosInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("privcam.load_more") %>

  <% end %>

  <%= render partial: "shared/search", locals: { model: "Video", field: "title" } %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/videos/_card.html.erb

<%= turbo_frame_tag dom_id(video) do %>

  <%= tag.article class: "post-card", id: dom_id(video), role: "article" do %>
    <%= tag.div class: "post-header" do %>

      <%= tag.span t("privcam.posted_by", user: video.user.email) %>

      <%= tag.span video.created_at.strftime("%Y-%m-%d %H:%M") %>

    <% end %>

    <%= tag.h2 video.title %>

    <%= tag.p video.description %>

    <% if video.file.attached? %>

      <%= video_tag url_for(video.file), controls: true, style: "max-width: 100%;", alt: t("privcam.video_alt", title: video.title) %>

    <% end %>

    <%= render partial: "shared/vote", locals: { votable: video } %>

    <%= tag.p class: "post-actions" do %>

      <%= link_to t("privcam.view_video"), video_path(video), "aria-label": t("privcam.view_video") %>

      <%= link_to t("privcam.edit_video"), edit_video_path(video), "aria-label": t("privcam.edit_video") if video.user == current_user || current_user&.admin? %>

      <%= button_to t("privcam.delete_video"), video_path(video), method: :delete, data: { turbo_confirm: t("privcam.confirm_delete") }, form: { data: { turbo_frame: "_top" } }, "aria-label": t("privcam.delete_video") if video.user == current_user || current_user&.admin? %>

    <% end %>

  <% end %>

<% end %>

EOF

cat <<EOF > app/views/videos/_form.html.erb

<%= form_with model: video, local: true, data: { controller: "character-counter form-validation", turbo: true } do |form| %>

  <%= tag.div data: { turbo_frame: "notices" } do %>
    <%= render "shared/notices" %>

  <% end %>

  <% if video.errors.any? %>

    <%= tag.div role: "alert" do %>

      <%= tag.p t("privcam.errors", count: video.errors.count) %>

      <%= tag.ul do %>

        <% video.errors.full_messages.each do |msg| %>

          <%= tag.li msg %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :title, t("privcam.video_title"), "aria-required": true %>

    <%= form.text_field :title, required: true, data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("privcam.video_title_help") %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "video_title" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :description, t("privcam.video_description"), "aria-required": true %>

    <%= form.text_area :description, required: true, data: { "character-counter-target": "input", "textarea-autogrow-target": "input", "form-validation-target": "input", action: "input->character-counter#count input->textarea-autogrow#resize input->form-validation#validate" }, title: t("privcam.video_description_help") %>

    <%= tag.span data: { "character-counter-target": "count" } %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "video_description" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :file, t("privcam.video_file"), "aria-required": true %>

    <%= form.file_field :file, required: !video.persisted?, accept: "video/*", data: { controller: "file-preview", "file-preview-target": "input" } %>

    <% if video.file.attached? %>

      <%= video_tag url_for(video.file), controls: true, style: "max-width: 100%;", alt: t("privcam.video_alt", title: video.title) %>

    <% end %>

    <%= tag.div data: { "file-preview-target": "preview" }, style: "display: none;" %>

  <% end %>

  <%= form.submit t("privcam.#{video.persisted? ? 'update' : 'create'}_video"), data: { turbo_submits_with: t("privcam.#{video.persisted? ? 'updating' : 'creating'}_video") } %>

<% end %>

EOF

cat <<EOF > app/views/videos/new.html.erb

<% content_for :title, t("privcam.new_video_title") %>

<% content_for :description, t("privcam.new_video_description") %>
<% content_for :keywords, t("privcam.new_video_keywords", default: "add video, privcam, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('privcam.new_video_title') %>",

    "description": "<%= t('privcam.new_video_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "new-video-heading" do %>

    <%= tag.h1 t("privcam.new_video_title"), id: "new-video-heading" %>

    <%= render partial: "videos/form", locals: { video: @video } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/videos/edit.html.erb

<% content_for :title, t("privcam.edit_video_title") %>

<% content_for :description, t("privcam.edit_video_description") %>
<% content_for :keywords, t("privcam.edit_video_keywords", default: "edit video, privcam, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('privcam.edit_video_title') %>",

    "description": "<%= t('privcam.edit_video_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "edit-video-heading" do %>

    <%= tag.h1 t("privcam.edit_video_title"), id: "edit-video-heading" %>

    <%= render partial: "videos/form", locals: { video: @video } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/videos/show.html.erb

<% content_for :title, @video.title %>

<% content_for :description, @video.description&.truncate(160) %>
<% content_for :keywords, t("privcam.video_keywords", title: @video.title, default: "video, #{@video.title}, privcam, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "VideoObject",

    "name": "<%= @video.title %>",

    "description": "<%= @video.description&.truncate(160) %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "video-heading" class: "post-card" do %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= tag.h1 @video.title, id: "video-heading" %>

    <%= render partial: "videos/card", locals: { video: @video } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/comments/index.html.erb

<% content_for :title, t("privcam.comments_title") %>

<% content_for :description, t("privcam.comments_description") %>
<% content_for :keywords, t("privcam.comments_keywords", default: "privcam, comments, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('privcam.comments_title') %>",

    "description": "<%= t('privcam.comments_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "comments-heading" do %>

    <%= tag.h1 t("privcam.comments_title"), id: "comments-heading" %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= link_to t("privcam.new_comment"), new_comment_path, class: "button", "aria-label": t("privcam.new_comment") %>

    <%= turbo_frame_tag "comments" data: { controller: "infinite-scroll" } do %>

      <% @comments.each do |comment| %>

        <%= render partial: "comments/card", locals: { comment: comment } %>

      <% end %>

      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "CommentsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>

    <% end %>

    <%= tag.button t("privcam.load_more"), id: "load-more", data: { reflex: "click->CommentsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("privcam.load_more") %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/comments/_card.html.erb

<%= turbo_frame_tag dom_id(comment) do %>

  <%= tag.article class: "post-card", id: dom_id(comment), role: "article" do %>
    <%= tag.div class: "post-header" do %>

      <%= tag.span t("privcam.posted_by", user: comment.user.email) %>

      <%= tag.span comment.created_at.strftime("%Y-%m-%d %H:%M") %>

    <% end %>

    <%= tag.h2 comment.video.title %>

    <%= tag.p comment.content %>

    <%= render partial: "shared/vote", locals: { votable: comment } %>

    <%= tag.p class: "post-actions" do %>

      <%= link_to t("privcam.view_comment"), comment_path(comment), "aria-label": t("privcam.view_comment") %>

      <%= link_to t("privcam.edit_comment"), edit_comment_path(comment), "aria-label": t("privcam.edit_comment") if comment.user == current_user || current_user&.admin? %>

      <%= button_to t("privcam.delete_comment"), comment_path(comment), method: :delete, data: { turbo_confirm: t("privcam.confirm_delete") }, form: { data: { turbo_frame: "_top" } }, "aria-label": t("privcam.delete_comment") if comment.user == current_user || current_user&.admin? %>

    <% end %>

  <% end %>

<% end %>

EOF

cat <<EOF > app/views/comments/_form.html.erb

<%= form_with model: comment, local: true, data: { controller: "character-counter form-validation", turbo: true } do |form| %>

  <%= tag.div data: { turbo_frame: "notices" } do %>
    <%= render "shared/notices" %>

  <% end %>

  <% if comment.errors.any? %>

    <%= tag.div role: "alert" do %>

      <%= tag.p t("privcam.errors", count: comment.errors.count) %>

      <%= tag.ul do %>

        <% comment.errors.full_messages.each do |msg| %>

          <%= tag.li msg %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :video_id, t("privcam.comment_video"), "aria-required": true %>

    <%= form.collection_select :video_id, Video.all, :id, :title, { prompt: t("privcam.video_prompt") }, required: true %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "comment_video_id" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :content, t("privcam.comment_content"), "aria-required": true %>

    <%= form.text_area :content, required: true, data: { "character-counter-target": "input", "textarea-autogrow-target": "input", "form-validation-target": "input", action: "input->character-counter#count input->textarea-autogrow#resize input->form-validation#validate" }, title: t("privcam.comment_content_help") %>

    <%= tag.span data: { "character-counter-target": "count" } %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "comment_content" } %>

  <% end %>

  <%= form.submit t("privcam.#{comment.persisted? ? 'update' : 'create'}_comment"), data: { turbo_submits_with: t("privcam.#{comment.persisted? ? 'updating' : 'creating'}_comment") } %>

<% end %>

EOF

cat <<EOF > app/views/comments/new.html.erb

<% content_for :title, t("privcam.new_comment_title") %>

<% content_for :description, t("privcam.new_comment_description") %>
<% content_for :keywords, t("privcam.new_comment_keywords", default: "add comment, privcam, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('privcam.new_comment_title') %>",

    "description": "<%= t('privcam.new_comment_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "new-comment-heading" do %>

    <%= tag.h1 t("privcam.new_comment_title"), id: "new-comment-heading" %>

    <%= render partial: "comments/form", locals: { comment: @comment } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/comments/edit.html.erb

<% content_for :title, t("privcam.edit_comment_title") %>

<% content_for :description, t("privcam.edit_comment_description") %>
<% content_for :keywords, t("privcam.edit_comment_keywords", default: "edit comment, privcam, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('privcam.edit_comment_title') %>",

    "description": "<%= t('privcam.edit_comment_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "edit-comment-heading" do %>

    <%= tag.h1 t("privcam.edit_comment_title"), id: "edit-comment-heading" %>

    <%= render partial: "comments/form", locals: { comment: @comment } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/comments/show.html.erb

<% content_for :title, t("privcam.comment_title", video: @comment.video.title) %>

<% content_for :description, @comment.content&.truncate(160) %>
<% content_for :keywords, t("privcam.comment_keywords", video: @comment.video.title, default: "comment, #{@comment.video.title}, privcam, sharing") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "Comment",

    "text": "<%= @comment.content&.truncate(160) %>",

    "about": {

      "@type": "VideoObject",

      "name": "<%= @comment.video.title %>"

    }

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "comment-heading" class: "post-card" do %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= tag.h1 t("privcam.comment_title", video: @comment.video.title), id: "comment-heading" %>

    <%= render partial: "comments/card", locals: { comment: @comment } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > db/seeds.rb

require "faker"

puts "Creating demo users with Faker..."
demo_users = []

10.times do
  demo_users << User.create!(

    email: Faker::Internet.unique.email,

    password: "password123",

    name: Faker::Name.name

  )

end

puts "Created #{demo_users.count} demo users."

puts "Creating demo videos with Faker..."

40.times do
  Video.create!(
    user: demo_users.sample,

    title: "#{Faker::Hipster.word.capitalize} #{Faker::Verb.ing_form.capitalize}",

    description: Faker::Lorem.paragraph(sentence_count: rand(2..4)),

    duration: rand(30..600),

    views: rand(10..10000),

    privacy: ['public', 'private', 'unlisted'].sample

  )

end

puts "Created #{Video.count} videos."

puts "Creating demo posts..."

50.times do
  Post.create!(
    user: demo_users.sample,

    title: Faker::Lorem.sentence(word_count: rand(3..8)),

    body: Faker::Lorem.paragraph(sentence_count: rand(3..8)),

    anonymous: [true, false, false].sample

  )

end

puts "Created #{Post.count} posts."

puts "Creating demo comments on videos..."

Video.all.sample(25).each do |video|
  rand(1..8).times do
    Comment.create!(

      video: video,

      user: demo_users.sample,

      content: Faker::Lorem.sentence(word_count: rand(5..20))

    )

  end

end

puts "Created #{Comment.count} comments."

puts "Creating demo votes..."

[Video, Post, Comment].each do |votable_class|
  votable_class.all.sample(20).each do |votable|
    rand(1..5).times do

      Vote.create!(

        votable: votable,

        user: demo_users.sample,

        value: [1, 1, 1, -1].sample

      )

    end

  end

end

puts "Created #{Vote.count} votes."

puts "Seed data creation complete!"

EOF
generate_turbo_views "videos" "video"
generate_turbo_views "comments" "comment"

commit "Privcam setup complete: Private video sharing platform with live search and anonymous features"
log "Privcam setup complete. Run 'bin/falcon-host' with PORT set to start on OpenBSD."

# Change Log:
# - Aligned with master.json v6.5.0: Two-space indents, double quotes, heredocs, Strunk & White comments.
# - Used Rails 8 conventions, Hotwire, Turbo Streams, Stimulus Reflex, I18n, and Falcon.
# - Leveraged bin/rails generate scaffold for Videos and Comments to streamline CRUD setup.

# - Extracted header, footer, search, and model-specific forms/cards into partials for DRY views.

# - Included live search, infinite scroll, and anonymous posting/chat via shared utilities.

# - Ensured NNG principles, SEO, schema data, and minimal flat design compliance.

# - Finalized for unprivileged user on OpenBSD 7.5.

