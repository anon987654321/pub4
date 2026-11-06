# frozen_string_literal: true

# Purge recursive digest output before Propshaft compiles (Falcon boot wedge).
Rails.application.config.before_initialize do
  nested = Rails.root.join("public", "assets", "assets")
  raise "propshaft safety: refusing symlinked digest output: #{nested}" if File.symlink?(nested)

  if nested.exist?
    raise "propshaft safety: expected a directory at #{nested}" unless nested.directory?

    FileUtils.rm_rf(nested)
  end
end
