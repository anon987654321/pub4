# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

module Master
  module Reach
    class Postpro
      TIER = :dangerous
      NAME = "postpro".freeze
      DESCRIPTION = "Apply cinematic post-processing to images via ruby-vips.".freeze
      PRESETS = %w[portrait landscape street blockbuster].freeze
      SCRIPT_PATHS = [
        "../DEPLOY/postpro.rb",
        "../../DEPLOY/postpro.rb",
        "../postpro.rb"
      ].freeze

      def initialize(root:, governor:, event_bus: nil)
        @root = root
        @governor = governor
        @bus = event_bus
      end

      def call(target_dir:, preset: "portrait", variations: 2, recipe: nil, patterns: nil)
        target = absolute(target_dir)
        return Result.err("postpro: target_dir required", category: :validation) if target_dir.to_s.empty?
        return Result.err("postpro: not a directory: #{target}", category: :validation) unless File.directory?(target)
        return Result.err("postpro: unknown preset #{preset}", category: :validation) unless recipe || PRESETS.include?(preset.to_s)

        script = script_path
        return Result.err("postpro: script missing", category: :infrastructure) unless script

        permission = @governor.permit?(NAME, TIER, "postpro #{preset} #{target}")
        return permission if permission.err?

        config_path = write_config(preset:, variations:, recipe:, patterns:)
        @bus&.publish("tool:before", tool: NAME, target: target, preset: preset)
        output, error, status = Open3.capture3({ "POSTPRO_DRIVER_CONFIG" => config_path }, "ruby", script, "--auto", chdir: target)
        @bus&.publish("tool:after", tool: NAME, exit: status.exitstatus)
        return Result.ok(format_output(output, error)) if status.success?

        Result.err("postpro: exit #{status.exitstatus} #{error.strip}", category: :provider_error)
      rescue StandardError => error
        Result.err("postpro: #{error.message}", category: :infrastructure)
      ensure
        FileUtils.rm_f(config_path) if defined?(config_path) && config_path
      end

      private

      def absolute(path)
        value = path.to_s
        File.absolute_path?(value) ? value : File.expand_path(value, @root)
      end

      def script_path
        SCRIPT_PATHS.map { |path| File.expand_path(path, @root) }.find { |path| File.exist?(path) }
      end

      def write_config(preset:, variations:, recipe:, patterns:)
        config = {
          "default_preset" => preset.to_s,
          "variations" => variations.to_i.clamp(1, 5),
          "jpeg_quality" => 95
        }
        config["patterns"] = Array(patterns) if patterns
        config["recipe"] = recipe if recipe
        path = File.join(Dir.tmpdir, "postpro_driver_#{Process.pid}_#{Time.now.to_i}.json")
        File.write(path, JSON.pretty_generate(config))
        path
      end

      def format_output(output, error)
        lines = (output.to_s + error.to_s).lines.map(&:strip).reject(&:empty?)
        lines.empty? ? "(no output)" : lines.last(40).join("\n")
      end
    end
  end
end
