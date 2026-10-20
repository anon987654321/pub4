# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "time"

module Contracts
  module Studio
    PHOTOGRAPH_TIMEOUT = Integer(ENV.fetch("STUDIO_PHOTOGRAPH_TIMEOUT", "120"))
    OUTPUT_PATH_TIMEOUT = Integer(ENV.fetch("STUDIO_OUTPUT_PATH_TIMEOUT", "10"))
    OUTPUT_PATH_COMMANDS = {
      reference_root: "reference-root",
      dilla_render_directory: "dilla-render-directory",
    }.freeze

    module_function

    def root
      value = ENV["PUB4_STUDIO_ROOT"].to_s.strip
      return File.expand_path(value) unless value.empty?

      File.expand_path("../../STUDIO", __dir__)
    end

    def dilla_script = first_file("dilla/dilla.rb")
    def photograph_script = first_file("photograph.rb")
    def postpro_script = first_file("postpro/postpro.rb")
    def replicate_script = first_file("replicate/replicate.rb")

    def first_file(relative)
      path = File.join(root, relative)
      File.file?(path) ? path : nil
    end

    # Query STUDIO's own path authority over the executable boundary. MASTER
    # must not load STUDIO/output_paths.rb as a sibling implementation.
    def output_path(kind:, at: Time.now.utc)
      command = OUTPUT_PATH_COMMANDS.fetch(kind.to_sym) do
        raise ArgumentError, "unknown STUDIO output path kind: #{kind.inspect}"
      end
      script = dilla_script or raise "STUDIO Dilla entrypoint is unavailable"

      argv = [RbConfig.ruby, script, "output-path", command]
      argv << at.utc.iso8601 if kind.to_sym == :dilla_render_directory
      output, status = run_bounded(argv, chdir: root, timeout: OUTPUT_PATH_TIMEOUT)
      unless status.success?
        detail = output.lines.last(5).join.strip
        raise "STUDIO output-path failed: #{detail.empty? ? "exit #{status.exitstatus}" : detail}"
      end

      paths = output.lines.map(&:strip).reject(&:empty?)
      raise "STUDIO output-path returned #{paths.length} paths; expected exactly one" unless paths.one?

      path = paths.fetch(0)
      raise "STUDIO output-path returned a relative path" unless path.start_with?(File::SEPARATOR)

      path
    end

    def photograph(prompt:, film: false, duration: 5)
      script = photograph_script or raise "STUDIO photograph entrypoint is unavailable"
      argv = [RbConfig.ruby, script]
      argv << "--film" if film
      argv.concat(["--duration", duration.to_i.to_s, prompt.to_s])
      output, status = run_bounded(argv, chdir: root)
      raise "STUDIO photograph failed: #{output.lines.last.to_s.strip}" unless status.success?

      JSON.parse(output)
    end

    def run_bounded(argv, chdir:, timeout: PHOTOGRAPH_TIMEOUT)
      output = +""
      status = nil

      Open3.popen2e(*argv, chdir:) do |stdin, io, wait|
        stdin.close
        reader = Thread.new { output = io.read.to_s }

        unless wait.join(timeout)
          begin
            Process.kill("TERM", wait.pid)
          rescue Errno::ESRCH
          end

          unless wait.join(5)
            begin
              Process.kill("KILL", wait.pid)
            rescue Errno::ESRCH
            end
            wait.join
          end
        end

        reader.join
        status = wait.value
      end

      [output, status]
    end
  end
end
