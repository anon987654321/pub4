# frozen_string_literal: true

require "pathname"

module Pub4
  # Monorepo vs copy-tree deploy path resolution (Rails app/ vs repo siblings).
  module DeployPaths
    DEFAULT_REPO = "/home/dev/pub4"
    DEFAULT_RAILS = "#{DEFAULT_REPO}/RAILS".freeze

    module_function

    def postpro_script = first_file(postpro_candidates)
    def repligen_script = first_file(repligen_candidates)

    def postpro_candidates
      [
        repo_join("MASTER/tools/postpro.rb"),
        Pathname.new("#{DEFAULT_REPO}/MASTER/tools/postpro.rb"),
        rails_root.join("../../MASTER/tools/postpro.rb")
      ]
    end

    def repligen_candidates
      [
        repo_join("MASTER/tools/repligen.rb"),
        Pathname.new("#{DEFAULT_REPO}/MASTER/tools/repligen.rb"),
        rails_root.join("../../MASTER/tools/repligen.rb")
      ]
    end

    def rails_root
      Pathname.new(env_value("PUB4_RAILS_ROOT") || DEFAULT_RAILS)
    end

    def deploy_root
      explicit = env_value("PUB4_DEPLOY_ROOT")
      return Pathname.new(explicit) if explicit

      repo = env_value("PUB4_ROOT")
      return Pathname.new(File.join(repo, "OPERATOR")) if repo

      rails_root.join("..").expand_path
    end

    def repo_root
      repo = env_value("PUB4_ROOT")
      return Pathname.new(repo) if repo

      deploy_root.join("..").expand_path
    end

    def env_value(key)
      value = ENV[key]
      return nil if value.nil?

      stripped = value.strip
      stripped.empty? ? nil : stripped
    end

    def rails_relative(rel)
      return Pathname.new(rel) unless defined?(Rails)

      Pathname.new(Rails.root).join(rel)
    end

    def deploy_join(rel)
      deploy_root.join(rel)
    end

    def repo_join(rel)
      repo_root.join(rel)
    end

    def first_file(candidates)
      candidates.map { |path| path.is_a?(Pathname) ? path : Pathname.new(path.to_s) }
        .map(&:expand_path)
        .uniq
        .find { |path| File.file?(path) }
    end

    # Lightweight sanity check for copy-tree layout (deployed: app/ + sibling shared/).
    # In source tree, shared lives at RAILS/shared (inside the monorepo).
    # Used by gates and deploy scripts to surface misconfigured PUB4_* env on VPS.
    # Only active/noisy in prod-like envs to avoid local dev tree noise.
    def validate_layout!
      return true unless ENV["PUB4_RAILS_ROOT"] || ENV["RAILS_ENV"] == "production" || RUBY_PLATFORM.include?("openbsd")

      root = rails_root
      # Deployed copy-tree: /home/<app>/app  with sibling /home/<app>/shared
      # Source: RAILS/ (apps + shared/ inside)
      sibling_shared = root.join("../shared")
      internal_shared = root.join("shared")
      is_source = File.directory?(internal_shared.to_s)
      is_deployed_sibling = File.directory?(sibling_shared.to_s)
      unless is_source || is_deployed_sibling
        warn "DeployPaths: unexpected layout. rails_root=#{root} (expected RAILS/shared in source or sibling shared/ on target)"
      end
      true
    end
  end
end
