# frozen_string_literal: true

require "active_support/core_ext/module/introspection"
require "active_support/core_ext/string/inflections"

module Shared
  # The boot shape every brgen vertical engine shares: autoload paths, its own
  # db/migrate, its views, its stylesheets and javascript. brgen/ENGINES.md calls
  # this the recipe and says to mirror Shared::Engine exactly; six engines
  # mirrored it by hand and the bodies were byte-identical but for the module
  # name, so the recipe lives here and each engine includes it.
  #
  # Everything is derived from the including class: `root` is the engine's own
  # root (Rails::Engine computes it from the file that opened the class, which is
  # still the engine's own lib/<name>/engine.rb), and the initializer prefix is
  # its namespace — Dating::Engine gives "dating.view_paths", the name it had.
  module VerticalEngine
    # A vertical does not carry app/views here: views come in through the
    # view_paths initializer below, not through autoloading.
    AUTOLOAD_DIRS = %w[
      app/controllers app/controllers/concerns
      app/models app/models/concerns
      app/helpers app/services app/jobs app/reflexes app/channels
    ].freeze

    ASSET_DIRS = %w[app/assets/stylesheets app/javascript].freeze

    def self.included(engine)
      super
      root = engine.root
      prefix = engine.module_parent.name.underscore

      # << not += : Rails 8.1 freezes these arrays during engine boot and +=
      # rebinds to a new frozen array that later engines then fail to append to.
      AUTOLOAD_DIRS.each do |dir|
        path = root.join(dir)
        engine.config.autoload_paths << path.to_s if path.exist?
      end

      # Unlike Shared::Engine, a vertical owns its future migrations — see the
      # "one migration per app" note there for why shared has no such line.
      engine.config.paths["db/migrate"] << root.join("db/migrate").to_s

      engine.initializer "#{prefix}.view_paths" do
        ActiveSupport.on_load(:action_controller_base) do
          append_view_path root.join("app/views")
        end
      end

      engine.initializer "#{prefix}.assets" do |app|
        ASSET_DIRS.each do |dir|
          path = root.join(dir).to_s
          app.config.assets.paths << path if Dir.exist?(path) && !app.config.assets.paths.include?(path)
        end
      end
    end
  end
end
