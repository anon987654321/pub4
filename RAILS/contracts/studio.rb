# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"

module Contracts
  module Studio
    PHOTOGRAPH_TIMEOUT = Integer(ENV.fetch("STUDIO_PHOTOGRAPH_TIMEOUT", "120"))

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
    def sonic_reference = first_file("dilla/data/reference_sonic.yml")

    def first_file(relative)
      path = File.join(root, relative)
      File.file?(path) ? path : nil
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

    def run_bounded(argv, chdir:)
      output = +""
      status = nil

      Open3.popen2e(*argv, chdir:) do |stdin, io, wait|
        stdin.close
        reader = Thread.new { output = io.read.to_s }

        unless wait.join(PHOTOGRAPH_TIMEOUT)
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
