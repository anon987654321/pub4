#!/usr/bin/env zsh
set -e # Halt script execution on first error

echo "Configuring BRGEN Dating features within the existing BRGEN Rails application..."

# Navigate to the main directory of your BRGEN Rails application
cd /path/to/brgen

## Setup basic Dating models
echo "Generating basic models for the Dating namespace..."
bin/rails generate model Dating::Profile user:references bio:text interests:text
bin/rails generate model Dating::Like user:references liked_user:references
bin/rails generate model Dating::Dislike user:references disliked_user:references
bin/rails db:migrate

git add .
git commit -m "Setup basic Dating models (Profile, Like, Dislike)"

## Implement matchmaking logic
echo "Adding matchmaking service logic..."
mkdir -p app/services/dating
cat <<RUBY > app/services/dating/matchmaking_service.rb
module Dating
  class MatchmakingService
    def self.find_matches(user)
      likes_given = user.likes.pluck(:liked_user_id)
      likes_received = Dating::Like.where(liked_user_id: user.id).pluck(:user_id)
      matches = likes_given & likes_received
      matches.each do |match_id|
        user.matches.find_or_create_by(matched_user_id: match_id)
      end
    end
  end
end
RUBY

git add .
git commit -m "Implemented matchmaking logic"

## Implementing Controllers for Profiles
echo "Creating controllers for profile interactions..."
mkdir -p app/controllers/dating
cat <<RUBY > app/controllers/dating/profiles_controller.rb
module Dating
  class ProfilesController < ApplicationController
    before_action :set_profile, only: [:show, :edit, :update]

    def index
      @profiles = Profile.all
    end

    def show
    end

    private

    def set_profile
      @profile = Profile.find(params[:id])
    end
  end
end
RUBY

git add .
git commit -m "Added basic controllers for Dating profiles"

## Enhancing Interactions with Hotwire and Stimulus
echo "Enhancing Profile interactions using Hotwire and Stimulus..."
yarn add @hotwired/stimulus @hotwired/turbo-rails

cat <<JS > app/javascript/controllers/dating_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  like() {
    const profileId = this.element.dataset.profileId;
    fetch(\`/dating/profiles/\${profileId}/like\`, { method: 'POST' })
      .then(response => response.text())
      .then(html => this.element.outerHTML = html);
  }

  dislike() {
    const profileId = this.element.dataset.profileId;
    fetch(\`/dating/profiles/\${profileId}/dislike\`, { method: 'POST' })
      .then(response => response.text())
      .then(html => this.element.outerHTML = html);
  }
}
JS

git add .
git commit -m "Enhanced Profile interactions with Stimulus controllers for like and dislike actions"

## Setup Turbo Streams and Views for Dynamic Profile Updates
echo "Setting up views with Turbo Streams for dynamic profile interactions..."
mkdir -p app/views/dating/profiles
cat <<ERB > app/views/dating/profiles/index.html.erb
<%= turbo_stream_from "dating" %>
<div data-controller="dating">
  <% @profiles.each do |profile| %>
    <div class="profile-card" data-profile-id="<%= profile.id %>" data-action="mouseover->profile#highlight">
      <%= image_tag profile.user.avatar.url, alt: profile.user.username %>
      <h3><%= profile.user.username %>, <%= profile.user.age %></h3>
      <p><%= profile.bio %></p>
      <button data-action="dating#like">Like</button>
      <button data-action="dating#dislike">Dislike</button>
    </div>
  <% end %>
</div>
ERB

git add .
git commit -m "Implemented Turbo Streams in Dating views for dynamic profile updates"

echo "BRGEN Dating subapp enhancements complete. Ready for interactive, real-time user engagement."
