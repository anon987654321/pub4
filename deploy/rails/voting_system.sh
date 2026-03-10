```zsh
#!/usr/bin/env zsh
# Voting System Generator
# Universal voting and reviews for all Rails apps

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Usage: add_voting_to_app app_name

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

add_voting_system() {
  typeset app_name="${1:-${PWD##*/}}"
  log "Adding voting system to $app_name"

  install_voting_gems
  generate_voting_models
  create_voting_controllers
  create_voting_helpers
  add_voting_routes
  create_voting_stimulus

  log "Voting system added to $app_name"
}

install_voting_gems() {
  if ! grep -q "acts_as_votable" Gemfile; then
    cat >> Gemfile << 'EOF'

# Voting and Reviews
gem 'acts_as_votable', '~> 0.12.1'
gem 'public_activity', '~> 2.0.0'
EOF
    bundle install
  fi
}

generate_voting_models() {
  bin/rails generate model Review \
    user:references \
    rating:integer \
    title:string \
    body:text \
    helpful_count:integer:default=0 \
    verified_purchase:boolean:default=false

  bin/rails generate migration AddVotableToPosts

  bin/rails generate migration AddKarmaToUsers karma:integer:default=0
}

create_voting_controllers() {
  write_votes_controller
  write_reviews_controller
}

write_votes_controller() {
  cat > app/controllers/votes_controller.rb << 'EOF'
class VotesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_votable

  def upvote
    if @votable.upvote_by(current_user)
      update_karma(@votable.user, 1) if @votable.respond_to?(:user)
      respond_to_vote('upvoted')
    else
      respond_to_vote('already voted', :unprocessable_entity)
    end
  end

  def downvote
    if @votable.downvote_by(current_user)
      update_karma(@votable.user, -1) if @votable.respond_to?(:user)
      respond_to_vote('downvoted')
    else
      respond_to_vote('already voted', :unprocessable_entity)
    end
  end

  def unvote
    if @votable.unvote_by(current_user)
      respond_to_vote('vote removed')
    else
      respond_to_vote('already voted', :unprocessable_entity)
    end
  end

  private

  def set_votable
    @votable = params[:votable_type].constantize.find(params[:votable_id])
  rescue
    respond_to_vote('resource not found', :not_found)
  end

  def respond_to_vote(message, status = :ok)
    render json: { message: message }, status: status
  end

  def update_karma(user, delta)
    user.update(karma: user.karma + delta)
  end
end
EOF
}

write_reviews_controller() {
  cat > app/controllers/reviews_controller.rb << 'EOF'
class ReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_review, only: [:show, :edit, :update, :destroy]

  def index
    @reviews = Review.includes(:user).order(created_at: :desc).page(params[:page]).per(10)
  end

  def show
  end

  def new
    @review = Review.new
  end

  def edit
  end

  def create
    @review = Review.new(review_params)
    @review.user = current_user

    if @review.save
      redirect_to @review, notice: 'Review was successfully created.'
    else
      render :new
    end
  end

  def update
    if @review.update(review_params)
      redirect_to @review, notice: 'Review was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @review.destroy
    redirect_to reviews_url, notice: 'Review was successfully destroyed.'
  end

  private

  def set_review
    @review = Review.find(params[:id])
  end

  def review_params
    params.require(:review).permit(:user_id, :rating, :title, :body, :helpful_count, :verified_purchase)
  end
end
EOF
}

create_voting_helpers() {
  cat > app/helpers/votes_helper.rb << 'EOF'
module VotesHelper
  def current_user_voted?(votable)
    votable.votes.where(user_id: current_user.id).exists?
  end

  def vote_button(votable)
    if current_user_voted?(votable)
      button_tag "Unvote", type: 'button', class: 'btn btn-danger', data: { toggle: 'modal', target: '#unvoteModal' }
    else
      button_tag "Upvote", type: 'button', class: 'btn btn-primary', data: { toggle: 'modal', target: '#voteModal' }
    end
  end
end
EOF
}

add_voting_routes {
  cat >> config/routes.rb << 'EOF'
resources :reviews, only: [:index, :show, :new, :create, :edit, :update, :destroy]
EOF
}

create_voting_stimulus() {
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/vote_controller.js.erb << 'EOF'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    votableId: String,
    votableType: String
  }

  upvote() {
    fetch(`/votes/${this.votableType}/${this.votableId}/upvote`, {
      method: 'POST',
      headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content }
    })
    .then(response => response.json())
    .then(data => {
      if (data.message) {
        alert(data.message)
      }
    })
  }

  downvote() {
    fetch(`/votes/${this.votableType}/${this.votableId}/downvote`, {
      method: 'POST',
      headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content }
    })
    .then(response => response.json())
    .then(data => {
      if (data.message) {
        alert(data.message)
      }
    })
  }

  unvote() {
    fetch(`/votes/${this.votableType}/${this.votableId}/unvote`, {
      method: 'DELETE',
      headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content }
    })
    .then(response => response.json())
    .then(data => {
      if (data.message) {
        alert(data.message)
      }
    })
  }
}
EOF
}
EOF
```
