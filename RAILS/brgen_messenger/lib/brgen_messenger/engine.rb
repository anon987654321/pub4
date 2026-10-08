# frozen_string_literal: true

require "rails/engine"

module BrgenMessenger
  class Engine < ::Rails::Engine
    config.paths["db/migrate"] << root.join("db/migrate").to_s
  end
end
