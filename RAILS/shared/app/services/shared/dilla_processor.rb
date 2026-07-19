# frozen_string_literal: true

require "pub4/deploy_paths"
require "rbconfig"
require "fileutils"
require "open3"

module Shared
  # Runs MASTER/tools/dilla.rb generate and attaches audio to a record.
  module DillaProcessor
    STYLES = %w[dilla flylo baroque bach neo-soul neo_soul jazz].freeze
    DEFAULT_BARS = 12
    MAX_BARS = 64

    module_function

    def script
      Pub4::DeployPaths.dilla_script
    end

    def available?
      path = script
      !path.to_s.empty? && File.file?(path)
    end

    def skip?
      ENV["SKIP_DILLA_RENDER"].to_s != "" || !available?
    end

    def normalize_style(style)
      s = style.to_s.downcase.tr("-", "_")
      s = "neo-soul" if s == "neo_soul"
      return "dilla" unless STYLES.map { |x| x.tr("-", "_") }.include?(s.tr("-", "_")) || STYLES.include?(style.to_s.downcase)

      style.to_s.downcase
    end

    def normalize_bars(bars)
      n = bars.to_i
      n = DEFAULT_BARS if n <= 0
      [[n, MAX_BARS].min, 4].max
    end

    # Render to a temp path. Returns absolute path or nil.
    def render_to_file!(style: "dilla", bars: DEFAULT_BARS, output: nil)
      return nil if skip?

      style = normalize_style(style)
      bars = normalize_bars(bars)
      Dir.mktmpdir("dilla_render") do |dir|
        out = output || File.join(dir, "#{style}_#{bars}bars.mp3")
        FileUtils.mkdir_p(File.dirname(out))
        ok = run_script(style, out, bars)
        return nil unless ok && File.file?(out) && File.size?(out).to_i.positive?

        # Copy out of tmpdir if we used it
        if output.nil?
          kept = File.join(Dir.tmpdir, "dilla_#{Process.pid}_#{Time.now.to_i}.mp3")
          FileUtils.cp(out, kept)
          return kept
        end
        out
      end
    end

    def attach_to_record!(record, attachment_name: :render, style: "dilla", bars: DEFAULT_BARS)
      path = render_to_file!(style: style, bars: bars)
      return false unless path

      File.open(path, "rb") do |io|
        record.public_send(attachment_name).attach(
          io: io,
          filename: File.basename(path),
          content_type: "audio/mpeg"
        )
      end
      FileUtils.rm_f(path)
      true
    rescue StandardError => e
      log("dilla attach failed for #{record.class.name}##{record.id}: #{e.class}: #{e.message}")
      false
    ensure
      FileUtils.rm_f(path) if path
    end

    def run_script(style, output, bars)
      # Kit-forward profile is applied inside MASTER/tools/dilla.rb (PRODUCT_KIT_ENV).
      # Only pass process-level overrides here so Solid Queue matches chat renders.
      env = {
        "DILLA_RAW" => ENV.fetch("DILLA_RAW", "0"),
        "STREAM_CONTINUOUS" => "0",
        "SPEAK" => ENV.fetch("DILLA_SPEAK", "0"),
        "DILLA_SPEAK" => ENV.fetch("DILLA_SPEAK", "0"),
        "RAP_VOCAL" => ENV.fetch("RAP_VOCAL", "jonas_v"),
        "RENDER_MODE" => "dilla"
      }
      cmd = [
        RbConfig.ruby, script.to_s, "generate",
        "--style", style.to_s,
        "--output", output.to_s,
        "--bars", bars.to_s
      ]
      out, err, status = Open3.capture3(env, *cmd)
      log("dilla stdout: #{out.lines.last.to_s.strip}") if out.to_s.strip != ""
      log("dilla stderr: #{err.lines.last.to_s.strip}") if !status.success? && err.to_s.strip != ""
      status.success?
    end

    def log(message)
      return unless defined?(Rails)

      Rails.logger.info(message)
    end
  end
end
