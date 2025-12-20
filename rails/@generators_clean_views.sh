#!/usr/bin/env zsh
set -euo pipefail

# Clean Rails 8 views with tag helpers - no div soup
# Pixel-perfect CSS preservation, ultraminimalistic markup

generate_clean_application_layout() {
  local app_name="${1:-App}"
  
  log "Generating clean application layout"
  
  cat <<'LAYOUT' > app/views/layouts/application.html.erb
<!DOCTYPE html>
<html lang="<%= I18n.locale %>">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <%= tag.title content_for?(:title) ? "#{yield(:title)} - #{t('app.name')}" : t('app.name') %>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
<body>
  <%= yield :header %>
  
  <% if current_user %>
    <%= tag.nav do %>
      <%= link_to t('nav.home'), root_path %>
      <%= link_to t('nav.profile'), user_path(current_user) if respond_to?(:user_path) %>
      <%= button_to t('nav.sign_out'), destroy_user_session_path, method: :delete %>
    <% end %>
  <% end %>
  
  <% flash.each do |type, msg| %>
    <%= tag.output msg, class: "alert alert-#{type}", data: { controller: "reveal", reveal_hidden_class: "hidden" } %>
  <% end %>
  
  <main>
    <%= yield %>
  </main>
  
  <%= yield :footer %>
</body>
</html>
LAYOUT
  
  log "✓ Clean application layout generated"
}

generate_scaffold_views() {
  local resource="${1}"
  local attributes="${2:-}" # e.g. "title:string content:text"
  
  log "Generating clean scaffold views for $resource"
  
  mkdir -p "app/views/${resource}"
  
  # Index view - ultraminimalistic table
  cat <<VIEW > "app/views/${resource}/index.html.erb"
<% content_for :title, t(".title") %>

<%= tag.header do %>
  <%= tag.h1 t(".heading") %>
  <%= link_to t(".new"), new_${resource}_path, class: "btn btn-primary" %>
<% end %>

<%= turbo_frame_tag "${resource}_list" do %>
  <% if @${resource}.any? %>
    <%= tag.table do %>
      <%= tag.thead do %>
        <%= tag.tr do %>
$(for attr in ${(s: :)attributes}; do
  field="${attr%%:*}"
  print "          <%= tag.th t('.${field}') %>"
done)
          <%= tag.th t('.actions') %>
        <% end %>
      <% end %>
      
      <%= tag.tbody do %>
        <% @${resource}.each do |item| %>
          <%= tag.tr id: dom_id(item) do %>
$(for attr in ${(s: :)attributes}; do
  field="${attr%%:*}"
  print "            <%= tag.td item.${field} %>"
done)
            <%= tag.td do %>
              <%= link_to t('show'), item %>
              <%= link_to t('edit'), edit_${resource}_path(item) %>
              <%= button_to t('destroy'), item, method: :delete, form: { data: { turbo_confirm: t('confirm') } } %>
            <% end %>
          <% end %>
        <% end %>
      <% end %>
    <% end %>
  <% else %>
    <%= tag.p t('.empty'), class: "empty-state" %>
  <% end %>
<% end %>
VIEW

  # Show view - clean dl/dt/dd
  cat <<VIEW > "app/views/${resource}/show.html.erb"
<% content_for :title, @${resource}.to_s %>

<%= tag.header do %>
  <%= tag.h1 @${resource}.to_s %>
  <%= link_to t('edit'), edit_${resource}_path(@${resource}), class: "btn btn-secondary" %>
  <%= button_to t('destroy'), @${resource}, method: :delete, form: { data: { turbo_confirm: t('confirm') } }, class: "btn btn-danger" %>
<% end %>

<%= tag.dl do %>
$(for attr in ${(s: :)attributes}; do
  field="${attr%%:*}"
  cat <<ATTR
  <%= tag.dt t('.${field}') %>
  <%= tag.dd @${resource}.${field} %>
ATTR
done)
<% end %>

<%= link_to t('back'), ${resource}_path %>
VIEW

  # Form partial - fieldset/legend, no divs
  cat <<VIEW > "app/views/${resource}/_form.html.erb"
<%= form_with model: ${resource}, data: { controller: "form-validation" } do |f| %>
  <% if ${resource}.errors.any? %>
    <%= tag.output class: "alert alert-danger", role: "alert" do %>
      <%= tag.h2 t('errors.template.header', count: ${resource}.errors.count, model: ${resource}.model_name.human) %>
      <%= tag.ul do %>
        <% ${resource}.errors.full_messages.each do |msg| %>
          <%= tag.li msg %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
  
  <%= tag.fieldset do %>
$(for attr in ${(s: :)attributes}; do
  field="${attr%%:*}"
  type="${attr##*:}"
  
  case "$type" in
    text)
      cat <<FIELD
    <%= tag.label f.object_name, :${field}, t('.${field}') %>
    <%= f.text_area :${field}, rows: 10 %>
FIELD
      ;;
    boolean)
      cat <<FIELD
    <%= f.label :${field} do %>
      <%= f.check_box :${field} %>
      <%= t('.${field}') %>
    <% end %>
FIELD
      ;;
    *)
      cat <<FIELD
    <%= tag.label f.object_name, :${field}, t('.${field}') %>
    <%= f.text_field :${field} %>
FIELD
      ;;
  esac
done)
    
    <%= f.submit t('save'), class: "btn btn-primary" %>
  <% end %>
<% end %>
VIEW

  # New view
  cat <<VIEW > "app/views/${resource}/new.html.erb"
<% content_for :title, t('.title') %>

<%= tag.h1 t('.heading') %>

<%= render "form", ${resource}: @${resource} %>

<%= link_to t('back'), ${resource}_path %>
VIEW

  # Edit view
  cat <<VIEW > "app/views/${resource}/edit.html.erb"
<% content_for :title, t('.title', name: @${resource}.to_s) %>

<%= tag.h1 t('.heading', name: @${resource}.to_s) %>

<%= render "form", ${resource}: @${resource} %>

<%= link_to t('show'), @${resource} %> |
<%= link_to t('back'), ${resource}_path %>
VIEW

  log "✓ Clean scaffold views generated for $resource"
}

# Turbo Stream partials - minimal, semantic
generate_turbo_partials() {
  local resource="${1}"
  
  mkdir -p "app/views/${resource}"
  
  # Item partial - for broadcasts
  cat <<VIEW > "app/views/${resource}/_${resource}.html.erb"
<%= turbo_frame_tag dom_id(${resource}) do %>
  <%= tag.article id: dom_id(${resource}) do %>
    <%= tag.h2 do %>
      <%= link_to ${resource}.to_s, ${resource} %>
    <% end %>
    
    <%= tag.p ${resource}.description if ${resource}.respond_to?(:description) %>
    
    <%= tag.footer do %>
      <%= tag.time ${resource}.created_at, datetime: ${resource}.created_at.iso8601 %>
    <% end %>
  <% end %>
<% end %>
VIEW

  # Create turbo stream
  cat <<VIEW > "app/views/${resource}/create.turbo_stream.erb"
<%= turbo_stream.prepend "${resource}_list" do %>
  <%= render @${resource} %>
<% end %>

<%= turbo_stream.replace "new_${resource}_form" do %>
  <%= render "form", ${resource}: @${resource.singularize}.class.new %>
<% end %>
VIEW

  # Update turbo stream
  cat <<VIEW > "app/views/${resource}/update.turbo_stream.erb"
<%= turbo_stream.replace dom_id(@${resource}) do %>
  <%= render @${resource} %>
<% end %>
VIEW

  # Destroy turbo stream
  cat <<VIEW > "app/views/${resource}/destroy.turbo_stream.erb"
<%= turbo_stream.remove dom_id(@${resource}) %>
VIEW

  log "✓ Turbo Stream partials generated"
}

# Authentication views - clean, no divs
generate_auth_views() {
  log "Generating clean authentication views"
  
  mkdir -p app/views/{sessions,passwords,registrations}
  
  # Sign in
  cat <<'VIEW' > app/views/sessions/new.html.erb
<% content_for :title, t('.title') %>

<%= tag.h1 t('.heading') %>

<%= form_with url: session_path, data: { turbo: false } do |f| %>
  <%= tag.fieldset do %>
    <%= tag.legend t('.credentials') %>
    
    <%= tag.label :email, t('.email') %>
    <%= f.email_field :email, autofocus: true, autocomplete: "email" %>
    
    <%= tag.label :password, t('.password') %>
    <%= f.password_field :password, autocomplete: "current-password" %>
    
    <%= f.label :remember_me do %>
      <%= f.check_box :remember_me %>
      <%= t('.remember_me') %>
    <% end %>
    
    <%= f.submit t('.sign_in'), class: "btn btn-primary" %>
  <% end %>
<% end %>

<%= tag.nav class: "auth-links" do %>
  <%= link_to t('.forgot_password'), new_password_path %>
  <%= link_to t('.sign_up'), new_registration_path %>
<% end %>
VIEW

  # Password reset request
  cat <<'VIEW' > app/views/passwords/new.html.erb
<% content_for :title, t('.title') %>

<%= tag.h1 t('.heading') %>

<%= tag.p t('.instructions') %>

<%= form_with url: passwords_path do |f| %>
  <%= tag.fieldset do %>
    <%= tag.label :email, t('.email') %>
    <%= f.email_field :email, autofocus: true, autocomplete: "email" %>
    
    <%= f.submit t('.send_instructions'), class: "btn btn-primary" %>
  <% end %>
<% end %>

<%= link_to t('back'), new_session_path %>
VIEW

  log "✓ Clean auth views generated"
}

# Error pages - semantic HTML
generate_error_pages() {
  log "Generating semantic error pages"
  
  mkdir -p public
  
  # 404
  cat <<'HTML' > public/404.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Page Not Found (404)</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 50rem; margin: 4rem auto; padding: 0 1rem; }
    h1 { font-size: 2rem; margin-bottom: 1rem; }
  </style>
</head>
<body>
  <h1>Page Not Found</h1>
  <p>The page you requested does not exist.</p>
  <p><a href="/">Return home</a></p>
</body>
</html>
HTML

  # 500
  cat <<'HTML' > public/500.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Server Error (500)</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 50rem; margin: 4rem auto; padding: 0 1rem; }
    h1 { font-size: 2rem; margin-bottom: 1rem; }
  </style>
</head>
<body>
  <h1>Server Error</h1>
  <p>Something went wrong on our end. We've been notified and will fix it soon.</p>
  <p><a href="/">Return home</a></p>
</body>
</html>
HTML

  log "✓ Error pages generated"
}
