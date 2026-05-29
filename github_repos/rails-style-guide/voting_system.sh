#!/usr/bin/env sh
# Voting System Generator – minimal, portable, safe

set -eu
set -o pipefail
IFS=$(printf '\n\t')

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

# Ensure Rails CLI exists
[ -x bin/rails ] || { log "Error: bin/rails not found"; exit 1; }

add_voting_system() {
  app=${1:-${PWD##*/}}
  log "Adding voting system to $app"
  install_gems || return

  # Routes
  if [ -f config/routes.rb ] && ! grep -qF "resources :reviews" config/routes.rb; then
    add_routes
  fi

  generate_models || return
  create_controller   || return
  create_helper      || return
  create_stimulus    || return

  log "Voting system added to $app"
}

install_gems() {
  if grep -qE "acts_as_votable|public_activity" Gemfile; then
    log "Gems already present"
    return 0
  fi

  {
    printf "\n%s\n" "gem 'acts_as_votable', '~> 1.0.0'"
    printf "%s\n"   "gem 'public_activity', '~> 2.0.0'"
  } >> Gemfile

  if ! bundle install --quiet; then
    log "Gem install failed"
    exit 1
  fi
}

generate_models() {
  # Review model
  if [ ! -f app/models/review.rb ]; then
    bin/rails generate model Review \
      user:references \
      rating:integer \
      title:string \
      body:text \
      helpful_count:integer:default=0 \
      verified_purchase:boolean:default=false ||
      { log "Model generation failed"; exit 1; }
  fi

  # Polymorphic votable migration
  if ! ls db/migrate/*add_votable_to_posts*.rb >/dev/null 2>&1; then
    bin/rails generate migration AddVotableToPosts votable:references{polymorphic} ||
      { log "Votable migration failed"; exit 1; }
  fi

  # Karma migration
  if ! ls db/migrate/*add_karma_to_users*.rb >/dev/null 2>&1; then
    bin/rails generate migration AddKarmaToUsers karma:integer:default=0 ||
      { log "Karma migration failed"; exit 1; }
  fi

  bin/rails db:migrate || { log "Migrations failed"; exit 1; }
}

add_routes() {
  tmp=$(mktemp -p .) || { log "Failed to create temporary file"; exit 1; }
  awk '
    /Rails\.application\.routes\.draw do/ {print; next}
    /end/ && !found {
      print "  resources :reviews do"
      print "    member do"
      print "      post :mark_helpful"
      print "    end"
      print "  end"
      found=1
    }
    {print}
  ' config/routes.rb > "$tmp" && mv "$tmp" config/routes.rb
}

create_controller() {
  file=app/controllers/reviews_controller.rb
  if [ -f "$file" ]; then
    log "Controller exists"
    return 0
  fi

  cat >"$file" <<'EOF'
class ReviewsController < ApplicationController
  before_action :set_review, only: %i[show edit update destroy mark_helpful]
  before_action :authenticate_user!, except: %i[index show]

  def index
    @reviews = Review.includes(:user).order(created_at: :desc)
  end

  def show; end

  def new
    @review = Review.new
  end

  def create
    @review = current_user.reviews.build(review_params)
    if @review.save
      redirect_to @review, notice: "Review created"
    else
      render :new
    end
  end

  def edit; end

  def update
    if @review.update(review_params)
      redirect_to @review, notice: "Review updated"
    else
      render :edit
    end
  end

  def destroy
    @review.destroy
    redirect_to reviews_path, notice: "Review destroyed"
  end

  def mark_helpful
    if @review.voted_for_by?(current_user)
      current_user.unvote_for(@review)
      @review.decrement!(:helpful_count)
    else
      current_user.vote_for(@review)
      @review.increment!(:helpful_count)
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

  log "Created controller"
}

create_helper() {
  file=app/helpers/reviews_helper.rb
  if [ -f "$file" ]; then
    log "Helper exists"
    return 0
  fi

  cat >"$file" <<'EOF'
module ReviewsHelper
  def star_rating(rating, max = 5)
    full = rating.floor
    half = (rating - full) >= 0.5
    empty = max - full - (half ? 1 : 0)

    stars = content_tag(:span, '★' * full, class: 'star full')
    stars << content_tag(:span, '½', class: 'star half') if half
    stars << content_tag(:span, '★' * empty, class: 'star empty')
    stars
  end

  def helpful_pct(review)
    total = review.votes_for.size
    return 0 if total.zero?

    ((review.helpful_count.to_f / total) * 100).round
  end

  def verified_badge(review)
    return unless review.verified_purchase?

    content_tag(:span, '✓ Verified Purchase', class: 'verified-badge')
  end
end
EOF

  log "Created helper"
}

create_stimulus() {
  path=app/javascript/controllers/reviews_controller.js
  mkdir -p "$(dirname "$path")"
  if [ -f "$path" ]; then
    log "Stimulus exists"
    return 0
  fi

  cat >"$path" <<'EOF'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["helpfulButton", "helpfulCount"]

  async markHelpful(event) {
    event.preventDefault()
    const url = this.data.get("url")
    const token = document.querySelector("[name='csrf-token']").content

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" },
        credentials: "same-origin"
      })
      const data = await response.json()
      if (data.success) {
        this.helpfulCountTarget.textContent = data.helpful_count
        this.updateButton(data.helpful)
      }
    } catch (_) {
      console.error("Error marking helpful")
    }
  }

  updateButton(helpful) {
    this.helpfulButtonTarget.textContent = helpful ? "✓ Helpful" : "Mark Helpful"
    this.helpfulButtonTarget.classList.toggle("active", helpful)
  }
}
EOF

  log "Created stimulus"
}

add_voting_system "$@"
