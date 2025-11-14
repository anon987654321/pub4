#!/bin/zsh

APP="amber"
BASE_DIR="$HOME/rails/$APP"

# Create the application directory if it doesn't exist and navigate to it
mkdir -p $BASE_DIR && cd $BASE_DIR

# Function to execute a script and handle errors
execute_script() {
  script_name=$1
  shift
  echo "Running $script_name..."
  if zsh "$script_name" "$@" ; then
    echo "$script_name completed successfully."
  else
    echo "$script_name failed. Exiting..."
    exit 1
  fi
}

# -- SOURCE PARTIALS --

execute_script "../__shared/@postgresql.sh"
execute_script "../__shared/@redis.sh"
execute_script "../__shared/@yarn.sh"
execute_script "../__shared/@rails_new.sh"
execute_script "../__shared/@pwa.sh"
execute_script "../__shared/@active_storage_and_imageprocessing.sh"
execute_script "../__shared/@devise.sh"
execute_script "../__shared/@falcon.sh"
execute_script "../__shared/@ai.sh"
execute_script "../__shared/@posts_communities_and_comments.sh"
execute_script "../__shared/@instant_and_private_message.sh"
execute_script "../__shared/@live_cam_streaming.sh"
execute_script "../__shared/@social_media_sharing.sh"
execute_script "../__shared/@push_notifications.sh"

# -- GENERATE MODELS --

bin/rails generate scaffold Item title:string content:text color:string size:string material:string texture:string brand:string price:decimal category:string stock_quantity:integer available:boolean sku:string release_date:date user:references
bin/rails generate scaffold Outfit name:string description:text image_url:string category:string user:references
bin/rails generate controller Search
bin/rails generate controller Home index

mkdir -p app/views/home app/views/items app/views/looks app/views/layouts app/views/pages app/views/features app/views/outfits app/views/recommendations app/views/search

cat <<EOF > app/views/layouts/application.html.erb
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="<%= form_authenticity_token %>">
    <title><%= t("site.title") %></title>
    <%= stylesheet_link_tag "application", media: "all", "data-turbo-track": "reload" %>
    <%= javascript_include_tag "application", "data-turbo-track": "reload" %>
    <%= tag.script(type: "application/ld+json") { render(partial: "shared/jsonld") } %>
  </head>
  <body>
    <%= yield %>
    <%= cable_ready_channel_tag %>
    <%= stimulus_include_tag %>
  </body>
</html>
EOF

cat <<EOF > app/views/home/_header.html.erb
<%= tag.header do %>
  <%= tag.nav do %>
    <%= image_tag("logo.svg", alt: t("brand.logo_alt")) %>
    <%= link_to t("navigation.home"), root_path %>
    <%= link_to t("features.visualize_your_wardrobe"), visualize_your_wardrobe_path %>
    <%= link_to t("features.style_assistant"), style_assistant_path %>
    <%= link_to t("features.mix_match_magic"), mix_match_magic_path %>
    <%= link_to t("features.shop_smarter"), shop_smarter_path %>
    <%= link_to t("navigation.search"), search_path %>
    <%= button_to t("navigation.login"), "#", data: { action: "dialog#open" } %>
    <%= button_to t("navigation.dark_mode"), "#", data: { action: "dark-mode#toggle" } %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/home/_footer.html.erb
<%= tag.footer do %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.about_amber") %>
    <%= tag.p t("footer.about_description") %>
  <% end %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.explore") %>
    <%= link_to t("footer.special_offers"), "#" %>
    <%= link_to t("footer.ethical_practices"), "#" %>
    <%= link_to t("footer.upcoming_designers"), "#" %>
  <% end %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.legal") %>
    <%= link_to t("footer.privacy_policy"), "#" %>
    <%= link_to t("footer.terms_of_service"), "#" %>
  <% end %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.contact_us") %>
    <%= tag.p t("footer.contact_info") %>
    <%= link_to t("footer.email_us"), "mailto:info@amber.fashion" %>
  <% end %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.supporting_wildlife") %>
    <%= tag.p t("footer.supporting_wildlife_description") %>
  <% end %>
<% end %>
EOF

# -- SET UP CONTROLLERS AND VIEWS FOR FEATURES --

cat <<EOF > app/controllers/home_controller.rb
class HomeController < ApplicationController
  def index
    @suggestions = generate_mix_and_match_suggestions(current_user.posts)
  end

  private

  def generate_mix_and_match_suggestions(posts)
    posts.sample(3)
  end
end
EOF

cat <<EOF > app/controllers/features_controller.rb
class FeaturesController < ApplicationController
  before_action :authenticate_user!

  def visualize_your_wardrobe
    @posts = current_user.posts
    # Additional logic for categorizing and organizing clothes
  end

  def style_assistant
    @outfits = current_user.outfits
  end

  def mix_match_magic
    @posts = current_user.posts
    @suggestions = generate_mix_and_match_suggestions(@posts)
  end

  def shop_smarter
    @recommendations = current_user.recommendations
  end

  private

  def generate_mix_and_match_suggestions(posts)
    posts.sample(3)
  end
end
EOF

cat <<EOF > app/controllers/outfits_controller.rb
class OutfitsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_outfit, only: [:show, :edit, :update, :destroy]

  def index
    @outfits = current_user.outfits
  end

  def show
  end

  def new
    @outfit = current_user.outfits.build
  end

  def create
    @outfit = current_user.outfits.build(outfit_params)
    if @outfit.save
      redirect_to @outfit, notice: t("outfits.create.success")
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @outfit.update(outfit_params)
      redirect_to @outfit, notice: t("outfits.update.success")
    else
      render :edit
    end
  end

  def destroy
    @outfit.destroy
    redirect_to outfits_url, notice: t("outfits.destroy.success")
  end

  private

  def set_outfit
    @outfit = current_user.outfits.find(params[:id])
  end

  def outfit_params
    params.require(:outfit).permit(:name, :description, post_ids: [])
  end
end
EOF

cat <<EOF > app/controllers/recommendations_controller.rb
class RecommendationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_recommendation, only: [:show, :edit, :update, :destroy]

  def index
    @recommendations = current_user.recommendations
  end

  def show
  end

  def new
    @recommendation = current_user.recommendations.build
  end

  def create
    @recommendation = current_user.recommendations.build(recommendation_params)
    if @recommendation.save
      redirect_to @recommendation, notice: t("recommendations.create.success")
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @recommendation.update(recommendation_params)
      redirect_to @recommendation, notice: t("recommendations.update.success")
    else
      render :edit
    end
  end

  def destroy
    @recommendation.destroy
    redirect_to recommendations_url, notice: t("recommendations.destroy.success")
  end

  private

  def set_recommendation
    @recommendation = current_user.recommendations.find(params[:id])
  end

  def recommendation_params
    params.require(:recommendation).permit(:post_id, :recommended_by)
  end
end
EOF

cat <<EOF > app/controllers/search_controller.rb
class SearchController < ApplicationController
  def index
    @query = params[:query]
    @results = if @query.present?
      Item.where("title ILIKE ?", "%#{@query}%")
    else
      []
    end
  end
end
EOF

# -- POST VIEWS --

cat <<EOF > app/views/posts/index.html.erb
<%= tag.section do %>
  <%= tag.h1 t("posts.index.title") %>
  <%= tag.section do %>
    <% @posts.each do |post| %>
      <%= tag.section itemscope itemtype="http://schema.org/Product" do %>
        <%= link_to image_tag(post.image_url, alt: post.title), post %>
        <%= tag.h2 itemprop="name" do %><%= post.title %></%=>
        <%= tag.p itemprop="description" do %><%= post.description %></%=>
      </%=>
    <% end %>
  </%=>
<% end %>
EOF

cat <<EOF > app/views/posts/show.html.erb
<%= tag.section itemscope itemtype="http://schema.org/Product" do %>
  <%= tag.h1 itemprop="name" do %><%= @post.title %></%=>
  <%= image_tag @post.image_url, alt: @post.title %>
  <%= tag.p itemprop="description" do %><%= @post.description %></%=
  <%= link_to t("posts.back"), posts_path %>
</%=
EOF

# -- ADDITIONAL SETUP --

mkdir -p config/locales
cat <<EOF > config/locales/en.yml
en:
  site:
    title: "Amber Fashion"
  navigation:
    home: "Home"
    search: "Search"
    login: "Login"
    dark_mode: "Toggle Dark Mode"
  features:
    visualize_your_wardrobe: "Visualize Your Wardrobe"
    style_assistant: "Style Assistant"
    mix_match_magic: "Mix & Match Magic"
    shop_smarter: "Shop Smarter"
  footer:
    about_amber: "About Amber"
    about_description: "Amber Fashion is your one-stop destination for innovative fashion."
    explore: "Explore"
    special_offers: "Special Offers"
    ethical_practices: "Ethical Practices"
    upcoming_designers: "Upcoming Designers"
    legal: "Legal"
    privacy_policy: "Privacy Policy"
    terms_of_service: "Terms of Service"
    contact_us: "Contact Us"
    contact_info: "Contact us at"
    email_us: "Email Us"
    supporting_wildlife: "Supporting Wildlife"
    supporting_wildlife_description: "Amber Fashion supports wildlife conservation efforts."
EOF

cat <<EOF > config/locales/no.yml
no:
  site:
    title: "Amber Fashion"
  navigation:
    home: "Hjem"
    search: "Søk"
    login: "Logg inn"
    dark_mode: "Bytt til mørk modus"
  features:
    visualize_your_wardrobe: "Visualiser Garderoben Din"
    style_assistant: "Stilassistent"
    mix_match_magic: "Mix & Match Magi"
    shop_smarter: "Handle Smartere"
  footer:
    about_amber: "Om Amber"
    about_description: "Amber Fashion er din one-stop destinasjon for innovativ mote."
    explore: "Utforsk"
    special_offers: "Spesialtilbud"
    ethical_practices: "Etiske Praksiser"
    upcoming_designers: "Kommande Designere"
    legal: "Juridisk"
    privacy_policy: "Personvern"
    terms_of_service: "Vilkår for Tjenester"
    contact_us: "Kontakt Oss"
    contact_info: "Kontakt oss på"
    email_us: "Send oss en e-post"
    supporting_wildlife: "Støtte til Villmarken"
    supporting_wildlife_description: "Amber Fashion støtter bevaring av villmark."
EOF

echo "Amber setup complete."

