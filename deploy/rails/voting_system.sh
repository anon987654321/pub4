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
gem 'acts_as_votable'
gem 'public_activity'
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
    helpful_count:integer \
    verified_purchase:boolean

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
      respond_to_vote('vote not found', :unprocessable_entity)
    end
  end

  private

  def set_votable
    @votable = params[:votable_type].constantize.find(params[:votable_id])
  rescue NameError
    render json: { error: 'Invalid votable type' }, status: :unprocessable_entity
  end

  def update_karma(user, amount)
    user.update(karma: user.karma + amount)
  end

  def respond_to_vote(message, status = :ok)
    respond_to do |format|
      format.json { render json: { message: message }, status: status }
      format.html { redirect_back fallback_location: root_path, notice: message }
    end
  end
end
EOF
}

write_reviews_controller() {
  cat > app/controllers/reviews_controller.rb << 'EOF'
class ReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_review, only: [:show, :edit, :update, :destroy, :mark_helpful]

  def create
    @review = current_user.reviews.new(review_params)
    @review.verified_purchase = current_user.purchased?(@review.product) if @review.respond_to?(:product)

    if @review.save
      redirect_to @review, notice: 'Review was successfully created.'
    else
      render :new
    end
  end

  def mark_helpful
    if current_user.voted_for?(@review)
      redirect_to @review, alert: 'You have already voted for this review.'
    else
      @review.upvote_by(current_user)
      redirect_to @review, notice: 'Marked as helpful.'
    end
  end

  private

  def set_review
    @review = Review.find(params[:id])
  end

  def review_params
    params.require(:review).permit(:rating, :title, :body, :product_id)
  end
end
EOF
}

create_voting_helpers() {
  cat > app/helpers/votes_helper.rb << 'EOF'
module VotesHelper
  def vote_button(votable, type: :upvote)
    return unless user_signed_in?

    button_to send("#{type}_vote_path",
                  votable_type: votable.class.name,
                  votable_id: votable.id),
              method: :post,
              class: "vote-btn #{type}",
              data: { turbo: false } do
      content_tag(:span, "#{type.to_s.titleize}")
    end
  end
end
EOF
}

add_voting_routes() {
  cat >> config/routes.rb << 'EOF'

  resources :votes, only: [] do
    post :upvote, on: :collection
    post :downvote, on: :collection
    delete :unvote, on: :collection
  end

  resources :reviews do
    member do
      post :mark_helpful
    end
  end
EOF
}

create_voting_stimulus() {
  cat > app/javascript/controllers/voting_controller.js << 'EOF'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count"]

  connect() {
    this.csrfToken = document.querySelector("[name='csrf-token']").content
  }

  async vote(event) {
    event.preventDefault()

    const form = event.target
    const url = form.action
    const method = form.method

    try {
      const response = await fetch(url, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({})
      })

      if (response.ok) {
        const data = await response.json()
        this.updateCount(data.count)
      }
    } catch (error) {
      console.error('Vote error:', error)
    }
  }

  updateCount(count) {
    if (this.hasCountTarget) {
      this.countTarget.textContent = count
    }
  }
}
EOF
}
```
