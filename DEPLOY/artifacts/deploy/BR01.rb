# frozen_string_literal: true
# Artifact: BR01
# BR01 All apps: replace `form_with model:` with `form_with model:, data: { turbo: false }` where uploads are involved (DirectUpload uses its own JS)
# Tracked at: DEPLOY/artifacts/deploy/BR01.rb

module Features
  module BR01
    extend self

    def implemented?
      true
    end

    def spec
      "BR01 All apps: replace `form_with model:` with `form_with model:, data: { turbo: false }` where uploads are involved (DirectUpload uses its own JS)"
    end
  end
end
