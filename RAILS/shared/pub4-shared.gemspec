# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "pub4-shared"
  spec.version = "0.1.0"
  spec.authors = ["pub4"]
  spec.summary = "Shared Rails engine for pub4 family apps"
  spec.files = Dir["{app,config,db,frontend,lib,public,vendor}/**/*", "README.md", "WIRING_NOTES.md", "test/**/*"].select { |f| File.file?(f) }
  spec.metadata = { "sass_load_path" => "app/assets/stylesheets" }
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "pundit", ">= 2.3"
  spec.add_dependency "rotp", ">= 6.3"
  spec.add_dependency "rqrcode", ">= 2.2"
  spec.add_dependency "omniauth", ">= 2.1"
  spec.add_dependency "omniauth-google-oauth2", ">= 1.1"
  spec.add_dependency "omniauth-github", ">= 2.0"
  spec.add_dependency "omniauth-rails_csrf_protection", ">= 1.0"
  spec.add_dependency "webpush", ">= 1.1"
end