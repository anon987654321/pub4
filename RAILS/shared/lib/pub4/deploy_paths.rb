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
    def dilla_script = first_file(dilla_candidates)
    def radio_bergen_study_script = first_file(radio_bergen_study_candidates)

    def postpro_candidates
      [
        repo_join("STUDIO/postpro/postpro.rb"),
        Pathname.new("#{DEFAULT_REPO}/STUDIO/postpro/postpro.rb"),
        rails_root.join("../../STUDIO/postpro/postpro.rb"),
      ]
    end

    def repligen_candidates
      [
        repo_join("STUDIO/repligen/repligen.rb"),
        Pathname.new("#{DEFAULT_REPO}/STUDIO/repligen/repligen.rb"),
        rails_root.join("../../STUDIO/repligen/repligen.rb"),
      ]
    end

    def dilla_candidates
      [
        repo_join("STUDIO/dilla/dilla.rb"),
        Pathname.new("#{DEFAULT_REPO}/STUDIO/dilla/dilla.rb"),
        rails_root.join("../../STUDIO/dilla/dilla.rb"),
      ]
    end

    # The study script is a thin wrapper around RadioBergenStudy, which lives in
    # dilla.rb. It moved with the rest of STUDIO/radio-bergen when that directory
    # was removed; same three-candidate shape as its neighbours above.
    def radio_bergen_study_candidates
      [
        repo_join("STUDIO/dilla/scripts/radio_bergen_study.rb"),
        Pathname.new("#{DEFAULT_REPO}/STUDIO/dilla/scripts/radio_bergen_study.rb"),
        rails_root.join("../../STUDIO/dilla/scripts/radio_bergen_study.rb"),
      ]
    end

    # MASTER web bridge (ai.brgen.no / loopback :53187) for constitutional turns.
    def master_bridge_base
      env_value("MASTER_BRIDGE_URL") ||
        env_value("MASTER_WEB_URL") ||
        (File.file?("/etc/relayd.conf") ? "http://127.0.0.1:53187" : "http://127.0.0.1:53187")
    end

    # Falls back to the checkout this file actually lives in, not to the server
    # path. DEFAULT_RAILS is /home/dev/pub4/RAILS, so with no PUB4_RAILS_ROOT set
    # every candidate below resolved somewhere under /home/dev — which exists
    # only on the VPS. Locally that made radio_bergen_study_script and friends
    # unresolvable, and `bin/rails test` aborted at load time with a LoadError
    # from radio_bergen_study_test.rb before a single test ran. The test file for
    # this module only ever exercised the with-PUB4_ROOT path, so the gap was
    # invisible.
    def rails_root
      explicit = env_value("PUB4_RAILS_ROOT")
      return Pathname.new(explicit) if explicit

      # In a booted app, Rails.root is the app dir (RAILS/brgen); RAILS/ is its
      # parent. Most reliable anchor when it's available.
      if defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root
        candidate = Pathname.new(::Rails.root).join("..").expand_path
        return candidate if candidate.directory?
      end

      # Source tree: this file is RAILS/shared/lib/pub4/deploy_paths.rb, so RAILS/
      # is three levels up. Works in any clone, and outside Rails entirely
      # (plain `ruby -Ilib` runs, gates, the deploy scripts).
      source_rails = Pathname.new(__dir__).join("../../..").expand_path
      return source_rails if source_rails.directory?

      Pathname.new(DEFAULT_RAILS)
    end

    def deploy_root
      explicit = env_value("PUB4_DEPLOY_ROOT")
      return Pathname.new(explicit) if explicit

      repo = env_value("PUB4_ROOT")
      return Pathname.new(File.join(repo, "OPENBSD")) if repo

      rails_root.join("..").expand_path
    end

    def repo_root
      repo = env_value("PUB4_ROOT")
      return Pathname.new(repo) if repo

      # Derived from rails_root, not from deploy_root. deploy_root is already
      # rails_root/.. (the repo), so going up again landed one level *above* the
      # checkout: with rails_root = /home/dev/pub4/RAILS this returned /home/dev,
      # and repo_join("STUDIO/…") pointed at /home/dev/studio. That is why every
      # candidate list needed the hardcoded DEFAULT_REPO entry to work at all —
      # the derived one had always been wrong, on the server too.
      rails_root.join("..").expand_path
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
        warn "DeployPaths: unexpected layout. rails_root=#{root} " \
             "(expected RAILS/shared in source or sibling shared/ on target)"
      end
      true
    end
  end
end
