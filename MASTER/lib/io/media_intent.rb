# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "time"
require_relative "../master_paths"
require_relative "script_dispatch"

module Master
  module Io
    # Routes a plainly spoken creative request to the local, consented media tools.
    # It is deliberately narrow: ordinary discussion of artists remains a chat turn.
    module MediaIntent
      module_function

      # Finished media lands in the user's home directory, not the repo.
      MEDIA_OUTPUT_DIR = File.expand_path("~")

      IMAGE_RE = /\b(?:make|create|generate|render|photograph|photo|portrait|image|picture)\b/i.freeze
      AUDIO_RE = /\b(?:make|create|generate|compose|render)\b.*\b(?:beat|loop|instrumental|track|music)\b|\b(?:dilla|j dilla|fly(?:ing)?\s+lotus|madlib|bach|baroque)\b.*\b(?:beat|loop|instrumental|track|music)\b/i.freeze
      POSTPRO_RE = /\b(?:post-?process|colour\s+grade|color\s+grade|film\s+look|vhs(?:\s+tape)?\s+look|crt(?:\s+broadcast)?\s+look|camcorder(?:\s+glitch)?\s+look|make\s+this\s+(?:cinematic|analog|analogue))\b/i.freeze
      IMAGE_PATH_RE = /(?:["']([^"']+\.(?:jpe?g|png|webp|tiff?))["']|(?:\A|\s)([^\s"']+\.(?:jpe?g|png|webp|tiff?))(?=\z|\s))/i.freeze

      def handles?(text)
        text.match?(AUDIO_RE) || text.match?(POSTPRO_RE) ||
          text.match?(IMAGE_RE) && text.match?(/\b(?:photo|portrait|image|picture)\b/i)
      end

      def dispatch(text, root: MasterPaths.root)
        return postprocess(text, root:) if text.match?(POSTPRO_RE)
        return generate_beat(text, root:) if text.match?(AUDIO_RE)

        generate_cloud_image(text, root:)
      end

      def generate_cloud_image(prompt, root:)
        output = File.join(MEDIA_OUTPUT_DIR, "repligen-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.webp")
        args = ["generate", "--prompt", prompt, "--output", output]
        result = ScriptDispatch.run(root:, tool: "repligen", arg: args.map { |v| Shellwords.escape(v) }.join(" "))
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :repligen, path: output }) : result
      end

      def postprocess(text, root:)
        source = text.match(IMAGE_PATH_RE)&.captures&.compact&.first
        return Result.err("postpro: include an existing JPG, PNG, WebP, or TIFF path", category: :validation) if source.to_s.empty?

        source = File.expand_path(source)
        return Result.err("postpro: input not found #{source}", category: :validation) unless File.file?(source)

        preset = postpro_preset_for(text)
        output_dir = MEDIA_OUTPUT_DIR
        FileUtils.mkdir_p(output_dir)
        ext = File.extname(source)
        output = File.join(output_dir, "#{File.basename(source, ext)}-#{preset}#{ext}")
        args = ["--input", source, "--output", output, "--preset", preset]
        result = ScriptDispatch.run(root:, tool: "postpro", arg: args.map { |value| Shellwords.escape(value) }.join(" "))
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :postpro, path: output }) : result
      end

      POSTPRO_PRESETS = [
        [/\bvhs\b/i, "vhs_tape"],
        [/\bcrt\b/i, "crt_broadcast"],
        [/\bcamcorder|mini\s*dv|hi\s*8\b/i, "camcorder_glitch"],
        [/\bportrait\b/i, "portrait"],
        [/\bnoir|black\s+and\s+white\b/i, "noir"],
        [/\blo[ -]?fi\b/i, "lo_fi"],
        [/\bmagic\s+hour|golden\s+hour\b/i, "magic_hour"],
      ].freeze

      def postpro_preset_for(text)
        POSTPRO_PRESETS.find { |pattern, _preset| text.match?(pattern) }&.last || "cinematic"
      end

      def generate_beat(text, root:)
        style = if text.match?(/\bbach|baroque\b/i)
                  "baroque"
                elsif text.match?(/\bneo[ -]?soul\b/i)
                  "neo-soul"
                elsif text.match?(/\bjazz\b/i)
                  "jazz"
                elsif text.match?(/fly(?:ing)?\s+lotus/i)
                  "flylo"
                else
                  "dilla"
                end
        output_dir = MEDIA_OUTPUT_DIR
        FileUtils.mkdir_p(output_dir)
        output = File.join(output_dir, "#{style}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.mp3")
        args = ["generate", "--style", style, "--output", output]
        result = ScriptDispatch.run(root:, tool: "dilla", arg: args.map { |v| Shellwords.escape(v) }.join(" "))
        result.ok? ? Result.ok({ output: result.value!, rendered: result.value!, media: :dilla, path: output }) : result
      end
    end
  end
end
