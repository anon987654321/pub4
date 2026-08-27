# frozen_string_literal: true

module Shared
  class Engine < ::Rails::Engine
    isolate_namespace Shared
    # Use << not += — Rails 8.1 freezes path arrays during engine boot; += breaks later engines.
    %w[app/models app/models/concerns app/services app/controllers app/controllers/concerns app/policies app/helpers
app/jobs app/reflexes].each do |dir|
      config.autoload_paths << root.join(dir).to_s
    end
    # NO db/migrate path. Deliberate, and the deletion of a line that looked like
    # wiring and was not.
    #
    # `config.paths["db/migrate"] << root.join("db/migrate")` sat here and no app
    # read it: `bin/rails db:migrate:status` in all three lists only that app's own
    # migrations, and the three files under shared/db/migrate had per-app
    # equivalents doing the real work (amber's enable_anonymous_posts creates the
    # same anonymous_post_quotas table). On 2026-08-11 a migration was added to
    # shared/db/migrate for the outbound_clicks table, ran nowhere, and the beacon
    # that writes to it would have failed silently behind a rescue — inert config
    # inside the framework wiring, which is this repo's own favourite defect class.
    #
    # The convention is one migration per app. `shared/db/migrate` is kept as the
    # historical record of the three that predate it and is asserted empty of new
    # files by RAILS/test/engine_migration_convention_test.rb, because a file added
    # there would silently do nothing.
    config.active_record.schema_format = :ruby if config.respond_to?(:active_record)

    %w[app/channels].each { |dir| config.autoload_paths << root.join(dir).to_s }

    initializer "shared.i18n" do |app|
      # Every locale file the engine carries, not one named set. This listed
      # social.<locale>.yml literally, so affiliate.en.yml — added when the
      # affiliate stack moved here so amber could render the same in-feed unit —
      # was on disk and never loaded, and the unit would have rendered
      # translation-missing spans in the app it was moved for.
      Dir[root.join("config/locales/*.{en,nb}.yml").to_s].sort.each do |path|
        app.config.i18n.load_path << path
      end
    end

    initializer "shared.view_paths" do
      ActiveSupport.on_load(:action_controller_base) do
        append_view_path Shared::Engine.root.join("app/views")
      end
      # ActionMailer keeps its own view-path stack, so the controller hook above
      # does not reach it. Without this, a host mailer can only render templates
      # it carries itself — which is why every app had its own copy of
      # passwords_mailer/reset.* and of layouts/mailer.*, and why amber and
      # bsdports were quietly rendering Rails' generated stub layout instead of
      # the engine's designed one.
      ActiveSupport.on_load(:action_mailer) do
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

    # shared/_ad_slot gates on advertising_consent?, and it is an engine partial —
    # available to all three apps. The helper was included in brgen's
    # ApplicationController only, so placing an ad slot in amber or bsdports would
    # have raised NoMethodError and taken the page down instead of rendering
    # nothing, which is exactly what brgen's own comment warns about. Registered
    # here so the gate travels with the partial.
    initializer "shared.consent_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        require_dependency Shared::Engine.root.join("app/helpers/shared/consent_helper").to_s
        helper Shared::ConsentHelper
      end
    end

    initializer "shared.ui_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        require_dependency Shared::Engine.root.join("app/helpers/shared/ui_helper").to_s
        helper Shared::UiHelper
        # Same require_dependency shape as UiHelper above: the engine app/helpers
        # path is not on every app autoload path, so the bare constant is not
        # guaranteed to resolve at this point in boot.
        require_dependency Shared::Engine.root.join("app/helpers/shared/rich_text_helper").to_s
        helper Shared::RichTextHelper
        require_dependency Shared::Engine.root.join("app/helpers/shared/place_helper").to_s
        helper Shared::PlaceHelper
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
        headers: app.config.public_file_server.headers,
      )
    end
  end
end
