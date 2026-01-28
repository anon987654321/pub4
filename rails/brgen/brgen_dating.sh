#!/usr/bin/env zsh
set -euo pipefail

# Brgen Dating setup: Location-based dating platform with matchmaking, Mapbox, live search, infinite scroll, and anonymous features on OpenBSD 7.5, unprivileged user

# Framework v37.3.2 compliant

APP_NAME="brgen_dating"

BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"

APP_PORT=$((10000 + RANDOM % 10000))

SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/@shared_functions.sh"

log "Starting Brgen Dating setup with enhanced matchmaking"

setup_full_app "$APP_NAME"

command_exists "ruby"

command_exists "node"

command_exists "psql"

# Redis optional - using Solid Cable for ActionCable (Rails 8 default)

install_gem "faker"

bin/rails generate scaffold Profile user:references bio:text location:string lat:decimal lng:decimal gender:string age:integer photos:attachments interests:text

bin/rails generate scaffold Match initiator:references{polymorphic} receiver:references{polymorphic} status:string

bin/rails generate model Dating::Like user:references liked_user:references

bin/rails generate model Dating::Dislike user:references disliked_user:references

# Add matchmaking service

mkdir -p app/services/dating

cat <<EOF > app/services/dating/matchmaking_service.rb

module Dating

  class MatchmakingService

    def self.find_matches(user)

      return [] unless user.profile

      # Get users who liked this user and this user also liked

      likes_given = user.dating_likes.pluck(:liked_user_id)

      likes_received = Dating::Like.where(liked_user_id: user.id).pluck(:user_id)

      mutual_likes = likes_given & likes_received

      # Create matches for mutual likes

      mutual_likes.each do |match_id|

        match_user = User.find(match_id)

        Match.find_or_create_by(

          initiator: user.profile,

          receiver: match_user.profile,

          status: 'matched'

        )

      end

      # Return potential matches based on location and interests

      find_potential_matches(user)

    end

    def self.find_potential_matches(user)

      return [] unless user.profile

      # Exclude already liked/disliked users

      excluded_ids = [user.id]

      excluded_ids += user.dating_likes.pluck(:liked_user_id)

      excluded_ids += user.dating_dislikes.pluck(:disliked_user_id)

      # Find profiles within reasonable distance and similar interests

      Profile.joins(:user)

             .where.not(user_id: excluded_ids)

             .where(gender: compatible_genders(user.profile.gender))

             .near([user.profile.lat, user.profile.lng], 50) # 50km radius

             .limit(10)

    end

    private

    def self.compatible_genders(user_gender)

      case user_gender

      when 'male' then ['female', 'non-binary']

      when 'female' then ['male', 'non-binary']

      when 'non-binary' then ['male', 'female', 'non-binary']

      else ['male', 'female', 'non-binary']

      end

    end

  end

end

EOF

# Enhanced Profile controller with matchmaking

mkdir -p app/controllers/dating

cat <<EOF > app/controllers/dating/profiles_controller.rb

module Dating

  class ProfilesController < ApplicationController

    before_action :set_profile, only: [:show, :edit, :update, :like, :dislike]

    before_action :authenticate_user!

    def index

      @profiles = MatchmakingService.find_potential_matches(current_user)

      @pagy, @profiles = pagy(@profiles) unless @stimulus_reflex

    end

    def show

    end

    def like

      Dating::Like.find_or_create_by(

        user: current_user,

        liked_user: @profile.user

      )

      # Check for match

      if Dating::Like.exists?(user: @profile.user, liked_user: current_user)

        Match.find_or_create_by(

          initiator: current_user.profile,

          receiver: @profile,

          status: 'matched'

        )

        flash[:notice] = "It's a match! 🎉"

      end

      redirect_to dating_profiles_path

    end

    def dislike

      Dating::Dislike.find_or_create_by(

        user: current_user,

        disliked_user: @profile.user

      )

      redirect_to dating_profiles_path

    end

    private

    def set_profile

      @profile = Profile.find(params[:id])

    end

  end

end

EOF

cat <<EOF > app/reflexes/profiles_infinite_scroll_reflex.rb

class ProfilesInfiniteScrollReflex < InfiniteScrollReflex

  def load_more

    @pagy, @collection = pagy(Profile.all.order(created_at: :desc), page: page)

    super

  end

end

EOF

cat <<EOF > app/reflexes/matches_infinite_scroll_reflex.rb

class MatchesInfiniteScrollReflex < InfiniteScrollReflex

  def load_more

    @pagy, @collection = pagy(Match.where(initiator: current_user.profile).or(Match.where(receiver: current_user.profile)).order(created_at: :desc), page: page)

    super

  end

end

EOF

generate_mapbox_controller "mapbox" 5.3467 60.3971 "profiles"

cat <<EOF > app/controllers/profiles_controller.rb

class ProfilesController < ApplicationController

  before_action :authenticate_user!

  before_action :set_profile, only: [:show, :edit, :update, :destroy]

  def index

    @pagy, @profiles = pagy(Profile.all.order(created_at: :desc)) unless @stimulus_reflex

  end

  def show

  end

  def new

    @profile = Profile.new

  end

  def create

    @profile = Profile.new(profile_params)

    @profile.user = current_user

    if @profile.save

      respond_to do |format|

        format.html { redirect_to profiles_path, notice: t("brgen_dating.profile_created") }

        format.turbo_stream

      end

    else

      render :new, status: :unprocessable_entity

    end

  end

  def edit

  end

  def update

    if @profile.update(profile_params)

      respond_to do |format|

        format.html { redirect_to profiles_path, notice: t("brgen_dating.profile_updated") }

        format.turbo_stream

      end

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy

    @profile.destroy

    respond_to do |format|

      format.html { redirect_to profiles_path, notice: t("brgen_dating.profile_deleted") }

      format.turbo_stream

    end

  end

  private

  def set_profile

    @profile = Profile.find(params[:id])

    redirect_to profiles_path, alert: t("brgen_dating.not_authorized") unless @profile.user == current_user || current_user&.admin?

  end

  def profile_params

    params.require(:profile).permit(:bio, :location, :lat, :lng, :gender, :age, photos: [])

  end

end

EOF

cat <<EOF > app/controllers/matches_controller.rb

class MatchesController < ApplicationController

  before_action :authenticate_user!

  before_action :set_match, only: [:show, :edit, :update, :destroy]

  def index

    @pagy, @matches = pagy(Match.where(initiator: current_user.profile).or(Match.where(receiver: current_user.profile)).order(created_at: :desc)) unless @stimulus_reflex

  end

  def show

  end

  def new

    @match = Match.new

  end

  def create

    @match = Match.new(match_params)

    @match.initiator = current_user.profile

    if @match.save

      respond_to do |format|

        format.html { redirect_to matches_path, notice: t("brgen_dating.match_created") }

        format.turbo_stream

      end

    else

      render :new, status: :unprocessable_entity

    end

  end

  def edit

  end

  def update

    if @match.update(match_params)

      respond_to do |format|

        format.html { redirect_to matches_path, notice: t("brgen_dating.match_updated") }

        format.turbo_stream

      end

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy

    @match.destroy

    respond_to do |format|

      format.html { redirect_to matches_path, notice: t("brgen_dating.match_deleted") }

      format.turbo_stream

    end

  end

  private

  def set_match

    @match = Match.where(initiator: current_user.profile).or(Match.where(receiver: current_user.profile)).find(params[:id])

    redirect_to matches_path, alert: t("brgen_dating.not_authorized") unless @match.initiator == current_user.profile || @match.receiver == current_user.profile || current_user&.admin?

  end

  def match_params

    params.require(:match).permit(:receiver_id, :status)

  end

end

EOF

cat <<EOF > app/controllers/home_controller.rb

class HomeController < ApplicationController

  def index

    @pagy, @posts = pagy(Post.all.order(created_at: :desc), items: 10) unless @stimulus_reflex

    @profiles = Profile.all.order(created_at: :desc).limit(5)

  end

end

EOF

mkdir -p app/views/brgen_dating_logo

cat <<'EOF' > app/assets/stylesheets/application.css

:root {

  --primary: #e91e63;

  --secondary: #5f6368;

  --bg: #ffffff;

  --surface: #f8f9fa;

  --text: #202124;

  --border: #dadce0;

  --spacing: 1rem;

}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {

  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;

  line-height: 1.6;

  color: var(--text);

  background: var(--bg);

}

main { max-width: 600px; margin: 0 auto; padding: var(--spacing); }

.profile-card {

  background: var(--surface);

  border: 1px solid var(--border);

  border-radius: 8px;

  padding: calc(var(--spacing) * 2);

  text-align: center;

}

.profile-card img {

  width: 200px;

  height: 200px;

  border-radius: 50%;

  object-fit: cover;

  margin-bottom: var(--spacing);

}

.actions {

  display: flex;

  gap: var(--spacing);

  justify-content: center;

  margin-top: calc(var(--spacing) * 2);

}

.button {

  width: 60px;

  height: 60px;

  border-radius: 50%;

  border: none;

  cursor: pointer;

  font-size: 1.5rem;

  display: flex;

  align-items: center;

  justify-content: center;

}

.button.like { background: var(--primary); color: white; }

.button.pass { background: var(--surface); border: 2px solid var(--border); }

.button.super { background: #2196f3; color: white; }

.matches { display: grid; gap: var(--spacing); grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); }

.match-card { text-align: center; }

.match-card img { width: 100%; aspect-ratio: 1; border-radius: 8px; object-fit: cover; }

@media (max-width: 768px) {

  main { padding: calc(var(--spacing) / 2); }

}

EOF

cat <<EOF > app/views/brgen_dating_logo/_logo.html.erb

<%= tag.svg xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 100 50", role: "img", class: "logo", "aria-label": t("brgen_dating.logo_alt") do %>

  <%= tag.title t("brgen_dating.logo_title", default: "Brgen Dating Logo") %>

  <%= tag.path d: "M50 15 C70 5, 90 25, 50 45 C10 25, 30 5, 50 15", fill: "#e91e63", stroke: "#1a73e8", "stroke-width": "2" %>

<% end %>

EOF

cat <<EOF > app/views/shared/_header.html.erb

<%= tag.header role: "banner" do %>

  <%= render partial: "brgen_dating_logo/logo" %>

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

<% content_for :title, t("brgen_dating.home_title") %>

<% content_for :description, t("brgen_dating.home_description") %>

<% content_for :keywords, t("brgen_dating.home_keywords", default: "brgen dating, profiles, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('brgen_dating.home_title') %>",

    "description": "<%= t('brgen_dating.home_description') %>",

    "url": "<%= request.original_url %>",

    "publisher": {

      "@type": "Organization",

      "name": "Brgen Dating",

      "logo": {

        "@type": "ImageObject",

        "url": "<%= image_url('brgen_dating_logo.svg') %>"

      }

    }

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "post-heading" do %>

    <%= tag.h1 t("brgen_dating.post_title"), id: "post-heading" %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= render partial: "posts/form", locals: { post: Post.new } %>

  <% end %>

  <%= tag.section aria-labelledby: "map-heading" do %>

    <%= tag.h2 t("brgen_dating.map_title"), id: "map-heading" %>

    <%= tag.div id: "map" data: { controller: "mapbox", "mapbox-api-key-value": ENV["MAPBOX_API_KEY"], "mapbox-profiles-value": @profiles.to_json } %>

  <% end %>

  <%= render partial: "shared/search", locals: { model: "Profile", field: "bio" } %>

  <%= tag.section aria-labelledby: "profiles-heading" do %>

    <%= tag.h2 t("brgen_dating.profiles_title"), id: "profiles-heading" %>

    <%= link_to t("brgen_dating.new_profile"), new_profile_path, class: "button", "aria-label": t("brgen_dating.new_profile") if current_user %>

    <%= turbo_frame_tag "profiles" data: { controller: "infinite-scroll" } do %>

      <% @profiles.each do |profile| %>

        <%= render partial: "profiles/card", locals: { profile: profile } %>

      <% end %>

      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "ProfilesInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>

    <% end %>

    <%= tag.button t("brgen_dating.load_more"), id: "load-more", data: { reflex: "click->ProfilesInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_dating.load_more") %>

  <% end %>

  <%= tag.section aria-labelledby: "posts-heading" do %>

    <%= tag.h2 t("brgen_dating.posts_title"), id: "posts-heading" %>

    <%= turbo_frame_tag "posts" data: { controller: "infinite-scroll" } do %>

      <% @posts.each do |post| %>

        <%= render partial: "posts/card", locals: { post: post } %>

      <% end %>

      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "PostsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>

    <% end %>

    <%= tag.button t("brgen_dating.load_more"), id: "load-more", data: { reflex: "click->PostsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_dating.load_more") %>

  <% end %>

  <%= render partial: "shared/chat" %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/profiles/index.html.erb

<% content_for :title, t("brgen_dating.profiles_title") %>

<% content_for :description, t("brgen_dating.profiles_description") %>

<% content_for :keywords, t("brgen_dating.profiles_keywords", default: "brgen dating, profiles, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('brgen_dating.profiles_title') %>",

    "description": "<%= t('brgen_dating.profiles_description') %>",

    "url": "<%= request.original_url %>",

    "hasPart": [

      <% @profiles.each do |profile| %>

      {

        "@type": "Person",

        "name": "<%= profile.user.email %>",

        "description": "<%= profile.bio&.truncate(160) %>",

        "address": {

          "@type": "PostalAddress",

          "addressLocality": "<%= profile.location %>"

        }

      }<%= "," unless profile == @profiles.last %>

      <% end %>

    ]

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "profiles-heading" do %>

    <%= tag.h1 t("brgen_dating.profiles_title"), id: "profiles-heading" %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= link_to t("brgen_dating.new_profile"), new_profile_path, class: "button", "aria-label": t("brgen_dating.new_profile") if current_user %>

    <%= turbo_frame_tag "profiles" data: { controller: "infinite-scroll" } do %>

      <% @profiles.each do |profile| %>

        <%= render partial: "profiles/card", locals: { profile: profile } %>

      <% end %>

      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "ProfilesInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>

    <% end %>

    <%= tag.button t("brgen_dating.load_more"), id: "load-more", data: { reflex: "click->ProfilesInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_dating.load_more") %>

  <% end %>

  <%= render partial: "shared/search", locals: { model: "Profile", field: "bio" } %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/profiles/_card.html.erb

<%= turbo_frame_tag dom_id(profile) do %>

  <%= tag.article class: "post-card", id: dom_id(profile), role: "article" do %>

    <%= tag.div class: "post-header" do %>

      <%= tag.span t("brgen_dating.posted_by", user: profile.user.email) %>

      <%= tag.span profile.created_at.strftime("%Y-%m-%d %H:%M") %>

    <% end %>

    <%= tag.h2 profile.user.email %>

    <%= tag.p profile.bio %>

    <%= tag.p t("brgen_dating.profile_location", location: profile.location) %>

    <%= tag.p t("brgen_dating.profile_gender", gender: profile.gender) %>

    <%= tag.p t("brgen_dating.profile_age", age: profile.age) %>

    <% if profile.photos.attached? %>

      <% profile.photos.each do |photo| %>

        <%= image_tag photo, style: "max-width: 200px;", alt: t("brgen_dating.profile_photo", email: profile.user.email) %>

      <% end %>

    <% end %>

    <%= render partial: "shared/vote", locals: { votable: profile } %>

    <%= tag.p class: "post-actions" do %>

      <%= link_to t("brgen_dating.view_profile"), profile_path(profile), "aria-label": t("brgen_dating.view_profile") %>

      <%= link_to t("brgen_dating.edit_profile"), edit_profile_path(profile), "aria-label": t("brgen_dating.edit_profile") if profile.user == current_user || current_user&.admin? %>

      <%= button_to t("brgen_dating.delete_profile"), profile_path(profile), method: :delete, data: { turbo_confirm: t("brgen_dating.confirm_delete") }, form: { data: { turbo_frame: "_top" } }, "aria-label": t("brgen_dating.delete_profile") if profile.user == current_user || current_user&.admin? %>

    <% end %>

  <% end %>

<% end %>

EOF

cat <<EOF > app/views/profiles/_form.html.erb

<%= form_with model: profile, local: true, data: { controller: "character-counter form-validation", turbo: true } do |form| %>

  <%= tag.div data: { turbo_frame: "notices" } do %>

    <%= render "shared/notices" %>

  <% end %>

  <% if profile.errors.any? %>

    <%= tag.div role: "alert" do %>

      <%= tag.p t("brgen_dating.errors", count: profile.errors.count) %>

      <%= tag.ul do %>

        <% profile.errors.full_messages.each do |msg| %>

          <%= tag.li msg %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :bio, t("brgen_dating.profile_bio"), "aria-required": true %>

    <%= form.text_area :bio, required: true, data: { "character-counter-target": "input", "textarea-autogrow-target": "input", "form-validation-target": "input", action: "input->character-counter#count input->textarea-autogrow#resize input->form-validation#validate" }, title: t("brgen_dating.profile_bio_help") %>

    <%= tag.span data: { "character-counter-target": "count" } %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "profile_bio" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :location, t("brgen_dating.profile_location"), "aria-required": true %>

    <%= form.text_field :location, required: true, data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("brgen_dating.profile_location_help") %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "profile_location" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :lat, t("brgen_dating.profile_lat"), "aria-required": true %>

    <%= form.number_field :lat, required: true, step: "any", data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("brgen_dating.profile_lat_help") %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "profile_lat" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :lng, t("brgen_dating.profile_lng"), "aria-required": true %>

    <%= form.number_field :lng, required: true, step: "any", data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("brgen_dating.profile_lng_help") %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "profile_lng" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :gender, t("brgen_dating.profile_gender"), "aria-required": true %>

    <%= form.text_field :gender, required: true, data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("brgen_dating.profile_gender_help") %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "profile_gender" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :age, t("brgen_dating.profile_age"), "aria-required": true %>

    <%= form.number_field :age, required: true, data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("brgen_dating.profile_age_help") %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "profile_age" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :photos, t("brgen_dating.profile_photos") %>

    <%= form.file_field :photos, multiple: true, accept: "image/*", data: { controller: "file-preview", "file-preview-target": "input" } %>

    <% if profile.photos.attached? %>

      <% profile.photos.each do |photo| %>

        <%= image_tag photo, style: "max-width: 200px;", alt: t("brgen_dating.profile_photo", email: profile.user.email) %>

      <% end %>

    <% end %>

    <%= tag.div data: { "file-preview-target": "preview" }, style: "display: none;" %>

  <% end %>

  <%= form.submit t("brgen_dating.#{profile.persisted? ? 'update' : 'create'}_profile"), data: { turbo_submits_with: t("brgen_dating.#{profile.persisted? ? 'updating' : 'creating'}_profile") } %>

<% end %>

EOF

cat <<EOF > app/views/profiles/new.html.erb

<% content_for :title, t("brgen_dating.new_profile_title") %>

<% content_for :description, t("brgen_dating.new_profile_description") %>

<% content_for :keywords, t("brgen_dating.new_profile_keywords", default: "add profile, brgen dating, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('brgen_dating.new_profile_title') %>",

    "description": "<%= t('brgen_dating.new_profile_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "new-profile-heading" do %>

    <%= tag.h1 t("brgen_dating.new_profile_title"), id: "new-profile-heading" %>

    <%= render partial: "profiles/form", locals: { profile: @profile } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/profiles/edit.html.erb

<% content_for :title, t("brgen_dating.edit_profile_title") %>

<% content_for :description, t("brgen_dating.edit_profile_description") %>

<% content_for :keywords, t("brgen_dating.edit_profile_keywords", default: "edit profile, brgen dating, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('brgen_dating.edit_profile_title') %>",

    "description": "<%= t('brgen_dating.edit_profile_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "edit-profile-heading" do %>

    <%= tag.h1 t("brgen_dating.edit_profile_title"), id: "edit-profile-heading" %>

    <%= render partial: "profiles/form", locals: { profile: @profile } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/profiles/show.html.erb

<% content_for :title, @profile.user.email %>

<% content_for :description, @profile.bio&.truncate(160) %>

<% content_for :keywords, t("brgen_dating.profile_keywords", email: @profile.user.email, default: "profile, #{@profile.user.email}, brgen dating, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "Person",

    "name": "<%= @profile.user.email %>",

    "description": "<%= @profile.bio&.truncate(160) %>",

    "address": {

      "@type": "PostalAddress",

      "addressLocality": "<%= @profile.location %>"

    }

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "profile-heading" class: "post-card" do %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= tag.h1 @profile.user.email, id: "profile-heading" %>

    <%= render partial: "profiles/card", locals: { profile: @profile } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/matches/index.html.erb

<% content_for :title, t("brgen_dating.matches_title") %>

<% content_for :description, t("brgen_dating.matches_description") %>

<% content_for :keywords, t("brgen_dating.matches_keywords", default: "brgen dating, matches, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('brgen_dating.matches_title') %>",

    "description": "<%= t('brgen_dating.matches_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "matches-heading" do %>

    <%= tag.h1 t("brgen_dating.matches_title"), id: "matches-heading" %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= link_to t("brgen_dating.new_match"), new_match_path, class: "button", "aria-label": t("brgen_dating.new_match") %>

    <%= turbo_frame_tag "matches" data: { controller: "infinite-scroll" } do %>

      <% @matches.each do |match| %>

        <%= render partial: "matches/card", locals: { match: match } %>

      <% end %>

      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "MatchesInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>

    <% end %>

    <%= tag.button t("brgen_dating.load_more"), id: "load-more", data: { reflex: "click->MatchesInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_dating.load_more") %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/matches/_card.html.erb

<%= turbo_frame_tag dom_id(match) do %>

  <%= tag.article class: "post-card", id: dom_id(match), role: "article" do %>

    <%= tag.div class: "post-header" do %>

      <%= tag.span t("brgen_dating.initiated_by", user: match.initiator.user.email) %>

      <%= tag.span match.created_at.strftime("%Y-%m-%d %H:%M") %>

    <% end %>

    <%= tag.h2 match.receiver.user.email %>

    <%= tag.p t("brgen_dating.match_status", status: match.status) %>

    <%= render partial: "shared/vote", locals: { votable: match } %>

    <%= tag.p class: "post-actions" do %>

      <%= link_to t("brgen_dating.view_match"), match_path(match), "aria-label": t("brgen_dating.view_match") %>

      <%= link_to t("brgen_dating.edit_match"), edit_match_path(match), "aria-label": t("brgen_dating.edit_match") if match.initiator == current_user.profile || match.receiver == current_user.profile || current_user&.admin? %>

      <%= button_to t("brgen_dating.delete_match"), match_path(match), method: :delete, data: { turbo_confirm: t("brgen_dating.confirm_delete") }, form: { data: { turbo_frame: "_top" } }, "aria-label": t("brgen_dating.delete_match") if match.initiator == current_user.profile || match.receiver == current_user.profile || current_user&.admin? %>

    <% end %>

  <% end %>

<% end %>

EOF

cat <<EOF > app/views/matches/_form.html.erb

<%= form_with model: match, local: true, data: { controller: "form-validation", turbo: true } do |form| %>

  <%= tag.div data: { turbo_frame: "notices" } do %>

    <%= render "shared/notices" %>

  <% end %>

  <% if match.errors.any? %>

    <%= tag.div role: "alert" do %>

      <%= tag.p t("brgen_dating.errors", count: match.errors.count) %>

      <%= tag.ul do %>

        <% match.errors.full_messages.each do |msg| %>

          <%= tag.li msg %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :receiver_id, t("brgen_dating.match_receiver"), "aria-required": true %>

    <%= form.collection_select :receiver_id, Profile.all, :id, :user_email, { prompt: t("brgen_dating.receiver_prompt") }, required: true %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "match_receiver_id" } %>

  <% end %>

  <%= tag.fieldset do %>

    <%= form.label :status, t("brgen_dating.match_status"), "aria-required": true %>

    <%= form.select :status, ["pending", "accepted", "rejected"], { prompt: t("brgen_dating.status_prompt"), selected: match.status }, required: true %>

    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "match_status" } %>

  <% end %>

  <%= form.submit t("brgen_dating.#{match.persisted? ? 'update' : 'create'}_match"), data: { turbo_submits_with: t("brgen_dating.#{match.persisted? ? 'updating' : 'creating'}_match") } %>

<% end %>

EOF

cat <<EOF > app/views/matches/new.html.erb

<% content_for :title, t("brgen_dating.new_match_title") %>

<% content_for :description, t("brgen_dating.new_match_description") %>

<% content_for :keywords, t("brgen_dating.new_match_keywords", default: "add match, brgen dating, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('brgen_dating.new_match_title') %>",

    "description": "<%= t('brgen_dating.new_match_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "new-match-heading" do %>

    <%= tag.h1 t("brgen_dating.new_match_title"), id: "new-match-heading" %>

    <%= render partial: "matches/form", locals: { match: @match } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/matches/edit.html.erb

<% content_for :title, t("brgen_dating.edit_match_title") %>

<% content_for :description, t("brgen_dating.edit_match_description") %>

<% content_for :keywords, t("brgen_dating.edit_match_keywords", default: "edit match, brgen dating, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "WebPage",

    "name": "<%= t('brgen_dating.edit_match_title') %>",

    "description": "<%= t('brgen_dating.edit_match_description') %>",

    "url": "<%= request.original_url %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "edit-match-heading" do %>

    <%= tag.h1 t("brgen_dating.edit_match_title"), id: "edit-match-heading" %>

    <%= render partial: "matches/form", locals: { match: @match } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

cat <<EOF > app/views/matches/show.html.erb

<% content_for :title, t("brgen_dating.match_title", receiver: @match.receiver.user.email) %>

<% content_for :description, t("brgen_dating.match_description", receiver: @match.receiver.user.email) %>

<% content_for :keywords, t("brgen_dating.match_keywords", receiver: @match.receiver.user.email, default: "match, #{@match.receiver.user.email}, brgen dating, matchmaking") %>

<% content_for :schema do %>

  <script type="application/ld+json">

  {

    "@context": "https://schema.org",

    "@type": "Person",

    "name": "<%= @match.receiver.user.email %>",

    "description": "<%= @match.receiver.bio&.truncate(160) %>"

  }

  </script>

<% end %>

<%= render "shared/header" %>

<%= tag.main role: "main" do %>

  <%= tag.section aria-labelledby: "match-heading" class: "post-card" do %>

    <%= tag.div data: { turbo_frame: "notices" } do %>

      <%= render "shared/notices" %>

    <% end %>

    <%= tag.h1 t("brgen_dating.match_title", receiver: @match.receiver.user.email), id: "match-heading" %>

    <%= render partial: "matches/card", locals: { match: @match } %>

  <% end %>

<% end %>

<%= render "shared/footer" %>

EOF

generate_turbo_views "profiles" "profile"

generate_turbo_views "matches" "match"

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

puts "Creating demo profiles with Faker..."

genders = ['male', 'female', 'non-binary']

locations = ['Bergen', 'Oslo', 'Stavanger', 'Trondheim', 'Åsane']

base_coords = { 'Bergen' => [60.3913, 5.3221], 'Oslo' => [59.9139, 10.7522], 'Stavanger' => [58.9700, 5.7331], 'Trondheim' => [63.4305, 10.3951], 'Åsane' => [60.4650, 5.3220] }

demo_users.each do |user|

  location = locations.sample

  coords = base_coords[location]

  Profile.create!(

    user: user,

    bio: Faker::Lorem.paragraph(sentence_count: 3),

    location: location,

    lat: coords[0] + rand(-0.05..0.05),

    lng: coords[1] + rand(-0.05..0.05),

    gender: genders.sample,

    age: rand(22..45),

    interests: [Faker::Hobby.activity, Faker::Hobby.activity, Faker::Hobby.activity].join(', ')

  )

end

puts "Created #{Profile.count} demo profiles."

puts "Creating demo matches with Faker..."

profiles = Profile.all.to_a

20.times do

  initiator = profiles.sample

  receiver = profiles.sample

  next if initiator == receiver

  Match.create!(

    initiator: initiator,

    receiver: receiver,

    status: ['pending', 'matched', 'rejected'].sample

  )

end

puts "Created #{Match.count} demo matches."

puts "Creating demo likes and dislikes..."

30.times do

  user = demo_users.sample

  liked_user = demo_users.sample

  next if user == liked_user

  Dating::Like.create!(

    user: user,

    liked_user: liked_user

  )

end

20.times do

  user = demo_users.sample

  disliked_user = demo_users.sample

  next if user == disliked_user

  Dating::Dislike.create!(

    user: user,

    disliked_user: disliked_user

  )

end

puts "Created #{Dating::Like.count} likes and #{Dating::Dislike.count} dislikes."

puts "Seed data creation complete!"

EOF

commit "Brgen Dating setup complete: Location-based dating platform with Mapbox, live search, and anonymous features"

log "Brgen Dating setup complete. Run 'bin/falcon-host' with PORT set to start on OpenBSD."

# Change Log:

# - Aligned with master.json v6.5.0: Two-space indents, double quotes, heredocs, Strunk & White comments.

# - Used Rails 8 conventions, Hotwire, Turbo Streams, Stimulus Reflex, I18n, and Falcon.

# - Leveraged bin/rails generate scaffold for Profiles and Matches to streamline CRUD setup.

# - Extracted header, footer, search, and model-specific forms/cards into partials for DRY views.

# - Included Mapbox for profile locations, live search, infinite scroll, and anonymous posting/chat via shared utilities.

# - Ensured NNG principles, SEO, schema data, and minimal flat design compliance.

# - Finalized for unprivileged user on OpenBSD 7.5.
