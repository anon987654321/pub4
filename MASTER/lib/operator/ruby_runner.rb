# frozen_string_literal: true

require_relative "../io/exec"
require_relative "environment"

module Operator
  module RubyRunner
    module_function

    def ruby_cmd(root: Environment.repo_root)
      explicit = ENV["PUB4_RUBY"].to_s
      return explicit if !explicit.empty? && File.executable?(explicit)

      candidate = best_available_ruby(root:)
      return candidate[:path] if candidate

      raise Environment.ruby_mismatch_message
    end

    def bundle_cmd(root: Environment.repo_root)
      explicit = ENV["PUB4_BUNDLE"].to_s
      return explicit if !explicit.empty? && File.executable?(explicit)

      ruby = best_available_ruby(root:)&.fetch(:path, nil)
      if ruby
        sibling = File.join(File.dirname(ruby), "bundle")
        return sibling if File.executable?(sibling)
      end

      command_path("bundle")
    end

    def best_available_ruby(root: Environment.repo_root)
      candidates = []
      candidates.concat(rbenv_ruby_candidates(root:))
      %w[ruby4.0 ruby40 ruby3.4 ruby34 ruby3.3 ruby33 ruby].each do |name|
        path = command_path(name)
        candidates << path unless path.empty?
      end
      candidates << RbConfig.ruby if File.executable?(RbConfig.ruby)

      candidates.filter_map do |path|
        version = version_for(path)
        next unless version && Environment::SUPPORTED_RUBY_MIN <= version && version < Environment::SUPPORTED_RUBY_MAX

        { path:, version: }
      end.max_by { |candidate| candidate[:version] }
    end

    def rbenv_ruby_candidates(root: Environment.repo_root)
      rbenv_root = ENV["RBENV_ROOT"].to_s
      rbenv_root = File.expand_path("~/.rbenv") if rbenv_root.empty?
      direct = Dir.glob(File.join(rbenv_root, "versions", "*", "bin", "ruby"))
      direct.select { |path| File.executable?(path) }
    end

    def rbenv_path(name, root: Environment.repo_root)
      return best_available_ruby(root:)[:path] if name == "ruby" && best_available_ruby(root:)

      ruby = best_available_ruby(root:)&...[truncated]