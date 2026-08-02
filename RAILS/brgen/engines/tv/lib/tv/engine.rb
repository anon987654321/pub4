# frozen_string_literal: true

module Tv
  # brgen's TV vertical, extracted from the host app 2026-08-02 as the pilot for
  # the vertical-as-engine split. Mirrors Shared::Engine's conventions exactly —
  # `<<` not `+=` on the frozen Rails 8.1 path arrays, explicit view/asset paths —
  # so the five verticals share one boot shape. See ENGINES.md.
  class Engine < ::Rails::Engine
    isolate_namespace Tv

    # << not += : Rails 8.1 freezes these arrays during engine boot and += rebinds
    # to a new frozen array that later engines then fail to append to.
    %w[
      app/controllers app/controllers/concerns
      app/models app/models/concerns
      app/helpers app/services app/jobs app/reflexes app/channels
    ].each do |dir|
      path = root.join(dir)
      config.autoload_paths << path.to_s if path.exist?
    end

    config.paths["db/migrate"] << root.join("db/migrate").to_s

    initializer "tv.view_paths" do
      ActiveSupport.on_load(:action_controller_base) do
        append_view_path Tv::Engine.root.join("app/views")
      end
    end

    initializer "tv.assets" do |app|
      %w[app/assets/stylesheets app/javascript].each do |dir|
        p = Tv::Engine.root.join(dir).to_s
        app.config.assets.paths << p if Dir.exist?(p) && !app.config.assets.paths.include?(p)
      end
    end
  end
end
