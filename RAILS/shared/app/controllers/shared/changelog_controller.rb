# frozen_string_literal: true

module Shared
  class ChangelogController < ActionController::Base
    include ActionController::Rendering

    def show
      @changelog = YAML.safe_load_file(
        Shared::Engine.root.join("config/changelog.yml"),
        permitted_classes: [],
        aliases: false
      )
      render template: "shared/changelog", layout: "application"
    end
  end
end
