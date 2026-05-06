# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tmpdir"
require "fileutils"

module Master
  module Tools
    # Postpro — drive the multimedia/postpro.rb pipeline (libvips/ruby-vips,
    # film stocks, presets, recipes) from MASTER. Shells out so we don't
    # pollute Master's namespace with postpro's top-level constants.
    class Postpro
      TIER        = :dangerous
      NAME        = "postpro".freeze
      DESCRIPTION = "Apply cinematic post-processing (film grain, halation, teal-orange, presets, recipes) to images via ruby-vips.".freeze
      TIMEOUT     = 600
      PRESETS     = %w[portrait landscape street blockbuster].freeze
      SCRIPT_REL  = "../multimedia/postpro.rb".freeze

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
      end

      def call(target_dir:, preset: "portrait", variations: 2, recipe: nil, patterns: nil)
        return Result.err("postpro: target_dir required", category: :validation) if target_dir.to_s.empty?
        return Result.err("postpro: unknown preset #{preset}", category: :validation) unless PRESETS.include?(preset.to_s) || recipe

        target_abs = absolute(target_dir)
        return Result.err("postpro: not a directory: #{target_abs}", category: :validation) unless File.directory?(target_abs)

        perm = @governor.permit?(NAME, TIER, "postpro #{preset} #{target_abs}")
        return perm if perm.err?

        script = File.expand_path(SCRIPT_REL, @root)
        return Result.err("postpro: script missing at #{script}", category: :infrastructure) unless File.exist?(script)

        config_path = write_driver_config(target_abs, preset:, variations:, recipe:, patterns:)
        @bus&.publish("tool:before", tool: NAME, target: target_abs, preset: preset)

        out, err, status = Open3.capture3(
          { "POSTPRO_DRIVER_CONFIG" => config_path },
          "ruby", script, "--auto",
          chdir: target_abs
        )

        @bus&.publish("tool:after", tool: NAME, exit: status.exitstatus)
        status.success? ? Result.ok(format_output(out, err)) :
                          Result.err("postpro: exit #{status.exitstatus} #{err.strip}", category: :provider_error)
      rescue StandardError => e
        Result.err("postpro: #{e.message}", category: :infrastructure)
      ensure
        FileUtils.rm_f(config_path) if defined?(config_path) && config_path
      end

      private

      def absolute(path)
        path = path.to_s
        File.absolute_path?(path) ? path : File.expand_path(path, @root)
      end

      def write_driver_config(dir, preset:, variations:, recipe:, patterns:)
        config = {
          "default_preset" => preset.to_s,
          "variations"     => variations.to_i.clamp(1, 5),
          "jpeg_quality"   => 95
        }
        config["patterns"] = Array(patterns) if patterns
        config["recipe"]   = recipe if recipe

        path = File.join(Dir.tmpdir, "postpro_driver_#{Process.pid}_#{Time.now.to_i}.json")
        File.write(path, JSON.pretty_generate(config))
        path
      end

      def format_output(out, err)
        lines = (out.to_s + err.to_s).lines.map(&:strip).reject(&:empty?)
        summary = lines.last(20).join("\n")
        summary.empty? ? "(no output)" : summary
      end
    end
  end
end
