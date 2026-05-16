#!/usr/bin/env zsh
# @views.sh — sourced via @shared_functions.sh
set -euo pipefail


# Shared partials
write_shared_partials() {
  mkdir -p app/views/shared
  cat > app/views/shared/_flash.html.erb << 'ERB'
<% flash.each do |type, msg| %>
  <div class="flash flash--<%= type %>"><%= msg %></div>
<% end %>
ERB

  cat > app/views/shared/_errors.html.erb << 'ERB'
<% if object.errors.any? %>
  <div class="errors">
    <% object.errors.full_messages.each do |msg| %>
      <p class="error-msg"><%= msg %></p>
    <% end %>
  </div>
<% end %>
ERB

  cat > app/views/shared/_pagination.html.erb << 'ERB'
<%= pagy.series_nav if pagy.pages > 1 %>
ERB
  log_ok "Shared partials written"
}

# Auth views
write_auth_views() {
  mkdir -p app/views/sessions app/views/passwords
  cat > app/views/sessions/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Sign in</h1>
  <%= form_with url: session_path do |f| %>
    <%= render "shared/errors", object: f.object if f.object.respond_to?(:errors) %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="field">
      <%= f.label :password %>
      <%= f.password_field :password, autocomplete: "current-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Sign in", class: "btn btn--primary" %>
    </div>
    <p><%= link_to "Forgot password?", new_password_path %></p>
  <% end %>
</div>
ERB

  cat > app/views/passwords/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Reset password</h1>
  <%= form_with url: passwords_path do |f| %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="actions">
      <%= f.submit "Send reset link", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB

  cat > app/views/passwords/edit.html.erb << 'ERB'
<div class="auth-form">
  <h1>New password</h1>
  <%= form_with model: @user, url: password_path(params[:token]), method: :put do |f| %>
    <div class="field">
      <%= f.label :password, "New password" %>
      <%= f.password_field :password, autocomplete: "new-password" %>
    </div>
    <div class="field">
      <%= f.label :password_confirmation, "Confirm password" %>
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Set password", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB
  log_ok "Auth views written"
}

# Registration (sign-up)
write_registration() {
  mkdir -p app/views/registrations
  cat > app/controllers/registrations_controller.rb << 'RUBY'
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new = render

  def create
    user = User.new(registration_params)
    if user.save
      start_new_session_for user
      redirect_to root_path, notice: "Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
RUBY
  cat > app/views/registrations/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Create account</h1>
  <%= form_with model: User.new, url: registration_path do |f| %>
    <%= render "shared/errors", object: f.object %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="field">
      <%= f.label :password %>
      <%= f.password_field :password, autocomplete: "new-password" %>
    </div>
    <div class="field">
      <%= f.label :password_confirmation, "Confirm password" %>
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Create account", class: "btn btn--primary" %>
    </div>
    <p><%= link_to "Sign in instead", new_session_path %></p>
  <% end %>
</div>
ERB
  log_ok "Registration written"
}

# Enhanced layout
write_full_layout() {
  local app_title=${1:-App}
  local nav_links=${2:-}
  mkdir -p app/views/layouts
  cat > app/views/layouts/application.html.erb << LAYOUT
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="turbo-cache-control" content="no-preview">
  <title><%= content_for?(:title) ? yield(:title) + " – ${app_title}" : "${app_title}" %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
<body>
<nav>
  <%= link_to "${app_title}", root_path, class: "brand" %>
  ${nav_links}
  <% if authenticated? %>
    <%= link_to "Sign out", session_path, data: { turbo_method: :delete } %>
  <% else %>
    <%= link_to "Sign in", new_session_path %>
  <% end %>
</nav>
<%= render "shared/flash" %>
<main><%= yield %></main>
</body>
</html>
LAYOUT
  log_ok "Full layout written"
}
