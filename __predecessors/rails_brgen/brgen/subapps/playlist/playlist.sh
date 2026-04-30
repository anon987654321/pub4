echo "Setting up Playlist subapp..."
# Generate models for Playlist subapp
bin/rails generate model Playlist::Set name:string description:text user:references
bin/rails generate model Playlist::Track name:string artist:string audio_url:string set:references
bin/rails db:migrate

# Creating Playlist controllers and views
mkdir -p app/controllers/playlist
cat <<RUBY > app/controllers/playlist/sets_controller.rb
module Playlist
  class SetsController < ApplicationController
    before_action :set_set, only: [:show, :edit, :update, :destroy]

    def index
      @sets = Set.includes(:tracks).all
    end

    def show
    end

    def new
      @set = Set.new
    end

    def create
      @set = Set.new(set_params)
      if @set.save
        redirect_to playlist_set_path(@set), notice: "Set was successfully created."
      else
        render :new
      end
    end

    def update
      if @set.update(set_params)
        redirect_to playlist_set_path(@set), notice: "Set was successfully updated."
      else
        render :edit
      end
    end

    def destroy
      @set.destroy
      redirect_to playlist_sets_path, notice: "Set was successfully destroyed."
    end

    private

    def set_set
      @set = Set.find(params[:id])
    end

    def set_params
      params.require(:set).permit(:name, :description, :user_id)
    end
  end
end
RUBY

mkdir -p app/views/playlist/sets
cat <<ERB > app/views/playlist/sets/index.html.erb
<%= tag.div do %>
  <% @sets.each do |set| %>
    <%= tag.div itemscope itemtype="http://schema.org/MusicPlaylist" do %>
      <%= link_to set.name, playlist_set_path(set), itemprop: "name" %>
      <%= tag.p set.description, itemprop: "description" %>
    <% end %>
  <% end %>
<% end %>
ERB

git add .
git commit -m "Setup Playlist subapp with models, controllers, and views including schema.org microdata"
