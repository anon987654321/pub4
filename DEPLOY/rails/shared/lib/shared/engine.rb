# frozen_string_literal: true
module Shared
  class Engine < ::Rails::Engine
    isolate_namespace Shared
    # Use << not += — Rails 8.1 freezes path arrays during engine boot; += breaks later engines.
    %w[app/models app/models/concerns app/services app/controllers app/controllers/concerns app/policies app/helpers].each do |dir|
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

    def self.concern(n); const_get("Shared::#{n.to_s.camelize}") rescue (require "shared/#{n}"; const_get("Shared::#{n.to_s.camelize}")) end
  end
end
