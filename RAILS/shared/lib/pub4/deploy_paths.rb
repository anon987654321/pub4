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
        Pathname.new("#{DEFAULT_REPO}/MASTER/tools/postpro.rb")
      ]
    end

    def repligen_candidates
      [
        repo_join("MASTER/tools/repligen.rb"),
        Pathname.new("#{DEFAULT_REPO}/MASTER/tools/repligen.rb")
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
  end
end
