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
    bundle install || { log "Gem installation failed"; return 1; }
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

  if ! find db/migrate -name "*add_votable_to_posts*" -o -name "*add_votes_to_posts*" | grep -q .; then
    bin/rails generate migration AddVotesToPosts votable_type:string votable_id:integer voter_type:string voter_id:integer vote_flag:boolean vote_scope:string vote_weight:integer || return 1
  fi

  if ! find db/migrate -name "*add_karma_to_users*" | grep -q .; then
    bin/rails generate migration AddKarmaToUsers karma:integer:default=0 || return 1
  fi

  log "Generated voting migrations"
}

create_voting_controllers() {
  check_rails_command || return 1

  # Votes Controller
  if ! [ -f "app/controllers/votes_controller.rb" ]; then
    cat > app/controllers/votes_controller.rb << 'EOF'
class VotesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_votable

  def upvote
    @votable.upvote_by current_user
    update_karma(1)
    render json: { votes: @votable.get_upvotes.size }
  end

  def downvote
    @votable.downvote_by current_user
    update_karma(-1)
    render json: { votes: @votable.get_upvotes.size }
  end

  private

  def set_votable
    resource = params[:votable_type].classify.constantize
    @votable = resource.find(params[:votable_id])
  end

  def update_karma(change)
    if @votable.respond_to?(:user) && @votable.user != current_user
      @votable.user.update_column(:karma, @votable.user.karma + change)
    end
  end
end
EOF
    log "Created votes controller"
  fi

  # Reviews Controller
  if ! [ -f "app/controllers/reviews_controller.rb" ]; then
    cat > app/controllers/reviews_controller.rb << 'EOF'
class ReviewsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_review, only: [:show, :edit, :update, :destroy, :mark_helpful]

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

  def mark_helpful
    if @review.mark_helpful_by(current_user)
      render json: { helpful_count: @review.helpful_count }
    else
      render json: { error: 'Unable to mark as helpful' }, status: :unprocessable_entity
    end
  end

  private

  def set_review
    @review = Review.find(params[:id])
  end

  def review_params
    params.require(:review).permit(:rating, :title, :body, :reviewable_type, :reviewable_id)
  end
end
EOF
    log "Created reviews controller"
  fi
}

create_voting_helpers() {
  if ! [ -f "app/helpers/voting_helper.rb" ]; then
    cat > app/helpers/voting_helper.rb << 'EOF'
module VotingHelper
  def vote_button(resource, vote_type)
    button_to send("#{vote_type}_path",
                  votable_type: resource.class.name,
                  votable_id: resource.id),
              method: :post,
              class: "vote-btn #{vote_type}",
              remote: true do
      content_tag(:span, resource.get_upvotes.size)
    end
  end

  def star_rating(rating)
    full_stars = rating.floor
    half_star = (rating - full_stars) >= 0.5
    empty_stars = 5 - full_stars - (half_star ? 1 : 0)

    safe_join([
      full_stars.times.map { content_tag(:span, '★', class: 'star full') },
      (half_star ? content_tag(:span, '½', class: 'star half') : ''),
      empty_stars.times.map { content_tag(:span, '☆', class: 'star empty') }
    ].flatten)
  end
end
EOF
    log "Created voting helper"
  fi
}

create_voting_routes() {
  if ! grep -q "resources :reviews" config/routes.rb; then
    cat >> config/routes.rb << 'EOF'

  # Voting routes
  resources :reviews do
    member do
      post :mark_helpful
    end
  end

  resources :votes, only: [] do
    collection do
      post ':votable_type/:votable_id/upvote', action: :upvote, as: :upvote
      post ':votable_type/:votable_id/downvote', action: :downvote, as: :downvote
    end
  end
EOF
    log "Added voting routes"
  fi
}

create_voting_stimulus() {
  if ! [ -f "app/javascript/controllers/voting_controller.js" ]; then
    mkdir -p app/javascript/controllers
    cat > app/javascript/controllers/voting_controller.js << 'EOF'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count"]

  vote(event) {
    event.preventDefault()

    fetch(event.target.closest('form').action, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      this.countTarget.textContent = data.votes
    })
    .catch(error => console.error('Error:', error))
  }

  markHelpful(event) {
    event.preventDefault()

    fetch(this.data.get('url'), {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.helpful_count !== undefined) {
        event.target.textContent = `Helpful (${data.helpful_count})`
      }
    })
  }
}
EOF
    log "Created Stimulus controller"
  fi
}
```
