# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"

module Contracts
  module Studio
    module_function

    def root
      value = ENV["PUB4_STUDIO_ROOT"].to_s.strip
      return File.expand_path(value) unless value.empty?

      File.expand_path("../../STUDIO", __dir__)
    end

    def photograph_script = first_file("photograph.rb")

    def photograph(prompt:, film: false, duration: 5)
      script = photograph_script or raise "STUDIO photograph entrypoint is unavailable"
      argv = [RbConfig.ruby, script]
      argv << "--film" if film
      argv.concat(["--duration", duration.to_i.to_s, prompt.to_s])
      stdout, status = Open3.capture2e(*argv, chdir: root)
      raise "STUDIO photograph failed: #{stdout.lines.last.to_s.strip}" unless status.success?

      JSON.parse(stdout)
    end

    def dilla_script = first_file("dilla/dilla.rb")
    def postpro_script = first_file("postpro/postpro.rb")
    def replicate_script = first_file("replicate/replicate.rb")
    def sonic_reference = first_file("dilla/data/reference_sonic.yml")

    def first_file(relative)
      path = File.join(root, relative)
      File.file?(path) ? path : nil
    end
  end
end
