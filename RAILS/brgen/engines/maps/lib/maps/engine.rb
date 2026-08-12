# frozen_string_literal: true

module Maps
  # Maps surface as a mountable engine. Place stays a host model — restaurant
  # and store now point at it, so it has two consumers and is shared the same
  # way User is. This engine owns routes, controllers and views only.
  # See brgen/ENGINES.md (messenger-shaped extract).
  class Engine < ::Rails::Engine
    isolate_namespace Maps

    %w[
      app/controllers app/controllers/concerns
      app/models app/models/concerns
      app/helpers app/services app/jobs app/reflexes app/channels
    ].each do |dir|
      path = root.join(dir)
      config.autoload_paths << path.to_s if path.exist?
    end

    config.paths["db/migrate"] << root.join("db/migrate").to_s

    initializer "maps.view_paths" do
      ActiveSupport.on_load(:action_controller_base) do
        append_view_path Maps::Engine.root.join("app/views")
      end
    end

    initializer "maps.assets" do |app|
      %w[app/assets/stylesheets app/javascript].each do |dir|
        p = Maps::Engine.root.join(dir).to_s
        app.config.assets.paths << p if Dir.exist?(p) && !app.config.assets.paths.include?(p)
      end
    end
  end
end
