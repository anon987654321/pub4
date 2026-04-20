#!/usr/bin/env zsh
# Voting System Generator

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global
set -euo pipefail

log(){ echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

[[ -x bin/rails ]] || { log "Error: bin/rails not found"; exit 1; }

add_voting_system(){   local app=${1:-${PWD##*/}} log "Adding voting system to $app"
  install_gems || return
  [[ -f config/routes.rb ]] && grep -q "resources :reviews" config/routes.rb || add_routes
  generate_models || return  create_controller || return
  create_helper || return
  create_stimulus || return  log "Voting system added to $app"
}

install_gems(){ 
  grep -q "acts_as_votable\|public_activity" Gemfile || {
    cat >> Gemfile <<'GEM'
gem 'acts_as_votable', '~> 1.0.0'
gem 'public_activity', '~> 2.0.0'
GEM
    bundle install --quiet || { log "Gem install failed"; exit 1; }
  } || log "Gems present"
}

generate_models(){ 
  [[ -f app/models/review.rb ]] || bin/rails generate model Review user:references rating:integer title:string body:text helpful_count:integer:default=0 verified_purchase:boolean:default=false || { log "Model generate failed"; exit 1; }
  [[ -f db/migrate/*add_votable_to_posts*.rb ]] || bin/rails generate migration AddVotableToPosts votable:references{polymorphic} || { log "Migration failed"; exit 1; }
  [[ -f db/migrate/*add_karma_to_users*.rb ]] || bin/rails generate migration AddKarmaToUsers karma:integer:default=0 || { log "Karma migration failed"; exit 1; }
  bin/rails db:migrate || { log "Migrations failed"; exit 1; }
}

add_routes(){ 
  sed -i '' '/Rails.application.routes.draw do/a\
  resources :reviews do\
    member do\
      post :mark_helpful\
    end\
  end' config/routes.rb
}

create_controller(){ 
  local file=app/controllers/reviews_controller.rb  [[ -f $file ]] && { log "Controller exists"; return 0; }
  cat >$file <<'EOF'
class ReviewsController < ApplicationController
  before_action :set_review, only: [:show,:edit,:update,:destroy,:mark_helpful]
  before_action :authenticate_user!, except: [:index,:show]

  def index
    @reviews = Review.includes(:user).order(created_at: :desc)
  end
  def show; end
  def new
    @review = Review.new
  end
  def create
    @review = current_user.reviews.build(review_params)
    @review.save ? redirect_to(@review, notice: "Review created") : render :new
  end
  def edit; end
  def update
    @review.update(review_params) ? redirect_to(@review, notice: "Review updated") : render :edit
  end
  def destroy
    @review.destroy
    redirect_to reviews_path, notice: "Review destroyed"
  end
  def mark_helpful
    if @review.voted_for_by?(current_user)
      current_user.unvote_for(@review); @review.decrement!(:helpful_count)
    else
      current_user.vote_for(@review); @review.increment!(:helpful_count)
    end
    redirect_to @review
  end
  private
  def set_review; @review = Review.find(params[:id]); end
  def review_params; params.require(:review).permit(:rating,:title,:body,:verified_purchase); end
end
EOF
  log "Created controller"
}

create_helper(){ 
  local file=app/helpers/reviews_helper.rb
  [[ -f $file ]] && { log "Helper exists"; return 0; }
  cat >$file <<'EOF'
module ReviewsHelper
  def star_rating(rating,max=5)
    stars = ''.span(class:'star full',limit:rating.floor){'★'}
    stars += content_tag(:span,'½',class:'star half') if (rating - rating.floor) >= 0.5
    stars + ''.span(class:'star empty',limit:max - rating.floor - (rating - rating.floor >= 0.5 ? 1 : 0)){'★'}
  end
  def helpful_pct(review)
    (review.helpful_count.to_f / review.votes_for.size * 100).round
  end
  def verified_badge(review)
    return unless review.verified_purchase?
    content_tag(:span,'✓ Verified Purchase',class:'verified-badge')
  end
end
EOF
  log "Created helper"
}

create_stimulus(){ 
  local path=app/javascript/controllers/reviews_controller.js
  mkdir -p app/javascript/controllers
  [[ -f $path ]] && { log "Stimulus exists"; return 0; }
  cat >$path <<'EOF'
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets: ["helpfulButton","helpfulCount"]
  markHelpful(e){
    e.preventDefault()
    const url = this.data.get("url")
    const token = document.querySelector("[name='csrf-token']").content
    fetch(url,{method:"POST",headers:{ "X-CSRF-Token": token },credentials:"same-origin"}
      .then(r=>r.json())
      .then(d=>{ if(d.success){ this.helpfulCountTarget.textContent = d.helpful_count; this.updateButton(d.helpful) } })
      .catch(()=>console.error("Error"))
  }
  updateButton(helpful){
    this.helpfulButtonTarget.textContent = helpful ? "✓ Helpful" : "Mark Helpful"
    this.helpfulButtonTarget.classList.toggle("active",helpful)
  }
}
EOF
  log "Created stimulus"
}