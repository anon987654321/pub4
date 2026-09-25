# frozen_string_literal: true

require "yaml"
require_relative "mobile_app_registry"

module Shared
  module MobileIosProject
    module_function

    def spec
      apps = MobileAppRegistry.all
      {
        "name" => "Pub4Mobile",
        "options" => {
          "deploymentTarget" => { "iOS" => "16.0" },
          "developmentLanguage" => "en",
          "xcodeVersion" => "26.0",
          "minimumXcodeGenVersion" => "2.46.0"
        },
        "configs" => apps.to_h { |app| [ config_name(app), "release" ] },
        "targets" => { "Pub4Mobile" => target(apps) },
        "schemes" => apps.to_h { |app| [ config_name(app), scheme(config_name(app)) ] }
      }
    end

    # One application target; each registry app is a build configuration of it.
    def target(apps)
      {
        "type" => "application",
        "platform" => "iOS",
        "sources" => [{ "path" => "../Pub4MobileApp.swift" }],
        "settings" => {
          "base" => {
            "SWIFT_VERSION" => "5.0",
            "GENERATE_INFOPLIST_FILE" => "NO",
            "INFOPLIST_FILE" => "../Info.plist",
            "CODE_SIGN_ENTITLEMENTS" => "../Pub4Mobile.entitlements",
            "CODE_SIGN_STYLE" => "Automatic",
            "MARKETING_VERSION" => "1.0.0",
            "CURRENT_PROJECT_VERSION" => "1"
          },
          "configs" => apps.to_h { |app| [ config_name(app), app_settings(app) ] }
        }
      }
    end

    def app_settings(app)
      {
        "PRODUCT_BUNDLE_IDENTIFIER" => app.ios_bundle_id,
        "MOBILE_APP_URL" => app.url,
        "MOBILE_APP_HOST" => app.host,
        "MOBILE_APP_NAME" => app.name
      }
    end

    def scheme(name)
      {
        "build" => { "targets" => { "Pub4Mobile" => "all" } },
        "run" => { "config" => name },
        "archive" => { "config" => name }
      }
    end

    def config_name(app)
      app.key.to_s.split("_").map(&:capitalize).join
    end

    def write(path)
      File.write(path, YAML.dump(spec))
    end
  end
end
