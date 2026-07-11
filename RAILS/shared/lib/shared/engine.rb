# frozen_string_literal: true
module Shared
  class Engine < ::Rails::Engine
    isolate_namespace Shared
    # Use << not += — Rails 8.1 freezes path arrays during engine boot; += breaks later engines.
    %w[app/models app/models/concerns app/services app/controllers app/controllers/concerns app/policies app/helpers app/jobs app/reflexes].each do |dir|
      config.autoload_paths << root.join(dir).to_s
    end
    config.paths["db/migrate"] << root.join("db/migrate").to_s
    config.active_record.schema_format = :ruby if config.respond_to?(:active_record)

    initializer "shared.view_paths" do
      ActiveSupport.on_load(:action_controller_base) do
        append_view_path Shared::Engine.root.join("app/views")
      end
    end

    initializer "shared.search_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        require_dependency Shared::Engine.root.join("app/helpers/shared/search_helper").to_s
        helper Shared::SearchHelper
      end
    end

    initializer "shared.seo_kit" do
      ActiveSupport.on_load(:action_controller_base) do
        require_dependency Shared::Engine.root.join("app/helpers/shared/seo_kit").to_s
        helper Shared::SeoKit
      end
    end

    initializer "shared.schema_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        require_dependency Shared::Engine.root.join("app/helpers/schema_helper").to_s
        helper SchemaHelper
      end
    end

    initializer "shared.master_embed_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        require_dependency Shared::Engine.root.join("app/helpers/shared/master_embed_helper").to_s
        helper Shared::MasterEmbedHelper
      end
    end

    initializer "shared.stylesheets" do |app|
      path = root.join("app/assets/stylesheets").to_s
      app.config.assets.paths << path unless app.config.assets.paths.include?(path)
    end

    initializer "shared.frontend_assets" do |app|
      path = root.join("frontend").to_s
      app.config.assets.paths << path unless app.config.assets.paths.include?(path)
    end

    # importmap_baseline.rb pins @stimulus-components/* by bare filename
    # (e.g. "@stimulus-components--dialog.js"); without this path registered,
    # the asset pipeline can't resolve it and the pin falls through to a raw
    # to_s of the engine root, which importmap serializes as a literal
    # filesystem path (e.g. "/home/brgen/shared/vendor/javascript/...") that
    # the browser then 404s on verbatim.
    initializer "shared.vendor_javascript" do |app|
      path = root.join("vendor/javascript").to_s
      app.config.assets.paths << path unless app.config.assets.paths.include?(path)
    end

    initializer "shared.public_static" do |app|
      public_path = root.join("public").to_s
      next unless File.directory?(public_path)

      app.middleware.insert_before(
        ActionDispatch::Static,
        ActionDispatch::Static,
        public_path,
        index: nil,
        headers: app.config.public_file_server.headers
      )
    end

  end
end
