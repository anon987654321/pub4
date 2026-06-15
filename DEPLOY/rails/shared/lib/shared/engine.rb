# frozen_string_literal: true

module Shared
  class Engine < ::Rails::Engine
    isolate_namespace Shared

    # Autoload paths for concerns, services, etc.
    config.autoload_paths += %W[
      #{root}/app/models/concerns
      #{root}/app/services
      #{root}/app/controllers/concerns
    ]

    # If we want to mount routes later for shared controllers
    # initializer "shared.routes" do |app|
    #   app.routes.prepend do
    #     mount Shared::Engine, at: "/shared"
    #   end
    # end
  end
end
