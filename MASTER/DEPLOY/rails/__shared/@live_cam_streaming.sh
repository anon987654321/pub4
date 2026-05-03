#!/bin/zsh

# Add dependencies
yarn add video.js

# Generate models, controllers, and views for live streaming
bin/rails generate model Stream title:string description:text user:references
bin/rails generate controller Streams index show new create destroy

# Add routes for streams (append to routes.rb)
  echo "resources :streams, only: [:index, :show, :new, :create, :destroy]" >> config/routes.rb

# Create the Streams controller
cat <<EOF > app/controllers/streams_controller.rb
class StreamsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_stream, only: [:show, :destroy]

  def index
    @streams = Stream.all
  end

  def show
  end

  def new
    @stream = current_user.streams.build
  end

  def create
    @stream = current_user.streams.build(stream_params)
    if @stream.save
      redirect_to @stream, notice: "Stream created successfully"
    else
      render :new
    end
  end

  def destroy
    @stream.destroy
    redirect_to streams_path, notice: "Stream deleted successfully"
  end

  private

  def set_stream
    @stream = Stream.find(params[:id])
  end

  def stream_params
    params.require(:stream).permit(:title, :description)
  end
end
EOF

# Create the Stream model
cat <<EOF > app/models/stream.rb
class Stream < ApplicationRecord
  belongs_to :user
  validates :title, presence: true
end
EOF

# Create views for streams
mkdir -p app/views/streams
cat <<EOF > app/views/streams/index.html.erb
<%= tag.h1 "Streams" %>
<%= tag.ul do %>
  <% @streams.each do |stream| %>
    <%= tag.li do %>
      <%= link_to stream.title, stream %>
      <p><%= stream.description %></p>
    <% end %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/streams/show.html.erb
<%= tag.h1 @stream.title %>
<p><%= @stream.description %></p>
<div id="live-stream" data-controller="stream" data-stream-id="<%= @stream.id %>">
  <video id="live-stream-video" controls autoplay></video>
</div>
<%= link_to "Back", streams_path %>
EOF

cat <<EOF > app/views/streams/_form.html.erb
<%= form_with(model: @stream, local: true) do |form| %>
  <div class="field">
    <%= form.label :title %>
    <%= form.text_field :title %>
  </div>
  <div class="field">
    <%= form.label :description %>
    <%= form.text_area :description %>
  </div>
  <div class="actions">
    <%= form.submit %>
  </div>
<% end %>
EOF

cat <<EOF > app/views/streams/new.html.erb
<%= tag.h1 "New Stream" %>
<%= render "form", stream: @stream %>
<%= link_to "Back", streams_path %>
EOF

cat <<EOF > app/views/streams/edit.html.erb
<%= tag.h1 "Edit Stream" %>
<%= render "form", stream: @stream %>
<%= link_to "Back", streams_path %>
EOF

# Create Stimulus controller for live streaming
mkdir -p app/javascript/controllers
cat <<EOF > app/javascript/controllers/stream_controller.js
import { Controller } from "stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["video"]

  connect() {
    this.channel = createConsumer().subscriptions.create(
      { channel: "StreamChannel", stream_id: this.data.get("id") },
      {
        received: data => this.#received(data)
      }
    )
  }

  #received(data) {
    if (data.action === "play") {
      this.videoTarget.src = data.url
    }
  }
}
EOF

# Create StreamChannel
cat <<EOF > app/channels/stream_channel.rb
class StreamChannel < ApplicationCable::Channel
  def subscribed
    stream_from "stream_\#{params[:stream_id]}"
  end
end
EOF

# Create broadcast job
cat <<EOF > app/jobs/stream_broadcast_job.rb
class StreamBroadcastJob < ApplicationJob
  queue_as :default

  def perform(stream, url)
    ActionCable.server.broadcast "stream_\#{stream.id}", action: "play", url: url
  end
end
EOF

# Run migrations
bin/rails db:migrate

commit_to_git "Set up live cam streaming for $APP"
