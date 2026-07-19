# frozen_string_literal: true

# Purge recursive digest output before Propshaft compiles (Falcon boot wedge).
Rails.application.config.before_initialize do
  nested = Rails.root.join("public", "assets", "assets")
  FileUtils.rm_rf(nested) if nested.exist?
end