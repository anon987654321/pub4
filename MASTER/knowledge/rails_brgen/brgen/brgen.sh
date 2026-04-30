#!/bin/zsh

echo "BRGEN INSTALLER 1.0"

commit_to_git() {
  git add -A
  git commit -m "$1"
  echo "$1"
}

# -- INSTALL AND CONFIGURE POSTGRESQL --

if ! command -v psql &>/dev/null; then
  doas pkg_add postgresql-server
  doas rcctl enable postgresql
fi

if ! doas -u _postgresql pg_ctl status -D /var/postgresql/data &>/dev/null; then
  doas rcctl stop postgresql || true
  doas rm -rf /var/postgresql/data
  doas mkdir /var/postgresql/data
  doas chown _postgresql:_postgresql /var/postgresql/data
  doas -u _postgresql initdb -D /var/postgresql/data -E UTF8
  doas rcctl start postgresql
  sleep 10

  if ! doas -u _postgresql pg_ctl status -D /var/postgresql/data; then
    echo "PostgreSQL failed to start. Exiting..."
    exit 1
  fi

  doas -u _postgresql psql -d postgres -c "CREATE ROLE dev WITH LOGIN SUPERUSER;"
  doas -u _postgresql psql -d postgres -c "CREATE DATABASE brgen_development OWNER dev;"
  doas -u _postgresql psql -d postgres -c "CREATE DATABASE brgen_test OWNER dev;"
  doas -u _postgresql psql -d postgres -c "CREATE DATABASE brgen_production OWNER dev;"

  DB_PASS=$(pwgen 16 1)
  doas -u _postgresql psql -d postgres -c "DROP USER IF EXISTS brgen_development;"
  doas -u _postgresql psql -d postgres -c "CREATE USER brgen_development WITH LOGIN PASSWORD '${DB_PASS}';"
  echo "local all brgen_development scram-sha-256" | doas tee -a /var/postgresql/data/pg_hba.conf
  doas rcctl reload postgresql

  if ! doas -u _postgresql pg_ctl status -D /var/postgresql/data; then
    echo "PostgreSQL failed to start after configuration changes. Exiting..."
    exit 1
  fi
fi

if ! grep -q "permit nopass :wheel as _postgresql" /etc/doas.conf; then
  echo "permit nopass :wheel as _postgresql" | doas tee -a /etc/doas.conf
  commit_to_git "Install and configure PostgreSQL"
else
  echo "Install and configure PostgreSQL"
fi

# -- ENSURE REDIS IS INSTALLED AND RUNNING --

if ! command -v redis-server &>/dev/null; then
  doas pkg_add redis
  doas rcctl enable redis
fi
doas rcctl start redis
echo "Ensure Redis is installed and running"

# -- INSTALL YARN --

if ! command -v yarn &>/dev/null; then
  doas npm install yarn -g
fi
echo "Ensure Yarn is installed"

# -- CREATE AND SET UP RAILS APPLICATION --

gem install bundler --user-install
gem install rails --user-install

bundle config set --local path "$HOME/.local"

if [ ! -d "brgen" ]; then
  rails new brgen --database=postgresql --javascript=esbuild --css=sass --assets=propshaft
  cd brgen
  git init
  bundle install
  yarn install
  commit_to_git "Initial commit: Generate Rails app with PostgreSQL, Esbuild, SASS, and Propshaft."
else
  cd brgen
fi

# -- SET UP ACTIVE STORAGE AND IMAGE PROCESSING --

if ! psql -U dev -d brgen_development -c "SELECT to_regclass('public.active_storage_blobs');" | grep -q 'active_storage_blobs'; then
  bin/rails active_storage:install
  bin/rails db:migrate
  bundle add image_processing
  commit_to_git "Set up Active Storage and ImageProcessing."
else
  echo "Active Storage tables already exist, skipping migration."
fi

# -- LOAD DEVISE SETUP --

source ./devise.sh

# -- SET UP OMNIAUTH FOR USER AUTHENTICATION --

bundle add omniauth-openid-connect
bundle add omniauth-google-oauth2
bundle add omniauth-snapchat

mkdir -p app/controllers/users

cat <<EOF > app/controllers/users/omniauth_callbacks_controller.rb
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def vipps
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Vipps") if is_navigational_format?
    else
      session["devise.vipps_data"] = request.env["omniauth.auth"].except("extra")
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\\n")
    end
  end

  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      session["devise.google_data"] = request.env["omniauth.auth"].except("extra")
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\\n")
    end
  end

  def snapchat
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Snapchat") if is_navigational_format?
    else
      session["devise.snapchat_data"] = request.env["omniauth.auth"].except("extra")
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\\n")
    end
  end
end
EOF

cat <<EOF > app/models/user.rb
class User < ApplicationRecord
  devise :omniauthable, omniauth_providers: %i[vipps google_oauth2 snapchat]

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.name = auth.info.name
    end
  end
end
EOF
commit_to_git "Set up OmniAuth for Vipps, Google, and Snapchat."

# -- INSTALL AI DEPENDENCIES --

doas pkg_add llvm-16.0.6p8

# -- CONFIGURE FALCON AS THE PRIMARY WEB SERVER --

bundle add falcon
bundle add async
bundle add async-redis
bundle add async-websocket

cat <<EOF > config/falcon.rb
#!/usr/bin/env falcon-host
# Falcon for Rails with ActionCable support

ENV["RAILS_ENV"] ||= "production"

require_relative "./config/environment"
require "async/websocket/adapters/rack"

load :rack, :supervisor

Async do
  hostname = "localhost"

  rails = Rack::Builder.new do
    map "/cable" do
      run ActionCable.server
    end

    run Rails.application
  end

  rack hostname do
    endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:49195")
    app rails
  end

  supervisor
end
EOF
commit_to_git "Set up Falcon as the new web server with Async support"

# -- CONFIGURE RAILS AS A PROGRESSIVE WEB APP --

bin/rails generate pwa:install
commit_to_git "Configured Rails to run as a Progressive Web App (PWA)"

# -- SET UP VIEWS AND LINK ASSETS CORRECTLY --

mkdir -p app/views/posts app/views/categories app/views/layouts app/views/pages app/views/users

cat <<EOF > app/views/layouts/application.html.erb
<%= tag.doctype %>
<html lang="<%= I18n.locale %>">
  <head>
    <%= tag.meta charset: "UTF-8" %>
    <%= tag.meta name: "viewport", content: "width=device-width, initial-scale=1.0" %>
    <%= csp_meta_tag %>
    <%= csrf_meta_tags %>
    <title><%= t("site.title") %></title>
    <%= stylesheet_link_tag "application", media: "all", "data-turbo-track": "reload" %>
    <%= javascript_include_tag "application", "data-turbo-track": "reload" %>
    <%= tag.script(type: "application/ld+json") { render(partial: "shared/jsonld") } %>
  </head>
  <body>
    <%= render "layouts/header" %>
    <%= yield %>
    <%= render "layouts/footer" %>
    <%= cable_ready_channel_tag %>
    <%= stimulus_include_tag %>
  </body>
</html>
EOF

cat <<EOF > app/views/layouts/_header.html.erb
<%= tag.header do %>
  <%= tag.nav do %>
    <%= image_tag("logo.svg", alt: t("brand.logo_alt")) %>
    <%= link_to t("navigation.home"), root_path %>
    <%= link_to t("posts.new_post"), new_post_path %>
    <%= link_to t("posts.browse"), posts_path %>
    <%= link_to t("categories.browse"), categories_path %>
    <%= link_to t("navigation.search"), search_path %>
    <%= button_to t("navigation.login"), "#", data: { action: "dialog#open" } %>
    <%= button_to t("navigation.dark_mode"), "#", data: { action: "dark-mode#toggle" } %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/layouts/_footer.html.erb
<%= tag.footer do %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.about_brgen") %>
    <%= tag.p t("footer.about_description") %>
  <% end %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.explore") %>
    <%= link_to t("footer.posts"), posts_path %>
    <%= link_to t("footer.categories"), categories_path %>
  <% end %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.legal") %>
    <%= link_to t("footer.privacy_policy"), "#" %>
    <%= link_to t("footer.terms_of_service"), "#" %>
  <% end %>
  <%= tag.section do %>
    <%= tag.h3 t("footer.contact_us") %>
    <%= tag.p t("footer.contact_info") %>
    <%= link_to t("footer.email_us"), "mailto:info@brgen.com" %>
  <% end %>
<% end %>
EOF

# -- SET UP CONTROLLERS AND VIEWS FOR FEATURES --

bin/rails generate controller Posts
bin/rails generate controller Categories
bin/rails generate controller Pages
bin/rails generate controller Users

cat <<EOF > app/controllers/posts_controller.rb
class PostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post, only: [:show, :edit, :update, :destroy]

  def index
    @posts = Post.all
  end

  def show
  end

  def new
    @post = Post.new
  end

  def create
    @post = Post.new(post_params)
    if @post.save
      redirect_to @post, notice: t("posts.create.success")
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @post.update(post_params)
      redirect_to @post, notice: t("posts.update.success")
    else
      render :edit
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_url, notice: t("posts.destroy.success")
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :content, :category_id)
  end
end
EOF

cat <<EOF > app/controllers/categories_controller.rb
class CategoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_category, only: [:show, :edit, :update, :destroy]

  def index
    @categories = Category.all
  end

  def show
  end

  def new
    @category = Category.new
  end

  def create
    @category = Category.new(category_params)
    if @category.save
      redirect_to @category, notice: t("categories.create.success")
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      redirect_to @category, notice: t("categories.update.success")
    else
      render :edit
    end
  end

  def destroy
    @category.destroy
    redirect_to categories_url, notice: t("categories.destroy.success")
  end

  private

  def set_category
    @category = Category.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name, :description)
  end
end
EOF

cat <<EOF > app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def home
  end

  def about
  end

  def contact
  end
end
EOF

cat <<EOF > app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!

  def index
    @users = User.all
  end

  def show
    @user = User.find(params[:id])
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    if @user.update(user_params)
      redirect_to @user, notice: t("users.update.success")
    else
      render :edit
    end
  end

  def destroy
    @user = User.find(params[:id])
    @user.destroy
    redirect_to users_url, notice: t("users.destroy.success")
  end

  private

  def user_params
    params.require(:user).permit(:username, :email, :password, :password_confirmation)
  end
end
EOF

# -- GENERATE MODELS --

bin/rails generate model Post title:string content:text category:references user:references
bin/rails generate model Category name:string description:text

# -- RUN MIGRATIONS --

bin/rails db:migrate

# -- SET UP SCSS --

mkdir -p app/assets/stylesheets/components app/assets/stylesheets/pages

cat <<EOF > app/assets/stylesheets/application.scss
@import "components/header";
@import "components/footer";
@import "pages/home";
EOF

cat <<EOF > app/assets/stylesheets/components/_header.scss
header {
  background: \$primary-color;
  color: white;
  padding: 1rem;
  nav {
    display: flex;
    justify-content: space-between;
    align-items: center;
    a {
      color: white;
      text-decoration: none;
      padding: 0.5rem;
    }
    a:hover {
      text-decoration: underline;
    }
  }
}
EOF

cat <<EOF > app/assets/stylesheets/components/_footer.scss
footer {
  background: \$primary-color;
  color: white;
  padding: 2rem;
  display: flex;
  justify-content: space-between;
  section {
    margin-right: 2rem;
    h3 {
      margin-bottom: 1rem;
    }
    a {
      color: white;
      text-decoration: none;
      display: block;
      margin-bottom: 0.5rem;
    }
    a:hover {
      text-decoration: underline;
    }
  }
}
EOF

cat <<EOF > app/assets/stylesheets/pages/_home.scss
.home-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 2rem;
  .hero {
    text-align: center;
    h1 {
      font-size: 3rem;
      margin-bottom: 1rem;
    }
    p {
      font-size: 1.5rem;
      margin-bottom: 2rem;
    }
  }
}
EOF

# -- SET UP I18N --

mkdir -p config/locales
cat <<EOF > config/locales/en.yml
en:
  site:
    title: "Brgen"
  brand:
    logo_alt: "Brgen Logo"
  navigation:
    home: "Home"
    search: "Search"
    login: "Login"
    dark_mode: "Dark Mode"
  posts:
    new_post: "New Post"
    browse: "Browse Posts"
    create:
      success: "Post was successfully created."
    update:
      success: "Post was successfully updated."
    destroy:
      success: "Post was successfully destroyed."
  categories:
    browse: "Browse Categories"
    create:
      success: "Category was successfully created."
    update:
      success: "Category was successfully updated."
    destroy:
      success: "Category was successfully destroyed."
  footer:
    about_brgen: "About Brgen"
    about_description: "Brgen is an AI-enhanced social network for local communities."
    explore: "Explore"
    posts: "Posts"
    categories: "Categories"
    legal: "Legal"
    privacy_policy: "Privacy Policy"
    terms_of_service: "Terms of Service"
    contact_us: "Contact Us"
    contact_info: "For any inquiries, feel free to reach us at:"
    email_us: "Email Us"
EOF

cat <<EOF > config/locales/no.yml
no:
  site:
    title: "Brgen"
  brand:
    logo_alt: "Brgen Logo"
  navigation:
    home: "Hjem"
    search: "Søk"
    login: "Logg Inn"
    dark_mode: "Mørk Modus"
  posts:
    new_post: "Nytt Innlegg"
    browse: "Bla Gjennom Innlegg"
    create:
      success: "Innlegget ble opprettet."
    update:
      success: "Innlegget ble oppdatert."
    destroy:
      success: "Innlegget ble slettet."
  categories:
    browse: "Bla Gjennom Kategorier"
    create:
      success: "Kategorien ble opprettet."
    update:
      success: "Kategorien ble oppdatert."
    destroy:
      success: "Kategorien ble slettet."
  footer:   
    about_brgen: "Om Brgen"
    about_description: "Brgen er et AI-forbedret sosialt nettverk for lokale samfunn."
    explore: "Utforsk"
    posts: "Innlegg"
    categories: "Kategorier"
    legal: "Juridisk"
    privacy_policy: "Personvernpolicy"
    terms_of_service: "Vilkår for Bruk"
    contact_us: "Kontakt Oss"
    contact_info: "For alle henvendelser, vennligst kontakt oss på:"
    email_us: "Send en epost"
EOF

# -- ADD THREADED MESSAGES FEATURE --

echo "Adding threaded messages feature..."

cat <<EOF > app/controllers/messages_controller.rb
class MessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    @message = current_user.messages.new(message_params)
    if @message.save
      ActionCable.server.broadcast "messages_#{@message.thread_id || @message.id}", { message: render_to_string(partial: 'messages/message', locals: { message: @message }) }
      head :ok
    else
      render :new
    end
  end

  private

  def message_params
    params.require(:message).permit(:content, :thread_id)
  end
end
EOF

cat <<EOF > app/javascript/channels/message_channel.js
import consumer from "./consumer"

consumer.subscriptions.create("MessagesChannel", {
  connected() {
    console.log("Connected to MessagesChannel")
  },

  disconnected() {
    console.log("Disconnected from MessagesChannel")
  },

  received(data) {
    const messageElement = document.getElementById(`message_${data.message.id}`)
    if (messageElement) {
      messageElement.outerHTML = data.html
    } else {
      const messagesElement = document.getElementById("messages")
      messagesElement.insertAdjacentHTML("beforeend", data.html)
    }
  }
})
EOF

# -- ADD UNIFIED NOTIFICATIONS FEATURE --

echo "Adding unified notifications feature..."

cat <<EOF > app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @notifications = current_user.notifications
  end

  def update
    @notification = current_user.notifications.find(params[:id])
    @notification.update(notification_params)
    redirect_to notifications_path
  end

  private

  def notification_params
    params.require(:notification).permit(:read_at)
  end
end
EOF

cat <<EOF > app/javascript/channels/notification_channel.js
import consumer from "./consumer"

consumer.subscriptions.create("NotificationsChannel", {
  connected() {
    console.log("Connected to NotificationsChannel")
  },

  disconnected() {
    console.log("Disconnected from NotificationsChannel")
  },

  received(data) {
    const notificationElement = document.getElementById(`notification_${data.notification.id}`)
    if (notificationElement) {
      notificationElement.outerHTML = data.html
    } else {
      const notificationsElement = document.getElementById("notifications")
      notificationsElement.insertAdjacentHTML("beforeend", data.html)
    }
  }
})
EOF

# -- ADD REACTIONS FEATURE --

echo "Adding reactions feature..."

cat <<EOF > app/controllers/reactions_controller.rb
class ReactionsController < ApplicationController
  before_action :authenticate_user!

  def create
    @reaction = current_user.reactions.new(reaction_params)
    if @reaction.save
      ActionCable.server.broadcast "reactions_#{@reaction.reactable_id}", { reaction: render_to_string(partial: 'reactions/reaction', locals: { reaction: @reaction }) }
      head :ok
    else
      render :new
    end
  end

  private

  def reaction_params
    params.require(:reaction).permit(:reaction_type, :reactable_type, :reactable_id)
  end
end
EOF

cat <<EOF > app/javascript/channels/reaction_channel.js
import consumer from "./consumer"

consumer.subscriptions.create("ReactionsChannel", {
  connected() {
    console.log("Connected to ReactionsChannel")
  },

  disconnected() {
    console.log("Disconnected from ReactionsChannel")
  },

  received(data) {
    const reactionElement = document.getElementById(`reaction_${data.reaction.id}`)
    if (reactionElement) {
      reactionElement.outerHTML = data.html
    } else {
      const reactionsElement = document.getElementById("reactions")
      reactionsElement.insertAdjacentHTML("beforeend", data.html)
    }
  }
})
EOF

# -- FINAL STEPS --

echo "Setup complete. You can now start the Rails server with 'bin/rails server'."
