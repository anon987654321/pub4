# frozen_string_literal: true
module Shared
  class Engine < ::Rails::Engine
    isolate_namespace Shared
    config.autoload_paths += %W[#{root}/app/models/concerns #{root}/app/services #{root}/app/controllers/concerns]
    config.eager_load_paths += config.autoload_paths
    config.active_record.schema_format = :ruby if config.respond_to?(:active_record)
    def self.concern(n); const_get("Shared::#{n.to_s.camelize}") rescue (require "shared/#{n}"; const_get("Shared::#{n.to_s.camelize}")) end
  end
end
