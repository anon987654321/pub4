# frozen_string_literal: true

require "shared/contracts"
Shared::Contracts.require_contract("studio")
require "rbconfig"
require "fileutils"
require "open3"

module Shared
  # Runs STUDIO/dilla/dilla.rb and attaches audio to a record.
  module DillaProcessor
    module_function

    def script
      ::Contracts::Studio.dilla_script
    end

    def available?
      path = script
      !path.to_s.empty? && File.file?(path)
    end

    def skip?
      ENV["SKIP_DILLA_RENDER"].to_s != "" || !available?
    end

    # Render to a temp path: a random progression under a random drum pattern,
    # which is what `dilla.rb --random` picks. Returns the absolute path or nil.
    def render_to_file!(output: nil)
      return nil if skip?

      Dir.mktmpdir("dilla_render") do |dir|
        out = output || File.join(dir, "dilla.wav")
        FileUtils.mkdir_p(File.dirname(out))
        ok = run_script(out)
        return nil unless ok && File.file?(out) && File.size?(out).to_i.positive?

        # Copy out of tmpdir if we used it
        if output.nil?
          kept = File.join(Dir.tmpdir, "dilla_#{Process.pid}_#{Time.now.to_i}.wav")
          FileUtils.cp(out, kept)
          return kept
        end
        out
      end
    end

    def attach_to_record!(record, attachment_name: :render)
      path = render_to_file!
      return false unless path

      File.open(path, "rb") do |io|
        record.public_send(attachment_name).attach(
          io:,
          filename: File.basename(path),
          content_type: "audio/wav",
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

    def run_script(output)
      run_with_timeout({}, [ RbConfig.ruby, script.to_s, "--random", "--out", output.to_s ])
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
          [ out_reader, err_reader ].each(&:kill)
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
