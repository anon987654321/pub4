
#!/usr/bin/env zsh

cd "$(dirname "$0")"

# Add dependencies
yarn add video.js @hotwired/turbo-rails stimulus

# Generate models, controllers, and views for live streaming
bin/rails generate model Stream title:string description:text user:references
bin/rails generate controller Streams index show new create destroy
echo "resources :streams, only: [:index, :show, :new, :create, :destroy]" >> config/routes.rb

# Update Stream model
cat <<EOF > app/models/stream.rb
class Stream < ApplicationRecord
  belongs_to :user
  validates :title, presence: true
end
EOF

# Update StreamsController
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
      redirect_to @stream, notice: t("stream_created")
    else
      render :new
    end
  end

  def destroy
    @stream.destroy
    redirect_to streams_path, notice: t("stream_deleted")
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

# Create views for streams
mkdir -p app/views/streams
cat <<EOF > app/views/streams/index.html.erb
<%= tag.h1 t("streams") %>
<%= tag.ul do %>
  <% @streams.each do |stream| %>
    <%= tag.li do %>
      <%= link_to stream.title, stream %>
      <%= tag.p stream.description %>
    <% end %>
  <% end %>
<% end %>
<%= link_to t("new_stream"), new_stream_path %>
EOF

cat <<EOF > app/views/streams/show.html.erb
<%= tag.h1 @stream.title %>
<%= tag.p @stream.description %>
<%= link_to t("back"), streams_path %>
EOF

cat <<EOF > app/views/streams/_form.html.erb
<%= form_with(model: @stream, local: true) do |form| %>
  <%= form.label :title %>
  <%= form.text_field :title %>
  <%= form.label :description %>
  <%= form.text_area :description %>
  <%= form.submit %>
<% end %>
EOF

cat <<EOF > app/views/streams/new.html.erb
<%= tag.h1 t("new_stream") %>
<%= render "form", stream: @stream %>
<%= link_to t("back"), streams_path %>
EOF

bin/rails db:migrate
commit_to_git "Set up live streaming functionality"
