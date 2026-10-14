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
      repo_root = File.expand_path("..", __dir__)
      base_path = File.expand_path(base) unless base.empty?
      inside_repo = base_path == repo_root ||
                    (base_path && base_path.start_with?("#{repo_root}#{File::SEPARATOR}"))
      if base.empty? || !base.start_with?(File::SEPARATOR) || inside_repo
        base = File.expand_path("~/Documents")
      else
        base = base_path
      end
      File.join(base, "dilla-renders", at.strftime("%Y-%m-%d"))
    end
  end
end
