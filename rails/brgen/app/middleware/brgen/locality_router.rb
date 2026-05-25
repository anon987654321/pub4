# frozen_string_literal: true

module Brgen
  class LocalityRouter
    def initialize(app) = @app = app

    def call(env)
      request = Rack::Request.new(env)
      host_parts = request.host.split(".")
      if host_parts.size > 2 && host_parts.first != "www"
        env["brgen.city_context"] = host_parts.first
        Thread.current[:brgen_city_context] = host_parts.first
      end
      @app.call(env)
    end
  end
end
