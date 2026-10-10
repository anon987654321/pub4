# frozen_string_literal: true

require "date"
require "yaml"

module Shared
  class ChangelogController < ::ApplicationController
    include ActionController::Rendering

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
