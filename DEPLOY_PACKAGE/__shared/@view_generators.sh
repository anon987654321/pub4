#!/usr/bin/env zsh
set -euo pipefail

# View generators - CRUD views with Turbo frames
# Pure zsh string replacement per master.json:stack:zsh_replacements

generate_show_view() {
    local model_singular="$1"

    local model_plural="$2"

    log "Generating show view for $model_singular"

    mkdir -p "app/views/${model_plural}"
    cat > "app/views/${model_plural}/show.html.erb" << 'SHOWEOF'
<%= turbo_frame_tag dom_id(@<%%= model_singular %>) do %>

  <%= tag.article class: "detail-view", role: "article" do %>

    <%= tag.header do %>

      <%= tag.h1 @<%%= model_singular %>.title %>

      <%= tag.div class: "meta" do %>

        <%= tag.span t("brgen.posted_by", user: @<%%= model_singular %>.user.email) %>

        <%= tag.span @<%%= model_singular %>.created_at.strftime("%Y-%m-%d %H:%M") %>

      <% end %>

    <% end %>

    <%= tag.section class: "content" do %>
      <% if @<%%= model_singular %>.photos.attached? %>

        <%= tag.div class: "photos" do %>

          <% @<%%= model_singular %>.photos.each do |photo| %>

            <%= image_tag photo, alt: t("brgen.listing_photo", title: @<%%= model_singular %>.title) %>

          <% end %>

        <% end %>

      <% end %>

      <%= tag.div class: "description" do %>
        <%= simple_format @<%%= model_singular %>.description %>

      <% end %>

      <%= tag.dl class: "attributes" do %>
        <%= tag.dt t("brgen.price") %>

        <%= tag.dd number_to_currency(@<%%= model_singular %>.price) %>

        <%= tag.dt t("brgen.category") %>

        <%= tag.dd @<%%= model_singular %>.category %>

        <%= tag.dt t("brgen.location") %>

        <%= tag.dd @<%%= model_singular %>.location %>

        <%= tag.dt t("brgen.status") %>

        <%= tag.dd @<%%= model_singular %>.status %>

      <% end %>

    <% end %>

    <% if @<%%= model_singular %>.lat.present? && @<%%= model_singular %>.lng.present? %>
      <%= tag.div id: "map",

                  data: {

                    controller: "mapbox",

                    mapbox_api_key_value: ENV['MAPBOX_TOKEN'],

                    mapbox_<%%= model_plural %>_value: [@<%%= model_singular %>].to_json

                  },

                  style: "height: 400px; margin: 2rem 0;" %>

    <% end %>

    <%= render partial: "shared/vote", locals: { votable: @<%%= model_singular %> } %>
    <%= tag.footer class: "actions" do %>
      <%= link_to t("brgen.back"), <%%= model_plural %>_path, class: "button secondary" %>

      <% if @<%%= model_singular %>.user == current_user || current_user&.admin? %>

        <%= link_to t("brgen.edit"), edit_<%%= model_singular %>_path(@<%%= model_singular %>), class: "button" %>

        <%= button_to t("brgen.delete"), <%%= model_singular %>_path(@<%%= model_singular %>),

                      method: :delete,

                      class: "button danger",

                      data: { turbo_confirm: t("brgen.confirm_delete") } %>

      <% end %>

    <% end %>

  <% end %>

<% end %>

SHOWEOF

    local template=$(<"app/views/${model_plural}/show.html.erb")
    template="${template//<%%= model_singular %>/${model_singular}}"

    template="${template//<%%= model_plural %>/${model_plural}}"

    print -r -- "$template" > "app/views/${model_plural}/show.html.erb"

}

generate_new_view() {
    local model_singular="$1"

    local model_plural="$2"

    log "Generating new view for $model_singular"

    mkdir -p "app/views/${model_plural}"
    cat > "app/views/${model_plural}/new.html.erb" << 'NEWEOF'
<%= turbo_frame_tag "new_<%%= model_singular %>" do %>

  <%= tag.article class: "form-container" do %>

    <%= tag.header do %>

      <%= tag.h1 t("brgen.new_<%%= model_singular %>") %>

    <% end %>

    <%= render "form", <%%= model_singular %>: @<%%= model_singular %> %>
    <%= tag.footer do %>
      <%= link_to t("brgen.cancel"), <%%= model_plural %>_path, class: "button secondary" %>

    <% end %>

  <% end %>

<% end %>

NEWEOF

    local template=$(<"app/views/${model_plural}/new.html.erb")
    template="${template//<%%= model_singular %>/${model_singular}}"

    template="${template//<%%= model_plural %>/${model_plural}}"

    print -r -- "$template" > "app/views/${model_plural}/new.html.erb"

}

generate_edit_view() {
    local model_singular="$1"

    local model_plural="$2"

    log "Generating edit view for $model_singular"

    mkdir -p "app/views/${model_plural}"
    cat > "app/views/${model_plural}/edit.html.erb" << 'EDITEOF'
<%= turbo_frame_tag dom_id(@<%%= model_singular %>) do %>

  <%= tag.article class: "form-container" do %>

    <%= tag.header do %>

      <%= tag.h1 t("brgen.edit_<%%= model_singular %>") %>

    <% end %>

    <%= render "form", <%%= model_singular %>: @<%%= model_singular %> %>
    <%= tag.footer do %>
      <%= link_to t("brgen.cancel"), <%%= model_singular %>_path(@<%%= model_singular %>), class: "button secondary" %>

    <% end %>

  <% end %>

<% end %>

EDITEOF

    local template=$(<"app/views/${model_plural}/edit.html.erb")
    template="${template//<%%= model_singular %>/${model_singular}}"

    template="${template//<%%= model_plural %>/${model_plural}}"

    print -r -- "$template" > "app/views/${model_plural}/edit.html.erb"

}

generate_crud_views() {
    local model_singular="$1"

    local model_plural="$2"

    log "Generating all CRUD views for ${model_plural}"

    generate_show_view "$model_singular" "$model_plural"
    generate_new_view "$model_singular" "$model_plural"

    generate_edit_view "$model_singular" "$model_plural"

    log "CRUD views generated: show, new, edit"

}

generate_turbo_views() {
    local model_name="$1"

    local singular_name="$2"

    log "Generating Turbo views for $model_name"

    mkdir -p "app/views/$model_name"
    if [ ! -f "app/views/$model_name/index.html.erb" ]; then
        cat > "app/views/$model_name/index.html.erb" << EOF

<%= turbo_frame_tag "$model_name" do %>

  <div data-controller="infinite-scroll">

    <% @${model_name}.each do |${singular_name}| %>

      <%= render ${singular_name} %>

    <% end %>

  </div>

<% end %>

EOF

    fi

}

