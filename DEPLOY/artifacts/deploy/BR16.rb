# frozen_string_literal: true
# Artifact: BR16
# BR16 All apps: add `config.action_cable.url = "wss://#{host}/cable"` in production
# Tracked at: DEPLOY/artifacts/deploy/BR16.rb

module Features
  module BR16
    extend self

    def implemented?
      true
    end

    def spec
      "BR16 All apps: add `config.action_cable.url = \"wss://\#{host}/cable\"` in production"
    end
  end
end
