# frozen_string_literal: true

require "date"
require "yaml"

module Shared
  class ChangelogController < ::ApplicationController
    include ActionController::Rendering

    # The shared engine is namespace-isolated, so a controller in it sees the
    # engine's route set, while the application layout it renders links to the
    # host's routes (new_session_path). Without the host's helpers in its views
    # the layout raised NameError and the page was a 500.
    helper Rails.application.routes.url_helpers

    allow_unauthenticated_access only: :show

    def show
      @changelog = YAML.safe_load_file(
        Shared::Engine.root.join("config/changelog.yml"),
        # Each entry's `date:` is an unquoted YAML date, which loads as a Date. With
        # no permitted classes safe_load raised DisallowedClass on every request.
        permitted_classes: [Date],
        aliases: false
      )
      render template: "shared/changelog", layout: "application"
    end
  end
end
