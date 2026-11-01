# frozen_string_literal: true

# Keep media deliverables outside the checkout. Producers and Postpro share
# this path contract instead of guessing output locations.
module Studio
  module OutputPaths
    FALLBACK_DATA_HOME = File.expand_path("~/Downloads").freeze
    REPOSITORY_ROOT = File.realpath(File.expand_path("..", __dir__)).freeze

    module_function

    def data_home
      configured = ENV.fetch("XDG_DATA_HOME", "").to_s
      return fallback_data_home if configured.empty?
      return fallback_data_home unless configured.start_with?(File::SEPARATOR)

      candidate = canonical_path(configured)
      return fallback_data_home if inside_repository?(candidate)

      candidate
    end

    # Even the fallback must be safe: Downloads can itself be a symlink into
    # the checkout. Refuse that rare configuration rather than writing renders
    # into the repository under the guise of a fallback.
    def fallback_data_home(path = FALLBACK_DATA_HOME)
      if inside_repository?(path)
        raise ArgumentError, "fallback data home resolves inside the checkout: #{path}"
      end

      path
    end

    def canonical_path(path)
      expanded = File.expand_path(path)
      cursor = expanded
      missing = []
      until File.exist?(cursor) || File.symlink?(cursor)
        parent = File.dirname(cursor)
        break if parent == cursor

        missing.unshift(File.basename(cursor))
        cursor = parent
      end
      File.join(File.realpath(cursor), *missing)
    rescue SystemCallError
      expanded
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
      canonical = canonical_path(path)
      canonical == REPOSITORY_ROOT ||
        canonical.start_with?("#{REPOSITORY_ROOT}#{File::SEPARATOR}")
    end
  end
end
