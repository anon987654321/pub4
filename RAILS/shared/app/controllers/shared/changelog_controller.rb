# frozen_string_literal: true

require "yaml"

module Shared
  class ChangelogController < ::ApplicationController
    include ActionController::Rendering

    allow_unauthenticated_access only: :show

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
