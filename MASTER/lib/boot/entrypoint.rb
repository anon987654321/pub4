# frozen_string_literal: true

require "fileutils"
require "json"
require "rubygems"
require "time"
require_relative "dependency_manager"
require_relative "../trace/dmesg"
require_relative "../operator/environment"
require_relative "../operator/ruby_runner"

module Master
  module Boot
    module Entrypoint
      module_function

      SUPPORTED_RUBY_MIN = Operator::Environment::SUPPORTED_RUBY_MIN
      SUPPORTED_RUBY_MAX = Operator::Environment::SUPPORTED_RUBY_MAX

      def prepare!(root:, env: ENV, out: $stderr, argv: ARGV, program: $PROGRAM_NAME)
        root = File.expand_path(root)
        reexec_best_ruby!(root:, env:, out:, argv:, program:)
        manager = DependencyManager.new(root:, env:, out:)
        result = manager.ensure!
        unless result.ok
          Master::Trace::Dmesg.status("deps0", result.message, io: out)
          detail = result.output.to_s.strip
          Master::Trace::Dmesg.status("deps0", detail, io: out) unless detail.empty?
          exit 78
        end

        manager.activate_environment!
        reexec_mismatched_bundler!(root:, env:, out:, argv:, program:)
        activate_bundle!(root)
        write_boot_receipt!(root:, out:)

        true
      end

      def reexec_mismatched_bundler!(root:, env:, out:, argv:, program:)
        lock_version = locked_bundler_version(root)
        return if lock_version.empty?

        active = Gem.loaded_specs["bundler"]&.version&.to_s
        return if active.nil? || active == lock_version
        return if env["MASTER_BUNDLER_REEXEC_DONE"] == "1"

        clean_env = env.to_h.dup
        %w[RUBYOPT RUBYLIB].each { |key| clean_env.delete(key) }
        %w[
          BUNDLE_APP_CONFIG BUNDLE_BIN BUNDLE_DEPLOYMENT BUNDLE_FROZEN
          BUNDLE_GEMFILE BUNDLE_IGNORE_CONFIG BUNDLE_JOBS BUNDLE_LOCKFILE
          BUNDLE_ONLY BUNDLE_PATH BUNDLE_RETRY BUNDLE_USER_CONFIG
          BUNDLE_USER_HOME BUNDLE_VERSION BUNDLE_WITH BUNDLE_WITHOUT
        ].each { |key| clean_env.delete(key) }
        cle...[truncated]