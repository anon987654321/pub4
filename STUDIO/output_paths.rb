# frozen_string_literal: true

# Keep media deliverables outside the checkout. Producers and Postpro share
# this path contract instead of guessing output locations.
module Studio
  module OutputPaths
    FALLBACK_DATA_HOME = File.expand_path("~/Documents").freeze
    REPOSITORY_ROOT = File.expand_path("..", __dir__).freeze

    module_function

    def data_home
      configured = ENV.fetch("XDG_DATA_HOME", "").to_s
      return FALLBACK_DATA_HOME if configured.empty?
      return FALLBACK_DATA_HOME unless configured.start_with?(File::SEPARATOR)

      candidate = File.expand_path(configured)
      return FALLBACK_DATA_HOME if inside_repository?(candidate)

      candidate
    end

    def directory(name, at: nil, override: nil)
      configured = override ? ENV.fetch(override, "").to_s : ""
      return File.expand_path(configured) unless configured.empty?

      path = File.join(data_home, name)
      at ? File.join(path, at.utc.strftime("%Y-%m-%d")) : path
    end

    def render_directory(at: Time.now.utc)
      directory("dilla-renders", at:, override: "POSTPRO_OUTPUT_DIR")
    end

    def dilla_render_directory(at: Time.now.utc)
      directory("dilla-renders", at:, override: "DILLA_OUTPUT_DIR")
    end

    def reference_root
      directory("dilla-references")
    end

    def inside_repository?(path)
      path == REPOSITORY_ROOT || path.start_with?("#{REPOSITORY_ROOT}#{File::SEPARATOR}")
    end
  end
end
