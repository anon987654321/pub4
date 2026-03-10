```zsh
#!/usr/bin/env zsh
# Voting System Generator
# Universal voting and reviews for all Rails apps

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

check_rails_command() {
  if ! command -v bin/rails >/dev/null 2>&1; then
    log "Error: bin/rails command not found"
    return 1
  fi
  return 0
}

add_voting_system() {
  local app_name="${1:-${PWD##*/}}"
  log "Adding voting system to $app_name"

  install_voting_gems || return 1
  check_rails_command || return 1

  if generate_voting_models; then
    create_voting_controllers || return 1
    create_voting_helpers || return 1
    create_voting_routes || return 1
    create_voting_stimulus || return 1
  else
    log "Failed to generate voting models"
    return 1
  fi

  log "Voting system added to $app_name"
}

install_voting_gems() {
  local gemfile_content
  gemfile_content=$(<Gemfile)

  if ! grep -q "^[[:space:]]*gem[[:space:]]*['\"]acts_as_votable['\"]" Gemfile && \
     ! grep -q "^[[:space:]]*gem[[:space:]]*['\"]public_activity['\"]" Gemfile; then
    {
      echo ""
      echo "# Voting and Reviews"
      echo "gem 'acts_as_votable', '~> 1.0.0'"
      echo "gem 'public_activity', '~> 2.0.0'"
    } >> Gemfile
    if ! bundle install; then
      log "Gem installation failed"
      return 1
    fi
  else
    log "Skipping gem installation - dependencies already present"
  fi
}

generate_voting_models() {
  check_rails_command || return 1

  if ! [ -f "app/models/review.rb" ]; then
    if bin/rails generate model Review user:references \
        rating:integer title:string body:text \
        helpful_count:integer:default=0 verified_purchase:boolean:default=false; then
      log "Generated Review model"
    else
      log "Failed to generate Review model"
      return 1
    fi
  else
    log "Review model already exists, skipping creation"
  fi

  if ! find db/migrate -name "*add_votable_to_posts*" -o -name "*add_votes_to*" | grep -q .; then
    if bin/rails generate migration AddVotableToPosts votable:references{polymorphic}; then
      log "Generated votable migration"
    else
      log "Failed to generate votable migration"
      return 1
    fi
  else
    log "Votable migration already exists, skipping creation"
  fi

  if ! find db/migrate -name "*add_karma_to_users*" | grep -q .; then
    if bin/rails generate migration AddKarmaToUsers karma:integer:default=0; then
      log "Generated karma migration"
    else
      log "Failed to generate karma migration"
      return 1
    fi
  else
    log "Karma migration already exists, skipping creation"
  fi

  if bin/rails db:migrate; then
    log "Database migrations completed"
  else
    log "Database migrations failed"
    return 1
  fi
}

create_voting_controllers() {
  local controller_path="app/controllers/reviews_controller.rb"

  if [ -f "$controller_path" ]; then
    log "Reviews controller already exists, skipping creation"
    return 0
  fi

  cat > "$controller_path" << "EOF"
class ReviewsController < ApplicationController
  before_action :set_review, only: [:show, :edit, :update, :destroy, :mark_helpful]
  before_action :authenticate_user!, except: [:index, :show]

  def index
    @reviews = Review.includes(:user).order(created_at: :desc)
  end

  def show
  end

  def new
    @review = Review.new
  end

  def create
    @review = current_user.reviews.build(review_params)
    if @review.save
      redirect_to @review, notice: 'Review was successfully created.'
    else
      render :new
    end
  end

  def edit
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

  def mark_helpful
    helpful = current_user.voted_for?(@review) ? false : true

    if helpful
      current_user.vote_for(@review)
      @review.increment!(:helpful_count)
      flash[:notice] = 'Marked as helpful'
    else
      current_user.unvote_for(@review)
      @review.decrement!(:helpful_count)
      flash[:notice] = 'Removed helpful mark'
    end

    redirect_to @review
  end

  private

  def set_review
    @review = Review.find(params[:id])
  end

  def review_params
    params.require(:review).permit(:rating, :title, :body, :verified_purchase)
  end
end
EOF

  log "Created Reviews controller"
}

create_voting_helpers() {
  local helper_path="app/helpers/reviews_helper.rb"

  if [ -f "$helper_path" ]; then
    log "Reviews helper already exists, skipping creation"
    return 0
  fi

  cat > "$helper_path" << "EOF"
module ReviewsHelper
  def star_rating(rating, max = 5)
    full_stars = rating.floor
    half_star = (rating - full_stars) >= 0.5
    empty_stars = max - full_stars - (half_star ? 1 : 0)

    html = ''.span, '★', class: 'star full') }
    html += content_tag(:span, '½', class: 'star half    html
  end

  def helpful_percentage(review    total_votes = review.votes_for.size
    (review.helpful_count.to_f / total_votes * 100).round
  end

  def verified_purchase_badge(review)
    return unless review.verified_purchase?
    content_tag(:span, '✓ Verified Purchase', class: 'verified-badge')
  end
end
EOF

  log "Created Reviews helper"
}

create_voting_routes() {
  local routes_content
  routes_content=$(<config/routes.rb)

  if ! grep -q "resources :reviews" config/routes.rb; then
    sed -i '' '/Rails\.application\.routes\.draw do/a\
  resources :reviews do\
    member do\
      post :mark_helpful\
    end\
  end\
' config/routes.rb
    log "Added voting routes"
  else
    log "Voting routes already exist, skipping creation"
  fi
}

create_voting_stimulus() {
  local stimulus_path="app/javascript/controllers/reviews_controller.js"
  local controllers_dir="app/javascript/controllers"

  if [ ! -d "$controllers_dir" ]; then
    mkdir -p "$controllers_dir"
  fi

  if [ -f "$stimulus_path" ]; then
    log "Reviews Stimulus controller already exists, skipping creation"
    return 0
  fi

  cat > "$stimulus_path" << "EOF"
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["helpfulButton", "helpfulCount"]

  connect() {
    console.log("Reviews controller connected")
  }

  markHelpful(event) {
    event.preventDefault()

    const url = this.data.get("url")
    const csrfToken = document.querySelector("[name='csrf-token']").content

    fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      credentials: "same-origin"
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.helpfulCountTarget.textContent = data.helpful_count
        this.updateButtonState(data.helpful)
      }
    })
    .catch(error => console.error("Error:", error))
  }

  updateButtonState(helpful) {
    if (helpful) {
      this.helpfulButtonTarget.classList.add("active")
      this.helpfulButtonTarget.textContent = "✓ Helpful"
    } else {
      this.helpfulButtonTarget.classList.remove("active")
      this.helpfulButtonTarget.textContent = "Mark Helpful"
    }
  }
}
EOF

  log "Created Reviews Stimulus controller"
}
```
