# frozen_string_literal: true

require "pathname"

module Pub4
  # Monorepo vs copy-tree deploy path resolution (brgen app/ vs DEPLOY/ siblings).
  module DeployPaths
    module_function

    def postpro_script
      postpro_candidates.map(&:expand_path).uniq.find { |path| File.file?(path) }
    end

    def postpro_candidates
      rails = Pathname.new(Rails.root)
      deploy_rails = ENV.fetch("PUB4_RAILS_ROOT", "/home/dev/pub4/DEPLOY/rails")
      [
        rails.join("../../postpro/postpro.rb"),
        Pathname.new(deploy_rails).join("../postpro/postpro.rb"),
        Pathname.new("/home/dev/pub4/DEPLOY/postpro/postpro.rb")
      ]
    end
  end
end