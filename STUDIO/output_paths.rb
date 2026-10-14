# frozen_string_literal: true

# The external render directory is shared by media producers and must have one
# implementation so a consumer never guesses where another tool wrote a file.
module Studio
  module OutputPaths
    module_function

    def render_directory(at: Time.now.utc)
      configured = ENV.fetch("POSTPRO_OUTPUT_DIR", "").to_s
      return File.expand_path(configured) unless configured.empty?

      base = ENV.fetch("XDG_DATA_HOME", "").to_s
      base = File.expand_path("~/Documents") if base.empty?
      File.expand_path(File.join(base, "dilla-renders", at.strftime("%Y-%m-%d")))
    end
  end
end
