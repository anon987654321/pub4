# frozen_string_literal: true

require "pub4/deploy_paths"
require "rbconfig"
require "fileutils"
require "open3"

module Shared
  # Runs studio/dilla/dilla.rb and attaches audio to a record.
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
      allowed = STYLES.map { |name| name.tr("-", "_") }
      allowed.include?(s) ? s : "dilla"
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
      # Kit-forward profile now comes from the engine's own DILLA_BEST_DEFAULTS /
      # DILLA_STYLE_DEFAULTS soft-fill (RENDER_MODE=dilla) -- there's no
      # separate wrapper env table to keep in sync with those anymore.
      # Only pass process-level overrides here so Solid Queue matches chat renders.
      track = style.to_s.downcase.tr("-", "_")
      env = {
        "DILLA_RAW" => ENV.fetch("DILLA_RAW", "0"),
        "STREAM_CONTINUOUS" => "0",
        "SPEAK" => ENV.fetch("DILLA_SPEAK", "0"),
        "DILLA_SPEAK" => ENV.fetch("DILLA_SPEAK", "0"),
        "RAP_VOCAL" => ENV.fetch("RAP_VOCAL", "jonas_v"),
        "RENDER_MODE" => "dilla"
      }
      # Leave TRACK/PROGRESSION unset for the generic "dilla" style so the
      # engine's own default-progression resolution picks it, same as an
      # unadorned `ruby engine.rb dilla`.
      unless track.empty? || track == "dilla"
        env["TRACK"] = track
        env["PROGRESSION"] = track
      end
      cmd = [RbConfig.ruby, script.to_s, "dilla", output.to_s, bars.to_s]
      run_with_timeout(env, cmd)
    end

    # dilla has hung indefinitely before, pinning a Solid Queue worker forever with
    # the sketch stuck "rendering". popen3 + a wait timeout frees the worker AND kills
    # the child (capture3 wrapped in Timeout would leave it running). Reader threads
    # avoid a pipe-buffer deadlock.
    def run_with_timeout(env, cmd)
      require "timeout"
      seconds = Integer(ENV.fetch("DILLA_SH_TIMEOUT", "900"))
      Open3.popen3(env, *cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        out_reader = Thread.new { stdout.read }
        err_reader = Thread.new { stderr.read }
        # On the timeout path popen3 closes these pipes out from under the readers,
        # which would raise a stray IOError — we're abandoning that output anyway.
        out_reader.report_on_exception = false
        err_reader.report_on_exception = false
        begin
          status = Timeout.timeout(seconds) { wait_thr.value }
        rescue Timeout::Error
          # The process exiting between the timeout and the signal is the only
          # failure worth ignoring here; a bare `rescue nil` would also hide a
          # permissions problem, which is a real bug.
          begin
            Process.kill("TERM", wait_thr.pid)
          rescue Errno::ESRCH, Errno::EPERM
            nil
          end
          [out_reader, err_reader].each(&:kill)
          log("dilla render timed out after #{seconds}s — killed pid #{wait_thr.pid}")
          return false
        end
        out = out_reader.value.to_s
        err = err_reader.value.to_s
        log("dilla stdout: #{out.lines.last.to_s.strip}") if out.strip != ""
        log("dilla stderr: #{err.lines.last.to_s.strip}") if !status.success? && err.strip != ""
        status.success?
      end
    end

    def log(message)
      return unless defined?(Rails)

      Rails.logger.info(message)
    end
  end
end
