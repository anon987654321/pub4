#!/usr/bin/env zsh
set -euo pipefail

# MyToonz: AI-Powered Personalized Comic Strip Generator
# Generates authentic comic strips from user's daily stories using Replicate AI

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="mytoonz"

source "${BASE_DIR}/__shared/@common.sh"
main() {

    log "Starting MyToonz setup..."
    setup_full_app "$APP_NAME"
    setup_mytoonz_specific

    setup_frontend
    log "✓ MyToonz setup complete!"

    log "→ Start server: cd mytoonz && bin/rails server -p 10008"
    log "→ Visit: http://localhost:10008"
}

setup_mytoonz_specific() {
    log "Setting up MyToonz-specific features..."
    cd "$BASE_DIR/$APP_NAME"
    # Install required gems

    install_gem "httparty"
    install_gem "redis"

    install_gem "sidekiq"

    # Setup Active Storage for photo uploads
    setup_storage
    # Create Replicate service
    create_replicate_service

    # Create models
    create_models

    # Create controllers
    create_controllers

    # Create background jobs
    create_jobs

    # Setup routes
    setup_routes

    # Create initializers
    create_initializers

    log "✓ MyToonz-specific setup complete"
}

create_replicate_service() {
    log "Creating Replicate AI integration service..."

    mkdir -p app/services
    cat > app/services/replicate_service.rb << 'RUBY'

require 'httparty'
class ReplicateService

  include HTTParty
  base_uri 'https://api.replicate.com/v1'
  def initialize

    @api_token = ENV['REPLICATE_API_TOKEN']
    raise "REPLICATE_API_TOKEN not set" unless @api_token
  end

  def generate_comic_strip(prompt:, style: "comic", user_photo_url: nil)
    model = select_model(style)
    input = build_input(prompt, style, user_photo_url)
    response = self.class.post(

      '/predictions',
      headers: headers,
      body: {

        version: model[:version],
        input: input
      }.to_json
    )
    handle_response(response)
  end
  def get_prediction(prediction_id)
    response = self.class.get(

      "/predictions/#{prediction_id}",
      headers: headers

    )
    handle_response(response)
  end
  private
  def headers

    {
      'Authorization' => "Token #{@api_token}",

      'Content-Type' => 'application/json'

    }
  end
  def select_model(style)
    models = {
      comic: {
        name: 'stable-diffusion',

        version: 'db21e45d3f7023abc2a46ee38a23973f6dce16bb082a930b0c49861f96d1e5bf'
      },
      anime: {
        name: 'anything-v4',
        version: '42a996d39a96aedc57b2e0aa8105dea39c9c89d5f3c654c9ea1f10c80b3c3d07'
      },
      cartoon: {
        name: 'dreamshaper',
        version: '5f1c286b04e3c9b8c8e4b03b66e06a19e9cc7bbcf06e4e9e0a72f7d7b8c4a5b1'
      }
    }
    models[style.to_sym] || models[:comic]
  end
  def build_input(prompt, style, user_photo_url)
    base_prompt = enhance_prompt(prompt, style)

    input = {
      prompt: base_prompt,

      negative_prompt: "blurry, bad quality, distorted, ugly",
      width: 1024,

      height: 576,
      num_outputs: 4,
      guidance_scale: 7.5,
      num_inference_steps: 50
    }
    input[:image] = user_photo_url if user_photo_url
    input
  end
  def enhance_prompt(user_prompt, style)

    style_modifiers = {
      comic: "comic book style, vibrant colors, bold lines, comic panel",
      anime: "anime art style, manga, Japanese animation",

      cartoon: "cartoon style, animated, colorful, fun"
    }
    modifier = style_modifiers[style.to_sym] || style_modifiers[:comic]
    "#{modifier}, #{user_prompt}, high quality, detailed, professional artwork"
  end
  def handle_response(response)

    if response.success?
      response.parsed_response
    else

      Rails.logger.error "Replicate API error: #{response.code} - #{response.body}"
      { error: "API request failed: #{response.message}" }
    end
  end
end
RUBY
}
create_models() {
    log "Creating database models..."
    # Generate User model if it doesn't exist
    if [ ! -f "app/models/user.rb" ]; then

        bin/rails generate model User email:string username:string photo_url:string
    fi

    # Generate Story model
    if [ ! -f "app/models/story.rb" ]; then
        bin/rails generate model Story user:references content:text mood:string date:date
    fi

    # Generate ComicStrip model
    if [ ! -f "app/models/comic_strip.rb" ]; then
        bin/rails generate model ComicStrip story:references style:string status:string prediction_id:string image_urls:json
    fi

    # Generate StylePreference model
    if [ ! -f "app/models/style_preference.rb" ]; then
        bin/rails generate model StylePreference user:references style_type:string example_image_url:string is_default:boolean
    fi

    # Add associations to models
    cat > app/models/user.rb << 'RUBY'
class User < ApplicationRecord
  has_many :stories, dependent: :destroy

  has_many :comic_strips, through: :stories
  has_many :style_preferences, dependent: :destroy
  has_one_attached :photo
  validates :email, presence: true, uniqueness: true
  validates :username, presence: true
  def default_style
    style_preferences.find_by(is_default: true)&.style_type || 'comic'

  end
end

RUBY
    cat > app/models/story.rb << 'RUBY'
class Story < ApplicationRecord
  belongs_to :user
  has_many :comic_strips, dependent: :destroy

  validates :content, presence: true
  validates :date, presence: true
  enum mood: {
    happy: 'happy',

    sad: 'sad',
    excited: 'excited',

    stressed: 'stressed',
    relaxed: 'relaxed',
    neutral: 'neutral'
  }
end
RUBY
    cat > app/models/comic_strip.rb << 'RUBY'
class ComicStrip < ApplicationRecord
  belongs_to :story
  validates :style, presence: true

  validates :prediction_id, presence: true
  enum status: {
    pending: 'pending',

    processing: 'processing',
    completed: 'completed',

    failed: 'failed'
  }
  def refresh_status!
    return if completed? || failed?
    service = ReplicateService.new
    result = service.get_prediction(prediction_id)

    case result['status']
    when 'succeeded'

      update!(
        status: :completed,

        image_urls: result['output']
      )
    when 'failed'
      update!(status: :failed)
    when 'processing', 'starting'
      update!(status: :processing)
    end
  end
end
RUBY
    cat > app/models/style_preference.rb << 'RUBY'
class StylePreference < ApplicationRecord
  belongs_to :user
  has_one_attached :example_image

  validates :style_type, presence: true
  before_save :ensure_single_default
  private
  def ensure_single_default

    if is_default && is_default_changed?

      StylePreference.where(user: user, is_default: true)

                    .where.not(id: id)

                    .update_all(is_default: false)
    end
  end
end
RUBY
    migrate_db
}
create_controllers() {
    log "Creating controllers..."

    mkdir -p app/controllers
    # API base controller

    cat > app/controllers/api_controller.rb << 'RUBY'
class ApiController < ApplicationController

  skip_before_action :verify_authenticity_token

  before_action :set_current_user
  private
  def set_current_user
    # Simple session-based authentication
    session[:user_id] ||= create_guest_user.id

    @current_user = User.find_by(id: session[:user_id])

  end
  def create_guest_user
    User.create!(
      email: "guest_#{SecureRandom.hex(8)}@mytoonz.local",
      username: "Guest#{rand(10000)}"

    )
  end
  def render_json(data, status: :ok)
    render json: data, status: status
  end
  def render_error(message, status: :unprocessable_entity)

    render json: { error: message }, status: status
  end
end

RUBY
    # Stories controller
    cat > app/controllers/stories_controller.rb << 'RUBY'
class StoriesController < ApiController
  def create

    story = @current_user.stories.build(story_params)
    if story.save
      GenerateComicStripJob.perform_later(story.id)
      render_json({
        story: story.as_json(include: :comic_strips),

        message: "Story created! Generating your comic strip..."
      })
    else
      render_error(story.errors.full_messages.join(', '))
    end
  end
  def index
    stories = @current_user.stories.includes(:comic_strips).order(date: :desc)
    render_json(stories.as_json(include: :comic_strips))
  end

  def show
    story = @current_user.stories.find(params[:id])
    render_json(story.as_json(include: :comic_strips))
  end

  private
  def story_params
    params.require(:story).permit(:content, :mood, :date)
  end

end

RUBY
    # Comic strips controller
    cat > app/controllers/comic_strips_controller.rb << 'RUBY'
class ComicStripsController < ApiController
  def show

    comic_strip = ComicStrip.find(params[:id])
    comic_strip.refresh_status!
    render_json(comic_strip)
  end
  def refresh
    comic_strip = ComicStrip.find(params[:id])

    comic_strip.refresh_status!
    render_json({

      comic_strip: comic_strip,
      message: "Status updated"
    })

  end
end
RUBY
    # Users controller
    cat > app/controllers/users_controller.rb << 'RUBY'
class UsersController < ApiController
  def update

    if @current_user.update(user_params)
      render_json(@current_user)
    else
      render_error(@current_user.errors.full_messages.join(', '))
    end
  end
  def upload_photo
    if params[:photo].present?
      @current_user.photo.attach(params[:photo])
      render_json({

        photo_url: url_for(@current_user.photo),
        message: "Photo uploaded successfully"
      })
    else
      render_error("No photo provided")
    end
  end
  private
  def user_params
    params.require(:user).permit(:username, :email)
  end

end

RUBY
    # Home controller for frontend
    cat > app/controllers/home_controller.rb << 'RUBY'
class HomeController < ApplicationController
  def index

    # Serves the frontend
  end
end
RUBY
}
create_jobs() {
    log "Creating background jobs..."
    mkdir -p app/jobs
    cat > app/jobs/generate_comic_strip_job.rb << 'RUBY'

class GenerateComicStripJob < ApplicationJob
  queue_as :default

  def perform(story_id)

    story = Story.find(story_id)
    user = story.user
    # Get user photo URL if available

    photo_url = user.photo.attached? ? Rails.application.routes.url_helpers.url_for(user.photo) : nil
    # Generate comic strip using Replicate
    service = ReplicateService.new

    result = service.generate_comic_strip(
      prompt: build_prompt(story),

      style: user.default_style,
      user_photo_url: photo_url
    )
    if result['id']
      story.comic_strips.create!(
        style: user.default_style,
        status: :processing,

        prediction_id: result['id']
      )
      # Schedule status check
      CheckComicStripStatusJob.set(wait: 10.seconds).perform_later(story.id)
    else
      Rails.logger.error "Failed to create comic strip: #{result['error']}"

    end
  rescue => e
    Rails.logger.error "GenerateComicStripJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
  private
  def build_prompt(story)
    mood_descriptor = story.mood ? "feeling #{story.mood}" : ""
    "A person #{mood_descriptor}, #{story.content}"

  end

end
RUBY
    cat > app/jobs/check_comic_strip_status_job.rb << 'RUBY'
class CheckComicStripStatusJob < ApplicationJob
  queue_as :default
  def perform(story_id)

    story = Story.find(story_id)
    comic_strip = story.comic_strips.where(status: [:pending, :processing]).last
    return unless comic_strip

    comic_strip.refresh_status!
    # Reschedule if still processing
    if comic_strip.processing?

      CheckComicStripStatusJob.set(wait: 10.seconds).perform_later(story_id)

    end

  rescue => e
    Rails.logger.error "CheckComicStripStatusJob failed: #{e.message}"
  end
end
RUBY
}
setup_routes() {
    log "Setting up routes..."
    cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do

  root 'home#index'
  resources :stories, only: [:create, :index, :show]

  resources :comic_strips, only: [:show] do
    member do
      post :refresh

    end
  end
  resource :user, only: [:update] do
    post :upload_photo
  end
  get "up" => "rails/health#show", as: :rails_health_check

end
RUBY
}

create_initializers() {
    log "Creating initializers..."
    mkdir -p config/initializers
    cat > config/initializers/cors.rb << 'RUBY'

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do

    origins '*'

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
RUBY
    cat > config/initializers/sidekiq.rb << 'RUBY'
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end
RUBY

    # Create .env.example
    cat > .env.example << 'ENV'
REPLICATE_API_TOKEN=your_replicate_api_token_here
REDIS_URL=redis://localhost:6379/0

DATABASE_URL=postgresql://localhost/mytoonz_development
ENV
}
setup_frontend() {
    log "Setting up frontend..."
    cd "$BASE_DIR/$APP_NAME"
    mkdir -p app/views/home

    mkdir -p app/assets/stylesheets
    mkdir -p app/javascript

    create_frontend_view
    create_frontend_styles
    create_frontend_javascript
}

create_frontend_view() {
    log "Creating frontend HTML..."
    cat > app/views/layouts/application.html.erb << 'HTML'
<!DOCTYPE html>

<html lang="en">
<head>

  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MyToonz - AI Comic Strip Generator</title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_include_tag "application", "data-turbo-track": "reload", defer: true %>
</head>
<body>
  <%= yield %>
</body>
</html>
HTML
    cat > app/views/home/index.html.erb << 'HTML'
<div class="app-container">
  <header class="header">
    <h1 class="logo">MyToonz</h1>

    <p class="tagline">Turn your day into a comic strip</p>
  </header>
  <main class="main-content">
    <div class="input-section">
      <div class="photo-upload" id="photoUpload">
        <div class="upload-placeholder" id="uploadPlaceholder">

          <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"></path>
            <circle cx="12" cy="13" r="4"></circle>
          </svg>
          <p>Upload your photo</p>
          <input type="file" id="photoInput" accept="image/*" hidden>
        </div>
      </div>
      <div class="search-container">
        <textarea
          id="storyInput"
          class="story-input"

          placeholder="How was your day?"
          rows="1"
        ></textarea>
        <button id="generateBtn" class="generate-btn">
          <span>Generate Comic</span>
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"></path>
          </svg>
        </button>
      </div>
      <div class="mood-selector">
        <button class="mood-btn" data-mood="happy">😊 Happy</button>
        <button class="mood-btn" data-mood="sad">😢 Sad</button>
        <button class="mood-btn" data-mood="excited">🎉 Excited</button>

        <button class="mood-btn" data-mood="stressed">😰 Stressed</button>
        <button class="mood-btn" data-mood="relaxed">😌 Relaxed</button>
      </div>
    </div>
    <div id="loadingState" class="loading-state" style="display: none;">
      <div class="spinner"></div>
      <p>Generating your comic strip...</p>
    </div>

    <div id="resultsSection" class="results-section" style="display: none;">
      <h2>Your Comic Strips</h2>
      <div id="comicGrid" class="comic-grid"></div>
    </div>

    <div id="gallerySection" class="gallery-section">
      <h2>Your Stories</h2>
      <div id="storiesGrid" class="stories-grid"></div>
    </div>

  </main>
</div>
HTML
}
create_frontend_styles() {
    log "Creating CSS..."
    cat > app/assets/stylesheets/application.css << 'CSS'
* {

  margin: 0;
  padding: 0;

  box-sizing: border-box;
}
:root {
  --terra-cotta: #DA7756;
  --terra-dark: #C15F3C;
  --terra-light: #E89B7E;

  --text-primary: #3D3929;
  --text-secondary: #6B645A;
  --background: #FFFCF7;
  --surface: #F5F2ED;
}
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
  background: var(--background);
  color: var(--text-primary);

  line-height: 1.6;
}
.app-container {
  min-height: 100vh;
  max-width: 900px;
  margin: 0 auto;

  padding: 2rem 1rem;
}
.header {
  text-align: center;
  margin-bottom: 3rem;
}

.logo {
  font-size: 3rem;
  font-weight: 700;
  color: var(--terra-cotta);

  margin-bottom: 0.5rem;
}
.tagline {
  color: var(--text-secondary);
  font-size: 1.1rem;
}

.input-section {
  background: white;
  border-radius: 24px;
  padding: 2rem;

  box-shadow: 0 4px 24px rgba(0,0,0,0.06);
  margin-bottom: 2rem;
}
.photo-upload {
  margin-bottom: 1.5rem;
}
.upload-placeholder {

  border: 2px dashed var(--terra-light);
  border-radius: 16px;
  padding: 2rem;

  text-align: center;
  cursor: pointer;
  transition: all 0.3s ease;
}
.upload-placeholder:hover {
  border-color: var(--terra-cotta);
  background: var(--surface);
}

.upload-placeholder svg {
  color: var(--terra-cotta);
  margin-bottom: 0.5rem;
}

.search-container {
  display: flex;
  gap: 1rem;
  margin-bottom: 1.5rem;

}
.story-input {
  flex: 1;
  border: 2px solid var(--surface);
  border-radius: 16px;

  padding: 1rem 1.5rem;
  font-size: 1.1rem;
  font-family: inherit;
  resize: none;
  transition: all 0.3s ease;
  min-height: 60px;
}
.story-input:focus {
  outline: none;
  border-color: var(--terra-cotta);
  box-shadow: 0 0 0 4px rgba(218, 119, 86, 0.1);

}
.generate-btn {
  background: var(--terra-cotta);
  color: white;
  border: none;

  border-radius: 16px;
  padding: 1rem 2rem;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  transition: all 0.3s ease;
}
.generate-btn:hover {
  background: var(--terra-dark);
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(218, 119, 86, 0.3);

}
.mood-selector {
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;

}
.mood-btn {
  background: var(--surface);
  border: 2px solid transparent;
  border-radius: 12px;

  padding: 0.5rem 1rem;
  font-size: 0.95rem;
  cursor: pointer;
  transition: all 0.2s ease;
}
.mood-btn:hover,
.mood-btn.active {
  background: white;
  border-color: var(--terra-cotta);

  color: var(--terra-cotta);
}
.loading-state {
  text-align: center;
  padding: 3rem;
}

.spinner {
  width: 48px;
  height: 48px;
  border: 4px solid var(--surface);

  border-top-color: var(--terra-cotta);
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin: 0 auto 1rem;
}
@keyframes spin {
  to { transform: rotate(360deg); }
}
.results-section,

.gallery-section {
  margin-top: 3rem;
}

.results-section h2,
.gallery-section h2 {
  font-size: 1.8rem;
  margin-bottom: 1.5rem;

  color: var(--text-primary);
}
.comic-grid,
.stories-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));

  gap: 1.5rem;
}
.comic-item {
  background: white;
  border-radius: 16px;
  overflow: hidden;

  box-shadow: 0 4px 12px rgba(0,0,0,0.08);
  transition: transform 0.3s ease;
}
.comic-item:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 24px rgba(0,0,0,0.12);
}

.comic-item img {
  width: 100%;
  height: auto;
  display: block;

}
.story-card {
  background: white;
  border-radius: 16px;
  padding: 1.5rem;

  box-shadow: 0 4px 12px rgba(0,0,0,0.08);
}
.story-meta {
  display: flex;
  justify-content: space-between;
  align-items: center;

  margin-bottom: 1rem;
  color: var(--text-secondary);
  font-size: 0.9rem;
}
.story-content {
  color: var(--text-primary);
  margin-bottom: 1rem;
}

.story-status {
  display: inline-block;
  padding: 0.25rem 0.75rem;
  border-radius: 8px;

  font-size: 0.85rem;
  font-weight: 500;
}
.status-completed {
  background: #4A7C59;
  color: white;
}

.status-processing {
  background: #D97706;
  color: white;
}

.status-pending {
  background: var(--surface);
  color: var(--text-secondary);
}

@media (max-width: 640px) {
  .search-container {
    flex-direction: column;
  }

  .logo {
    font-size: 2rem;
  }
  .mood-selector {

    justify-content: center;
  }
}

CSS
}
create_frontend_javascript() {
    log "Creating JavaScript..."
    mkdir -p app/javascript
    cat > app/javascript/application.js << 'JS'

let selectedMood = null;
let currentUser = null;

document.addEventListener('DOMContentLoaded', () => {
  initializeApp();
  loadStories();
});

function initializeApp() {
  const photoUpload = document.getElementById('uploadPlaceholder');
  const photoInput = document.getElementById('photoInput');
  const generateBtn = document.getElementById('generateBtn');

  const storyInput = document.getElementById('storyInput');
  const moodBtns = document.querySelectorAll('.mood-btn');
  photoUpload.addEventListener('click', () => photoInput.click());
  photoInput.addEventListener('change', handlePhotoUpload);
  generateBtn.addEventListener('click', generateComicStrip);
  storyInput.addEventListener('input', autoResize);

  storyInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();

      generateComicStrip();
    }
  });
  moodBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      moodBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      selectedMood = btn.dataset.mood;
    });
  });
}
function autoResize(e) {
  e.target.style.height = 'auto';
  e.target.style.height = Math.min(e.target.scrollHeight, 200) + 'px';
}

async function handlePhotoUpload(e) {
  const file = e.target.files[0];
  if (!file) return;
  const formData = new FormData();

  formData.append('photo', file);
  try {
    const response = await fetch('/user/upload_photo', {

      method: 'POST',
      body: formData

    });
    const data = await response.json();
    if (response.ok) {
      const placeholder = document.getElementById('uploadPlaceholder');
      placeholder.innerHTML = `

        <img src="${data.photo_url}" alt="User photo" style="max-width: 200px; border-radius: 12px;">

        <p style="margin-top: 0.5rem;">Photo uploaded! ✓</p>
      `;
      showNotification('Photo uploaded successfully!', 'success');
    }
  } catch (error) {
    showNotification('Failed to upload photo', 'error');
    console.error('Upload error:', error);
  }
}
async function generateComicStrip() {
  const storyInput = document.getElementById('storyInput');
  const content = storyInput.value.trim();
  if (!content) {

    showNotification('Please tell us about your day!', 'warning');
    return;
  }

  const loadingState = document.getElementById('loadingState');
  const resultsSection = document.getElementById('resultsSection');
  loadingState.style.display = 'block';
  resultsSection.style.display = 'none';

  try {
    const response = await fetch('/stories', {

      method: 'POST',
      headers: {

        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        story: {
          content: content,
          mood: selectedMood || 'neutral',
          date: new Date().toISOString().split('T')[0]
        }
      })
    });
    const data = await response.json();
    if (response.ok) {
      showNotification(data.message, 'success');
      storyInput.value = '';

      storyInput.style.height = 'auto';

      pollComicStripStatus(data.story.id);
      loadStories();
    } else {
      throw new Error(data.error || 'Failed to create story');

    }
  } catch (error) {
    loadingState.style.display = 'none';
    showNotification(error.message, 'error');
    console.error('Generation error:', error);
  }
}
async function pollComicStripStatus(storyId) {
  const maxAttempts = 60;
  let attempts = 0;
  const checkStatus = async () => {

    try {
      const response = await fetch(`/stories/${storyId}`);
      const data = await response.json();

      if (data.comic_strips && data.comic_strips.length > 0) {
        const latestComic = data.comic_strips[data.comic_strips.length - 1];
        if (latestComic.status === 'completed') {
          displayComicStrip(latestComic);

          document.getElementById('loadingState').style.display = 'none';
          return;

        } else if (latestComic.status === 'failed') {
          showNotification('Comic generation failed. Please try again.', 'error');
          document.getElementById('loadingState').style.display = 'none';
          return;
        }
      }
      attempts++;
      if (attempts < maxAttempts) {
        setTimeout(checkStatus, 3000);
      } else {

        showNotification('Generation is taking longer than expected. Check back soon!', 'warning');
        document.getElementById('loadingState').style.display = 'none';
      }
    } catch (error) {
      console.error('Status check error:', error);
    }
  };
  checkStatus();
}
function displayComicStrip(comicStrip) {
  const resultsSection = document.getElementById('resultsSection');

  const comicGrid = document.getElementById('comicGrid');
  resultsSection.style.display = 'block';

  const imageUrls = Array.isArray(comicStrip.image_urls) ? comicStrip.image_urls : [];
  comicGrid.innerHTML = imageUrls.map(url => `
    <div class="comic-item">

      <img src="${url}" alt="Generated comic strip" loading="lazy">

    </div>

  `).join('');
  resultsSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
async function loadStories() {
  try {

    const response = await fetch('/stories');
    const stories = await response.json();

    const storiesGrid = document.getElementById('storiesGrid');
    if (stories.length === 0) {
      storiesGrid.innerHTML = '<p style="text-align: center; color: var(--text-secondary);">No stories yet. Share your day to get started!</p>';
      return;

    }

    storiesGrid.innerHTML = stories.map(story => {
      const date = new Date(story.date).toLocaleDateString();
      const hasComics = story.comic_strips && story.comic_strips.length > 0;
      const status = hasComics ? story.comic_strips[0].status : 'pending';

      return `
        <div class="story-card">
          <div class="story-meta">
            <span>${date}</span>

            <span class="story-status status-${status}">${status}</span>
          </div>
          <div class="story-content">${escapeHtml(story.content)}</div>
          ${story.mood ? `<div style="margin-top: 0.5rem; color: var(--text-secondary);">Mood: ${story.mood}</div>` : ''}
        </div>
      `;
    }).join('');
  } catch (error) {
    console.error('Failed to load stories:', error);
  }
}
function showNotification(message, type = 'info') {
  const notification = document.createElement('div');
  notification.className = `notification notification-${type}`;
  notification.textContent = message;

  notification.style.cssText = `
    position: fixed;
    top: 2rem;
    right: 2rem;
    background: ${type === 'success' ? '#4A7C59' : type === 'error' ? '#DC2626' : '#D97706'};
    color: white;
    padding: 1rem 1.5rem;
    border-radius: 12px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.2);
    z-index: 1000;
    animation: slideIn 0.3s ease;
  `;
  document.body.appendChild(notification);
  setTimeout(() => {
    notification.style.animation = 'slideOut 0.3s ease';
    setTimeout(() => notification.remove(), 300);

  }, 3000);

}
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;

}
JS
}
main "$@"
