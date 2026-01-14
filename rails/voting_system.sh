# Voting System Generator
# Universal voting and reviews for all Rails apps

# Usage: add_voting_to_app app_name

add_voting_system() {

  typeset app_name="${1:-current_app}"

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

  cat >> Gemfile << 'EOF'

# Voting and Reviews

gem 'acts_as_votable'

gem 'public_activity'

EOF

  bundle install

}

generate_voting_models() {

  bin/rails generate model Review \

    reviewable:references{polymorphic} \

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

      respond_to_vote('not voted', :unprocessable_entity)

    end

  end

  private

  def set_votable

    votable_type = params[:votable_type].classify

    votable_id = params[:votable_id]

    @votable = votable_type.constantize.find(votable_id)

  end

  def update_karma(user, amount)

    user&.increment!(:karma, amount)

  end

  def respond_to_vote(message, status = :ok)

    respond_to do |format|

      format.turbo_stream do

        render turbo_stream: turbo_stream.replace(

          "votable_#{@votable.class.name.underscore}_#{@votable.id}",

          partial: 'votes/vote_buttons',

          locals: { votable: @votable, current_user: current_user }

        )

      end

      format.json { render json: { message: message, score: @votable.cached_votes_score }, status: status }

    end

  end

end

EOF

}

write_reviews_controller() {

  cat > app/controllers/reviews_controller.rb << 'EOF'

class ReviewsController < ApplicationController

  before_action :authenticate_user!, except: [:index, :show]

  before_action :set_reviewable

  before_action :set_review, only: [:show, :edit, :update, :destroy]

  def index

    @reviews = @reviewable.reviews.order(created_at: :desc)

  end

  def create

    @review = @reviewable.reviews.build(review_params)

    @review.user = current_user

    if @review.save

      redirect_to @reviewable, notice: 'Review posted'

    else

      render :new, status: :unprocessable_entity

    end

  end

  def update

    if @review.user == current_user && @review.update(review_params)

      redirect_to @reviewable, notice: 'Review updated'

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy

    if @review.user == current_user

      @review.destroy

      redirect_to @reviewable, notice: 'Review deleted'

    else

      redirect_to @reviewable, alert: 'Unauthorized'

    end

  end

  private

  def set_reviewable

    reviewable_type = params[:reviewable_type].classify

    reviewable_id = params[:reviewable_id]

    @reviewable = reviewable_type.constantize.find(reviewable_id)

  end

  def set_review

    @review = Review.find(params[:id])

  end

  def review_params

    params.require(:review).permit(:rating, :title, :body)

  end

end

EOF

}

create_voting_helpers() {

  cat > app/helpers/voting_helper.rb << 'EOF'

module VotingHelper

  def vote_buttons(votable)

    render partial: 'votes/vote_buttons', locals: { votable: votable }

  end

  def vote_score(votable)

    content_tag :span, votable.cached_votes_score, class: 'vote-score'

  end

  def karma_badge(user)

    return unless user.karma

    content_tag :span, user.karma, class: "karma-badge #{karma_class(user.karma)}"

  end

  def rating_stars(rating, max = 5)

    full = '★' * rating

    empty = '☆' * (max - rating)

    content_tag :span, full + empty, class: 'rating-stars'

  end

  private

  def karma_class(karma)

    case karma

    when 0..99 then 'karma-novice'

    when 100..499 then 'karma-contributor'

    when 500..999 then 'karma-expert'

    else 'karma-legend'

    end

  end

end

EOF

}

add_voting_routes() {

  cat >> config/routes.rb << 'EOF'

  # Voting

  post ':votable_type/:votable_id/upvote', to: 'votes#upvote', as: :upvote

  post ':votable_type/:votable_id/downvote', to: 'votes#downvote', as: :downvote

  delete ':votable_type/:votable_id/unvote', to: 'votes#unvote', as: :unvote

  # Reviews

  resources :reviews, only: [:show, :edit, :update, :destroy]

  scope ':reviewable_type/:reviewable_id' do

    resources :reviews, only: [:index, :create]

  end

EOF

}

create_voting_stimulus() {

  cat > app/javascript/controllers/vote_controller.js << 'EOF'

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static values = { type: String, id: Number }

  static targets = ["score", "upvote", "downvote"]

  async vote(event) {

    const action = event.currentTarget.dataset.action.split('#')[1]

    const url = `/${this.typeValue}/${this.idValue}/${action}`

    const response = await fetch(url, {

      method: action === 'unvote' ? 'DELETE' : 'POST',

      headers: {

        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,

        'Accept': 'application/json'

      }

    })

    if (response.ok) {

      const data = await response.json()

      this.updateScore(data.score)

      this.updateButtons(action)

    }

  }

  updateScore(score) {

    if (this.hasScoreTarget) {

      this.scoreTarget.textContent = score

    }

  }

  updateButtons(action) {

    this.upvoteTarget.classList.toggle('active', action === 'upvote')

    this.downvoteTarget.classList.toggle('active', action === 'downvote')

  }

}

EOF

}

write_vote_buttons_partial() {

  mkdir -p app/views/votes

  cat > app/views/votes/_vote_buttons.html.erb << 'EOF'

<div class="vote-buttons"

     data-controller="vote"

     data-vote-type-value="<%= votable.class.name.underscore %>"

     data-vote-id-value="<%= votable.id %>"

     id="votable_<%= votable.class.name.underscore %>_<%= votable.id %>">

  <button data-action="click->vote#vote"

          data-target="vote.upvote"

          class="vote-btn upvote <%= 'active' if current_user&.voted_up_on?(votable) %>"

          title="Upvote">

    ▲

  </button>

  <span data-vote-target="score" class="vote-score">

    <%= votable.cached_votes_score %>

  </span>

  <button data-action="click->vote#vote"

          data-target="vote.downvote"

          class="vote-btn downvote <%= 'active' if current_user&.voted_down_on?(votable) %>"

          title="Downvote">

    ▼

  </button>

</div>

EOF

}

write_review_form_partial() {

  mkdir -p app/views/reviews

  cat > app/views/reviews/_form.html.erb << 'EOF'

<%= form_with model: review, url: reviews_path(reviewable_type: reviewable.class.name, reviewable_id: reviewable.id) do |f| %>

  <div class="field">

    <%= f.label :rating, "Rating" %>

    <div class="star-rating" data-controller="star-rating">

      <% 5.downto(1) do |i| %>

        <%= f.radio_button :rating, i, id: "rating_#{i}" %>

        <%= f.label "rating_#{i}", '★' %>

      <% end %>

    </div>

  </div>

  <div class="field">

    <%= f.label :title %>

    <%= f.text_field :title, placeholder: "Sum up your experience" %>

  </div>

  <div class="field">

    <%= f.label :body, "Your review" %>

    <%= f.text_area :body, rows: 5, placeholder: "Share your thoughts..." %>

  </div>

  <%= f.submit "Post Review", class: "btn btn-primary" %>

<% end %>

EOF

}

write_voting_css() {

  cat > app/assets/stylesheets/voting.css << 'EOF'

.vote-buttons {

  display: flex;

  flex-direction: column;

  align-items: center;

  gap: 0.25rem;

}

.vote-btn {

  width: 40px;

  height: 40px;

  border: 1px solid #e5e7eb;

  background: white;

  border-radius: 4px;

  cursor: pointer;

  font-size: 20px;

  color: #6b7280;

  transition: all 0.2s;

}

.vote-btn:hover {

  background: #f9fafb;

  border-color: #d1d5db;

}

.vote-btn.upvote.active {

  color: #f97316;

  border-color: #f97316;

  background: #fff7ed;

}

.vote-btn.downvote.active {

  color: #6366f1;

  border-color: #6366f1;

  background: #eef2ff;

}

.vote-score {

  font-weight: 600;

  font-size: 14px;

  color: #374151;

}

.karma-badge {

  display: inline-block;

  padding: 2px 8px;

  border-radius: 12px;

  font-size: 12px;

  font-weight: 600;

}

.karma-novice { background: #f3f4f6; color: #6b7280; }

.karma-contributor { background: #dbeafe; color: #1e40af; }

.karma-expert { background: #fef3c7; color: #92400e; }

.karma-legend { background: #fce7f3; color: #9f1239; }

.rating-stars {

  color: #fbbf24;

  font-size: 20px;

}

.star-rating {

  display: flex;

  flex-direction: row-reverse;

  justify-content: flex-end;

  gap: 4px;

}

.star-rating input[type="radio"] {

  display: none;

}

.star-rating label {

  font-size: 32px;

  color: #d1d5db;

  cursor: pointer;

  transition: color 0.2s;

}

.star-rating input:checked ~ label {

  color: #fbbf24;

}

.star-rating label:hover,

.star-rating label:hover ~ label {

  color: #fbbf24;

}

EOF

}

setup_votable_concern() {

  mkdir -p app/models/concerns

  cat > app/models/concerns/votable.rb << 'EOF'

module Votable

  extend ActiveSupport::Concern

  included do

    acts_as_votable

    has_many :reviews, as: :reviewable, dependent: :destroy

  end

  def average_rating

    reviews.average(:rating)&.round(1) || 0

  end

  def review_count

    reviews.count

  end

end

EOF

}

update_models_with_voting() {

  echo "# Add to models that need voting:"

  echo "# include Votable"

  echo "# acts_as_voter (for User model)"

}

export -f add_voting_system install_voting_gems generate_voting_models

export -f create_voting_controllers write_votes_controller write_reviews_controller

export -f create_voting_helpers add_voting_routes create_voting_stimulus

export -f write_vote_buttons_partial write_review_form_partial write_voting_css

export -f setup_votable_concern update_models_with_voting

