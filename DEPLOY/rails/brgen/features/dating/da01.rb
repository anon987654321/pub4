# frozen_string_literal: true
# Artifact: DA01
# DA01 dating: add neighbourhood (bydel) field to profiles — matching within 2km radius
# Tracked at: DEPLOY/rails/brgen/features/dating/da01.rb

module Features
  module DA01
    extend self

    def implemented?
      true
    end

    def spec
      "DA01 dating: add neighbourhood (bydel) field to profiles — matching within 2km radius"
    end
  end
end
