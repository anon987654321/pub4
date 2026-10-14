# frozen_string_literal: true

# Keep photograph deliverables outside the checkout. The producer and its
# Postpro consumer share this path contract instead of guessing output locations.
module Studio
  module OutputPaths
    module_function

    def render_directory(at: Time.now.utc)
      configured = ENV.fetch("POSTPRO_OUTPUT_DIR", "").to_s
      return File.expand_path(configured) unless configured.empty?

      base = ENV.fetch("XDG_DATA_HOME", "").to_s
      if base.empty? || !base.start_with?(File::SEPARATOR)
        base = File.expand_path("~/Documents")
      end
      File.join(base, "dilla-renders", at.strftime("%Y-%m-%d"))
    end
  end
end
