# frozen_string_literal: true

module Playlist
  # brgen's playlist vertical as a mountable engine. Mirrors Shared::Engine — see
  # brgen/ENGINES.md for the recipe and the two gotchas (require:, top-level mount).
  class Engine < ::Rails::Engine
    isolate_namespace Playlist

    %w[
      app/controllers app/controllers/concerns
      app/models app/models/concerns
      app/helpers app/services app/jobs app/reflexes app/channels
    ].each do |dir|
      path = root.join(dir)
      config.autoload_paths << path.to_s if path.exist?
    end

    config.paths["db/migrate"] << root.join("db/migrate").to_s

    initializer "playlist.view_paths" do
      ActiveSupport.on_load(:action_controller_base) do
        append_view_path Playlist::Engine.root.join("app/views")
      end
    end

    initializer "playlist.assets" do |app|
      %w[app/assets/stylesheets app/javascript].each do |dir|
        p = Playlist::Engine.root.join(dir).to_s
        app.config.assets.paths << p if Dir.exist?(p) && !app.config.assets.paths.include?(p)
      end
    end
  end
end
