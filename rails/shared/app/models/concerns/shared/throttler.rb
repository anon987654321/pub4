# frozen_string_literal: true

module Shared
  class Throttler
    def initialize(app) = @app = app

    def call(env)
      request = Rack::Request.new(env)
      window = Time.current.to_i / 60
      count = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(["SELECT increment_request(?, ?)", request.ip, window])
      )
      if count.to_i > 120
        [429, { "Content-Type" => "application/json" }, [{ error: "Rate Limit Exceeded" }.to_json]]
      else
        @app.call(env)
      end
    end
  end
end
