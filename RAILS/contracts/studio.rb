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
