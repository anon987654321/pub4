# frozen_string_literal: true
module Shared
  class Engine < ::Rails::Engine
    isolate_namespace Shared
    config.autoload_paths += %W[
      #{root}/app/models
      #{root}/app/models/concerns
      #{root}/app/services
      #{root}/app/controllers
      #{root}/app/controllers/concerns
      #{root}/app/policies
      #{root}/app/helpers
    ]
    config.eager_load_paths += config.autoload_paths
    config.active_record.schema_format = :ruby if config.respond_to?(:active_record)

    initializer "shared.view_paths" do
      ActiveSupport.on_load(:action_controller_base) do
        append_view_path Shared::Engine.root.join("app/views")
      end
    end

    initializer "shared.search_helper" do
      ActiveSupport.on_load(:action_controller_base) do
        helper Shared::SearchHelper
      end
    end

    def self.concern(n); const_get("Shared::#{n.to_s.camelize}") rescue (require "shared/#{n}"; const_get("Shared::#{n.to_s.camelize}")) end
  end
end
