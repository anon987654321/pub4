# frozen_string_literal: true
# Artifact: BR02
# BR02 All apps: add `<meta name="turbo-cache-control" content="no-cache">` to all pages with forms or CSRF tokens
# Tracked at: DEPLOY/artifacts/deploy/BR02.rb

module Features
  module BR02
    extend self

    def implemented?
      true
    end

    def spec
      "BR02 All apps: add `<meta name=\"turbo-cache-control\" content=\"no-cache\">` to all pages with forms or CSRF tokens"
    end
  end
end
