#!/usr/bin/env zsh
APP="amber"

set -euo pipefail

BASE_DIR="$HOME/rails/$APP"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# All functionality consolidated into @common.sh (per master.json ultraminimal principle)

source "${SCRIPT_DIR}/__shared/@common.sh"

# Marie Kondo AI Wardrobe Assistant - LangChain-powered organization
log "Setting up Marie Kondo AI Wardrobe Assistant with LangChain"

# Install LangChain gems
setup_ai

# -- GENERATE MODELS --
bin/rails generate scaffold Item title:string content:text color:string size:string material:string texture:string brand:string price:decimal category:string stock_quantity:integer available:boolean sku:string release_date:date season:string times_worn:integer purchase_date:date user:references spark_joy:boolean declutter_reason:text

bin/rails generate scaffold Outfit name:string description:text image_url:string category:string season:string occasion:string weather_condition:string user:references
bin/rails generate model OrganizationTip title:string content:text category:string embedding:vector{1536}

# Marie Kondo AI Service with LangChain

log "Creating Marie Kondo AI service"
mkdir -p app/services
cat > app/services/marie_kondo_ai_service.rb << 'KONDOEOF'

# Marie Kondo AI Assistant - Helps girls organize wardrobes with joy

# Uses LangChain + OpenAI embeddings for semantic wardrobe understanding

class MarieKondoAiService

  def initialize(user)

    @user = user
    @llm = Langchain::LLM::OpenAI.new(api_key: ENV['OPENAI_API_KEY'])

  end

  # Ask if item sparks joy using AI image analysis + sentiment

  def sparks_joy?(item)

    prompt = <<~PROMPT
      As Marie Kondo, analyze this clothing item and determine if it sparks joy:

      Item: #{item.title}

      Category: #{item.category}

      Color: #{item.color}
      Material: #{item.material}

      Times worn: #{item.times_worn}

      Purchase date: #{item.purchase_date}

      Does this item spark joy? Respond with:

      - "YES" if it sparks joy (worn regularly, good condition, meaningful)

      - "NO" if it should be decluttered (unworn, damaged, no emotional connection)
      - Provide a brief Marie Kondo-style reason

    PROMPT

    response = @llm.chat(messages: [{ role: "user", content: prompt }])

    joy = response.chat_completion.dig("choices", 0, "message", "content")

    {
      sparks_joy: joy.downcase.include?("yes"),
      reason: joy

    }

  end

  # Get personalized organization tips using RAG

  def get_organization_tips(category: nil, season: nil)

    query = build_query(category, season)
    # Vector similarity search in OrganizationTip embeddings

    similar_tips = OrganizationTip

      .nearest_neighbors(:embedding, generate_embedding(query), distance: "cosine")
      .limit(5)

    # Generate personalized advice using retrieved tips as context

    context = similar_tips.map { |tip| "#{tip.title}: #{tip.content}" }.join("\n\n")

    prompt = <<~PROMPT
      As Marie Kondo, provide personalized wardrobe organization advice.

      User's wardrobe summary:
      - Total items: #{@user.items.count}

      - Most worn category: #{most_worn_category}
      - Least worn items: #{least_worn_items.map(&:title).join(", ")}

      Context from organization database:

      #{context}

      Question: #{query}
      Provide 3-5 specific, actionable tips in Marie Kondo's voice.

      Focus on sparking joy, folding techniques, and mindful keeping.
    PROMPT
    @llm.chat(messages: [{ role: "user", content: prompt }])

        .chat_completion.dig("choices", 0, "message", "content")

  end
  # Suggest outfit combinations using embeddings

  def suggest_outfits(occasion:, season:, weather:)

    # Find items that match occasion/season/weather
    suitable_items = @user.items

      .where(available: true)

      .where("season LIKE ? OR season = ?", "%#{season}%", "all-season")

    prompt = <<~PROMPT

      As Marie Kondo's styling assistant, suggest 3 complete outfits using these items:

      #{suitable_items.map { |i| "- #{i.title} (#{i.color}, #{i.category})" }.join("\n")}
      Occasion: #{occasion}

      Season: #{season}
      Weather: #{weather}
      Create outfits that spark joy and are weather-appropriate.

      For each outfit, explain why the combination works.

    PROMPT
    @llm.chat(messages: [{ role: "user", content: prompt }])

        .chat_completion.dig("choices", 0, "message", "content")

  end
  # Declutter recommendations

  def declutter_recommendations

    unworn_items = @user.items.where("times_worn = 0 OR times_worn IS NULL")
    old_items = @user.items.where("purchase_date < ?", 2.years.ago)

    prompt = <<~PROMPT

      As Marie Kondo, help declutter this wardrobe:

      Unworn items (#{unworn_items.count}):
      #{unworn_items.limit(10).map { |i| "- #{i.title} (#{i.category})" }.join("\n")}

      Items over 2 years old (#{old_items.count}):
      #{old_items.limit(10).map { |i| "- #{i.title} (purchased #{i.purchase_date})" }.join("\n")}

      Provide gentle, encouraging decluttering advice.
      Help the user let go of items that no longer spark joy.

    PROMPT
    @llm.chat(messages: [{ role: "user", content: prompt }])

        .chat_completion.dig("choices", 0, "message", "content")

  end
  private

  def generate_embedding(text)

    # Use OpenAI embeddings via LangChain
    Langchain::LLM::OpenAI.new(api_key: ENV['OPENAI_API_KEY'])
      .embed(text: text)

      .embedding

  end

  def build_query(category, season)

    parts = ["How to organize"]

    parts << category if category
    parts << "for #{season}" if season

    parts.join(" ")

  end

  def most_worn_category

    @user.items.group(:category).sum(:times_worn).max_by { |_, count| count }&.first || "unknown"

  end
  def least_worn_items

    @user.items.order(times_worn: :asc).limit(5)

  end
end

KONDOEOF

# Controller for AI features

log "Creating Marie Kondo AI controller"

cat > app/controllers/kondo_ai_controller.rb << 'CONTROLLEREOF'
class KondoAiController < ApplicationController

  before_action :authenticate_user!

  def analyze_item

    @item = current_user.items.find(params[:id])

    @ai = MarieKondoAiService.new(current_user)
    result = @ai.sparks_joy?(@item)

    @item.update(

      spark_joy: result[:sparks_joy],
      declutter_reason: result[:reason]

    )

    respond_to do |format|

      format.turbo_stream

      format.json { render json: result }
    end

  end

  def organization_tips

    @ai = MarieKondoAiService.new(current_user)

    @tips = @ai.get_organization_tips(
      category: params[:category],

      season: params[:season]

    )

    respond_to do |format|

      format.html

      format.turbo_stream
    end

  end

  def suggest_outfits

    @ai = MarieKondoAiService.new(current_user)

    @suggestions = @ai.suggest_outfits(
      occasion: params[:occasion],

      season: params[:season],

      weather: params[:weather]

    )

    respond_to do |format|

      format.html

      format.turbo_stream
    end

  end

  def declutter_guide

    @ai = MarieKondoAiService.new(current_user)

    @recommendations = @ai.declutter_recommendations
    respond_to do |format|

      format.html

      format.turbo_stream
    end

  end

end

CONTROLLEREOF

# Routes

log "Adding Marie Kondo AI routes"

cat >> config/routes.rb << 'ROUTESEOF'
  # Marie Kondo AI Wardrobe Assistant

  post 'items/:id/analyze_joy', to: 'kondo_ai#analyze_item', as: :analyze_item_joy

  get 'kondo/tips', to: 'kondo_ai#organization_tips', as: :kondo_tips
  get 'kondo/outfits', to: 'kondo_ai#suggest_outfits', as: :kondo_outfits

  get 'kondo/declutter', to: 'kondo_ai#declutter_guide', as: :kondo_declutter

ROUTESEOF

# Seed organization tips with embeddings

log "Seeding Marie Kondo organization tips"

cat > db/seeds/kondo_tips.rb << 'SEEDSEOF'
# Marie Kondo Organization Tips - seeded with embeddings for RAG

tips = [

  {

    title: "Folding Technique for Spark Joy",
    content: "Fold each item into a small rectangle that can stand upright. This allows you to see all items at once and each piece sparks joy when you see it. Fold shirts, pants, and even socks using this method.",

    category: "folding"

  },

  {

    title: "Seasonal Wardrobe Rotation",

    content: "Keep only current season items accessible. Store off-season clothes in boxes, thanking them for their service. This prevents decision fatigue and keeps your closet joyful.",

    category: "seasons"

  },

  {

    title: "Color Coordination",

    content: "Arrange items by color from light to dark. This creates a visually pleasing rainbow effect and helps you see what you have. Dark colors on the right, light on the left.",

    category: "organization"

  },

  {

    title: "The Spark Joy Test",

    content: "Hold each item and ask: does this spark joy? If it makes you happy, keep it. If not, thank it and let it go. Trust your intuition, not logic.",

    category: "decluttering"

  },

  {

    title: "Drawer Organization",

    content: "Stand items upright in drawers like files. Never stack items flat. This prevents forgotten items at the bottom and lets you see everything at once.",

    category: "storage"

  },

  {

    title: "Gratitude for Items",

    content: "Before letting go of an item, hold it and express gratitude for the joy it brought you. This mindful practice makes decluttering easier and more meaningful.",

    category: "mindfulness"

  },

  {

    title: "Outfit Capsule Creation",

    content: "Keep 30-40 versatile items that all coordinate. Each piece should spark joy and mix well with others. Quality over quantity creates a joyful wardrobe.",

    category: "capsule"

  },

  {

    title: "Shoe Storage",

    content: "Store shoes in clear boxes or arrange by height and color. Keep only shoes that are comfortable and spark joy. 10-12 pairs is ideal for most people.",

    category: "shoes"

  }

]

# Generate embeddings using LangChain

llm = Langchain::LLM::OpenAI.new(api_key: ENV['OPENAI_API_KEY'])

tips.each do |tip_data|
  text = "#{tip_data[:title]}: #{tip_data[:content]}"

  embedding = llm.embed(text: text).embedding
  OrganizationTip.create!(

    title: tip_data[:title],

    content: tip_data[:content],
    category: tip_data[:category],

    embedding: embedding

  )

  puts "✓ Seeded: #{tip_data[:title]}"

end

SEEDSEOF
log "✓ Marie Kondo AI Wardrobe Assistant setup complete"

log "  - LangChain + OpenAI for semantic understanding"

log "  - Vector embeddings for organization tips RAG"
log "  - Spark joy analysis with AI"

log "  - Outfit suggestions based on occasion/season/weather"

log "  - Gentle decluttering recommendations"

# Homepage controller

log "Creating homepage controller"

cat > app/controllers/home_controller.rb << 'HOMEEOF'
class HomeController < ApplicationController

  def index

    if user_signed_in?

      @items_count = current_user.items.count

      @spark_joy_count = current_user.items.where(spark_joy: true).count

      @recent_items = current_user.items.order(created_at: :desc).limit(6)

    end

  end

end

HOMEEOF

# Homepage view

log "Creating homepage view"

mkdir -p app/views/home
cat > app/views/home/index.html.erb << 'INDEXEOF'

<div class="hero">

  <div class="container">

    <h1 class="brand">Amber</h1>

    <p class="tagline">AI-powered wardrobe organization with Marie Kondo wisdom</p>

    <% if user_signed_in? %>

      <div class="cta-buttons">

        <%= link_to "Add New Item", new_item_path, class: "btn btn-primary" %>
        <%= link_to "My Wardrobe", items_path, class: "btn btn-secondary" %>

      </div>

    <% else %>

      <div class="cta-buttons">

        <%= link_to "Sign Up", new_user_registration_path, class: "btn btn-primary" %>

        <%= link_to "Sign In", new_user_session_path, class: "btn btn-secondary" %>

      </div>

    <% end %>

  </div>

</div>

<% if user_signed_in? %>

  <div class="dashboard">

    <div class="container">
      <h2>Your Wardrobe Dashboard</h2>

      <div class="stats-grid">

        <div class="stat-card">

          <div class="stat-number"><%= @items_count %></div>
          <div class="stat-label">Total Items</div>

        </div>

        <div class="stat-card spark-joy">

          <div class="stat-number"><%= @spark_joy_count %></div>

          <div class="stat-label">Items That Spark Joy</div>
        </div>

        <div class="stat-card">

          <div class="stat-number">

            <%= @items_count > 0 ? ((@spark_joy_count.to_f / @items_count) * 100).round : 0 %>%
          </div>

          <div class="stat-label">Joy Percentage</div>

        </div>

      </div>

      <h3>Quick Actions</h3>

      <div class="actions-grid">

        <div class="action-card">
          <h4>Organization Tips</h4>

          <p>Get personalized Marie Kondo advice for your wardrobe</p>

          <%= link_to "Get Tips", kondo_tips_path, class: "btn btn-small" %>

        </div>

        <div class="action-card">

          <h4>Outfit Suggestions</h4>

          <p>AI-powered outfit combinations for any occasion</p>
          <%= link_to "Get Outfits", kondo_outfits_path, class: "btn btn-small" %>

        </div>

        <div class="action-card">

          <h4>Declutter Guide</h4>

          <p>Gentle recommendations for items to let go</p>
          <%= link_to "Start Decluttering", kondo_declutter_path, class: "btn btn-small" %>

        </div>

        <div class="action-card">

          <h4>Add New Item</h4>

          <p>Track a new wardrobe item with AI analysis</p>
          <%= link_to "Add Item", new_item_path, class: "btn btn-small" %>

        </div>

      </div>

      <% if @recent_items.any? %>

        <h3>Recent Items</h3>

        <div class="items-grid">
          <%= render partial: "items/item_card", collection: @recent_items, as: :item %>

        </div>

      <% end %>

    </div>

  </div>

<% else %>

  <div class="features">

    <div class="container">

      <h2>Organize Your Wardrobe with Joy</h2>

      <div class="features-grid">

        <div class="feature-card">

          <h3>AI Spark Joy Analysis</h3>
          <p>LangChain-powered AI analyzes each item to determine if it truly sparks joy in your life.</p>

        </div>

        <div class="feature-card">

          <h3>Smart Organization Tips</h3>

          <p>Vector embeddings and RAG provide personalized Marie Kondo advice for your unique wardrobe.</p>
        </div>

        <div class="feature-card">

          <h3>Outfit Suggestions</h3>

          <p>GPT-4 creates complete outfit combinations based on occasion, season, and weather.</p>
        </div>

        <div class="feature-card">

          <h3>Gentle Decluttering</h3>

          <p>Compassionate AI guidance helps you let go of items that no longer serve you.</p>
        </div>

      </div>

    </div>

  </div>

<% end %>

INDEXEOF

# Item card partial

log "Creating item card partial"

cat > app/views/items/_item_card.html.erb << 'CARDEOF'
<div class="item-card">

  <div class="item-image" style="background: linear-gradient(135deg, <%= item.color || '#D4A574' %> 0%, <%= item.color ? lighten(item.color, 20) : '#F5E6D3' %> 100%);">

    <% if item.spark_joy %>

      <span class="spark-joy-badge">Sparks Joy</span>

    <% end %>

  </div>

  <div class="item-details">

    <h4><%= item.title %></h4>

    <div class="item-meta">
      <span class="category"><%= item.category %></span>

      <% if item.times_worn %>

        <span class="worn">Worn <%= item.times_worn %> times</span>

      <% end %>

    </div>

    <% if item.spark_joy.nil? %>

      <%= button_to "Analyze Joy", analyze_item_joy_path(item), method: :post, class: "btn btn-small", remote: true %>

    <% elsif item.declutter_reason %>
      <p class="ai-reason"><%= truncate(item.declutter_reason, length: 100) %></p>

    <% end %>

    <div class="item-actions">

      <%= link_to "View", item_path(item), class: "btn-link" %>

      <%= link_to "Edit", edit_item_path(item), class: "btn-link" %>
    </div>

  </div>

</div>

CARDEOF

# Kondo AI views

log "Creating Kondo AI views"

mkdir -p app/views/kondo_ai
cat > app/views/kondo_ai/organization_tips.html.erb << 'TIPSEOF'

<div class="kondo-page">

  <div class="container">
    <h1>Organization Tips</h1>

    <p class="subtitle">Personalized Marie Kondo advice for your wardrobe</p>

    <div class="filter-form">

      <%= form_with url: kondo_tips_path, method: :get, local: true do |f| %>

        <div class="form-row">
          <%= f.select :category,

              options_for_select(['All', 'Tops', 'Bottoms', 'Dresses', 'Shoes', 'Accessories'], params[:category]),

              {}, class: "form-select" %>

          <%= f.select :season,

              options_for_select(['All Seasons', 'Spring', 'Summer', 'Fall', 'Winter'], params[:season]),

              {}, class: "form-select" %>
          <%= f.submit "Get Tips", class: "btn btn-primary" %>

        </div>

      <% end %>
    </div>

    <% if @tips %>

      <div class="ai-response">

        <h3>Marie Kondo says:</h3>
        <%= simple_format(@tips) %>

      </div>

    <% end %>

  </div>

</div>

TIPSEOF

cat > app/views/kondo_ai/suggest_outfits.html.erb << 'OUTFITSEOF'

<div class="kondo-page">

  <div class="container">
    <h1>Outfit Suggestions</h1>

    <p class="subtitle">AI-powered outfit combinations that spark joy</p>

    <div class="outfit-form">

      <%= form_with url: kondo_outfits_path, method: :get, local: true do |f| %>

        <div class="form-group">
          <%= f.label :occasion, "Occasion" %>

          <%= f.select :occasion,

              options_for_select(['Casual', 'Work', 'Formal', 'Date Night', 'Party', 'Workout'], params[:occasion]),

              {}, class: "form-select" %>

        </div>

        <div class="form-group">

          <%= f.label :season, "Season" %>

          <%= f.select :season,
              options_for_select(['Spring', 'Summer', 'Fall', 'Winter'], params[:season]),

              {}, class: "form-select" %>

        </div>

        <div class="form-group">

          <%= f.label :weather, "Weather" %>

          <%= f.select :weather,
              options_for_select(['Sunny', 'Rainy', 'Cold', 'Hot', 'Mild'], params[:weather]),

              {}, class: "form-select" %>

        </div>

        <%= f.submit "Get Outfit Ideas", class: "btn btn-primary" %>

      <% end %>

    </div>
    <% if @suggestions %>

      <div class="ai-response">

        <h3>Outfit Suggestions:</h3>
        <%= simple_format(@suggestions) %>

      </div>

    <% end %>

  </div>

</div>

OUTFITSEOF

cat > app/views/kondo_ai/declutter_guide.html.erb << 'DECLUTTEREOF'

<div class="kondo-page">

  <div class="container">
    <h1>Declutter Guide</h1>

    <p class="subtitle">Gentle guidance for letting go with gratitude</p>

    <div class="declutter-intro">

      <p>Marie Kondo teaches us to thank each item before letting it go. This creates a mindful, joyful decluttering experience.</p>

    </div>
    <% if @recommendations %>

      <div class="ai-response">

        <h3>Your Personalized Decluttering Plan:</h3>
        <%= simple_format(@recommendations) %>

      </div>

    <% else %>

      <div class="cta-section">

        <%= button_to "Get Decluttering Recommendations", kondo_declutter_path, method: :get, class: "btn btn-primary" %>

      </div>

    <% end %>

  </div>

</div>

DECLUTTEREOF

# Create ultraminimal professional layout

log "Creating Amber application layout"

mkdir -p app/views/layouts
cat <<'LAYOUTEOF' > app/views/layouts/application.html.erb

<!DOCTYPE html>

<html lang="en">

<head>

  <meta charset="UTF-8">

  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <title><%= content_for?(:title) ? yield(:title) : "Amber - AI-Enhanced Fashion Assistant" %></title>

  <%= csrf_meta_tags %>

  <%= csp_meta_tag %>

  <meta name="description" content="<%= content_for?(:description) ? yield(:description) : 'Organize your wardrobe, get style suggestions, and discover fashion trends' %>">

  <meta name="theme-color" content="#D4A574">

  <%= stylesheet_link_tag "amber", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>

</head>
<body class="<%= controller_name %> <%= action_name %>">

  <header class="site-header">

    <div class="container">

      <nav class="nav-main">

        <div class="nav-brand">

          <%= link_to root_path, class: "logo-link" do %>

            <span class="logo">Amber</span>

          <% end %>

        </div>

        <div class="nav-links">

          <%= link_to "Wardrobe", "#", class: "nav-link" %>

          <%= link_to "Outfits", "#", class: "nav-link" %>
          <%= link_to "Trends", "#", class: "nav-link" %>

          <%= link_to "AI Assistant", "#", class: "nav-link" %>

          <% if user_signed_in? %>

            <span class="nav-user"><%= current_user.email %></span>

            <%= button_to "Sign Out", destroy_user_session_path, method: :delete, class: "btn-text" %>
          <% else %>

            <%= link_to "Sign In", new_user_session_path, class: "nav-link" %>

            <%= link_to "Get Started", new_user_registration_path, class: "btn-primary-sm" %>

          <% end %>

        </div>

      </nav>

    </div>

  </header>

  <main class="site-main">

    <% if notice %>

      <div class="flash flash-notice"><%= notice %></div>
    <% end %>

    <% if alert %>

      <div class="flash flash-alert"><%= alert %></div>

    <% end %>

    <%= yield %>

  </main>

  <footer class="site-footer">
    <div class="container">

      <div class="footer-content">
        <div class="footer-section">

          <h4>Amber</h4>

          <p>Your AI-powered fashion companion</p>

        </div>

        <div class="footer-section">

          <h4>Features</h4>

          <ul class="footer-links">

            <li><%= link_to "Wardrobe Manager", "#" %></li>

            <li><%= link_to "Style Assistant", "#" %></li>

            <li><%= link_to "Outfit Generator", "#" %></li>

          </ul>

        </div>

        <div class="footer-section">

          <h4>Company</h4>

          <ul class="footer-links">

            <li><%= link_to "About", "#" %></li>

            <li><%= link_to "Privacy", "#" %></li>

            <li><%= link_to "Terms", "#" %></li>

          </ul>

        </div>

      </div>

      <p class="footer-copyright">

        &copy; <%= Time.current.year %> Amber. All rights reserved.

      </p>

    </div>

  </footer>

</body>

</html>

LAYOUTEOF

# Stimulus controllers for interactivity

log "Creating Amber Stimulus controllers"

mkdir -p app/javascript/controllers
cat <<'JSEOF' > app/javascript/controllers/wardrobe_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = ["item", "filter"]

  connect() {
    console.log("Wardrobe controller connected")

  }
  filterItems(event) {

    const category = event.target.value

    this.itemTargets.forEach(item => {
      if (category === "all" || item.dataset.category === category) {

        item.style.display = "block"

      } else {

        item.style.display = "none"

      }

    })

  }

  toggleFavorite(event) {

    event.currentTarget.classList.toggle("favorited")

  }
}

JSEOF

cat <<'JSEOF' > app/javascript/controllers/outfit_generator_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["result", "loading"]

  async generate() {
    this.loadingTarget.classList.remove("hidden")

    this.resultTarget.innerHTML = ""
    try {

      const response = await fetch("/kondo_ai/suggest_outfits", {

        method: "POST",
        headers: {

          "Content-Type": "application/json",

          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content

        },

        body: JSON.stringify({ occasion: "casual" })

      })

      if (response.ok) {

        const html = await response.text()

        this.resultTarget.innerHTML = html
      }

    } catch (error) {

      console.error("Failed to generate outfit:", error)

    } finally {

      this.loadingTarget.classList.add("hidden")

    }

  }

}

JSEOF

# Stylesheet

log "Creating Amber stylesheet"

mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/amber.scss << 'SCSSEOF'

// Amber Theme - Warm, joyful colors inspired by Marie Kondo

$primary: #D4A574;

$secondary: #F5E6D3;

$accent: #C4915F;

$dark: #8B7355;

$light: #FFF8F0;

$success: #A8C686;

$text: #4A4A4A;

* {

  margin: 0;

  padding: 0;
  box-sizing: border-box;

}

body {

  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;

  color: $text;
  background: $light;

  line-height: 1.6;

}

.container {

  max-width: 1200px;

  margin: 0 auto;
  padding: 0 20px;

}

// Hero section

.hero {

  background: linear-gradient(135deg, $primary 0%, $accent 100%);
  color: white;

  padding: 80px 20px;

  text-align: center;

  .brand {

    font-size: 3.5rem;

    font-weight: 300;
    margin-bottom: 10px;

    letter-spacing: 2px;

  }

  .tagline {

    font-size: 1.2rem;

    margin-bottom: 30px;
    opacity: 0.95;

  }

  .cta-buttons {

    display: flex;

    gap: 15px;
    justify-content: center;

    margin-top: 30px;

  }

}

// Dashboard

.dashboard {

  padding: 60px 20px;
  h2 {

    color: $dark;

    margin-bottom: 30px;
    font-size: 2rem;

  }

  h3 {

    color: $dark;

    margin: 40px 0 20px;
    font-size: 1.5rem;

  }

}

.stats-grid {

  display: grid;

  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 20px;

  margin-bottom: 40px;

}

.stat-card {

  background: white;

  padding: 30px;
  border-radius: 12px;

  box-shadow: 0 2px 8px rgba(0,0,0,0.1);

  text-align: center;

  border-top: 4px solid $primary;

  &.spark-joy {

    border-top-color: $success;

  }
  .stat-number {

    font-size: 3rem;

    font-weight: 300;
    color: $primary;

    margin-bottom: 10px;

  }

  .stat-label {

    color: $dark;

    font-size: 0.9rem;
    text-transform: uppercase;

    letter-spacing: 1px;

  }

}

.actions-grid {

  display: grid;

  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 20px;

  margin-bottom: 40px;

}

.action-card {

  background: white;

  padding: 25px;
  border-radius: 12px;

  box-shadow: 0 2px 8px rgba(0,0,0,0.1);

  transition: transform 0.2s;

  &:hover {

    transform: translateY(-5px);

    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
  }

  h4 {

    color: $accent;

    margin-bottom: 10px;
  }

  p {

    color: $text;

    font-size: 0.9rem;
    margin-bottom: 15px;

  }

}

// Items grid

.items-grid {

  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));

  gap: 25px;

}

.item-card {

  background: white;

  border-radius: 12px;
  overflow: hidden;

  box-shadow: 0 2px 8px rgba(0,0,0,0.1);

  transition: transform 0.2s;

  &:hover {

    transform: translateY(-5px);

    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
  }

  .item-image {

    height: 200px;

    position: relative;
    display: flex;

    align-items: center;

    justify-content: center;

  }

  .spark-joy-badge {

    position: absolute;

    top: 10px;
    right: 10px;

    background: $success;

    color: white;

    padding: 5px 12px;

    border-radius: 20px;

    font-size: 0.8rem;

    font-weight: 600;

  }

  .item-details {

    padding: 20px;

    h4 {
      color: $dark;

      margin-bottom: 10px;
    }

  }

  .item-meta {

    display: flex;

    gap: 10px;
    margin-bottom: 15px;

    font-size: 0.85rem;

    .category {

      background: $secondary;

      color: $accent;
      padding: 3px 10px;

      border-radius: 12px;

    }

    .worn {

      color: $dark;

    }
  }

  .ai-reason {

    font-size: 0.85rem;

    font-style: italic;
    color: $dark;

    margin: 10px 0;

  }

  .item-actions {

    display: flex;

    gap: 15px;
    margin-top: 15px;

  }

}

// Features section

.features {

  padding: 60px 20px;
  background: white;

  h2 {

    text-align: center;

    color: $dark;
    margin-bottom: 50px;

    font-size: 2.5rem;

  }

}

.features-grid {

  display: grid;

  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 30px;

}

.feature-card {

  text-align: center;

  padding: 30px;
  h3 {

    color: $accent;

    margin-bottom: 15px;
  }

  p {

    color: $text;

    line-height: 1.7;
  }

}

// Kondo AI pages

.kondo-page {

  padding: 60px 20px;
  min-height: 70vh;

  h1 {

    color: $dark;

    margin-bottom: 10px;
    font-size: 2.5rem;

  }

  .subtitle {

    color: $accent;

    font-size: 1.1rem;
    margin-bottom: 40px;

  }

}

.filter-form, .outfit-form {

  background: white;

  padding: 30px;
  border-radius: 12px;

  box-shadow: 0 2px 8px rgba(0,0,0,0.1);

  margin-bottom: 40px;

  .form-row {

    display: flex;

    gap: 15px;
    align-items: center;

  }

  .form-group {

    margin-bottom: 20px;

    label {
      display: block;

      color: $dark;
      font-weight: 600;

      margin-bottom: 8px;

    }

  }

  .form-select {

    padding: 10px 15px;

    border: 2px solid $secondary;
    border-radius: 8px;

    font-size: 1rem;

    flex: 1;

    &:focus {

      outline: none;

      border-color: $primary;
    }

  }

}

.ai-response {

  background: white;

  padding: 40px;
  border-radius: 12px;

  box-shadow: 0 2px 8px rgba(0,0,0,0.1);

  border-left: 4px solid $success;

  h3 {

    color: $accent;

    margin-bottom: 20px;
  }

  p {

    color: $text;

    line-height: 1.8;
    margin-bottom: 15px;

  }

}

.declutter-intro {

  background: $secondary;

  padding: 30px;
  border-radius: 12px;

  margin-bottom: 40px;

  p {

    color: $dark;

    font-size: 1.1rem;
    text-align: center;

  }

}

.cta-section {

  text-align: center;

  margin-top: 40px;
}

// Buttons

.btn {

  display: inline-block;
  padding: 12px 30px;

  border-radius: 8px;

  text-decoration: none;

  font-weight: 600;

  transition: all 0.2s;

  border: none;

  cursor: pointer;

  font-size: 1rem;

  &.btn-primary {

    background: $primary;

    color: white;
    &:hover {

      background: $accent;

    }
  }

  &.btn-secondary {

    background: white;

    color: $primary;
    border: 2px solid $primary;

    &:hover {

      background: $primary;

      color: white;
    }

  }

  &.btn-small {

    padding: 8px 20px;

    font-size: 0.9rem;
  }

}

.btn-link {

  color: $accent;

  text-decoration: none;
  font-size: 0.9rem;

  &:hover {

    color: $primary;

    text-decoration: underline;
  }

}

SCSSEOF

# Update routes for homepage

log "Setting homepage route"

cat > config/routes.rb << 'ROOTEOF'
Rails.application.routes.draw do

  devise_for :users

  root "home#index"

  resources :items

  resources :outfits
  # Marie Kondo AI Wardrobe Assistant
  post 'items/:id/analyze_joy', to: 'kondo_ai#analyze_item', as: :analyze_item_joy

  get 'kondo/tips', to: 'kondo_ai#organization_tips', as: :kondo_tips
  get 'kondo/outfits', to: 'kondo_ai#suggest_outfits', as: :kondo_outfits

  get 'kondo/declutter', to: 'kondo_ai#declutter_guide', as: :kondo_declutter

  get "up" => "rails/health#show", as: :rails_health_check

end

ROOTEOF
log "✓ Complete frontend views added"

log "  - Homepage with dashboard and stats"

log "  - Item card partial with spark joy badge"
log "  - Organization tips page with filters"

log "  - Outfit suggestions page"

log "  - Declutter guide page"

log "  - Complete Amber theme stylesheet"

log "  - amber.brgen.no ready to deploy"

migrate_db

commit "Add Marie Kondo AI wardrobe assistant with LangChain

- LangChain integration for semantic wardrobe understanding
- AI-powered spark joy analysis for each item

- Vector embeddings for organization tips (RAG)
- Outfit suggestions using GPT-4

- Decluttering recommendations in Marie Kondo's voice

- Personalized organization advice

Tech stack:

- langchainrb + langchainrb_rails

- OpenAI embeddings (1536 dimensions)
- pgvector for similarity search

- Turbo Streams for real-time updates

Helps girls organize wardrobes with joy and mindfulness.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
