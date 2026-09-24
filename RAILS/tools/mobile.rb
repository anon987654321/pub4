# frozen_string_literal: true

require "fileutils"
require_relative "../shared/lib/shared/mobile_app_registry"

module MobileTool
  ROOT = File.expand_path("../..", __dir__)
  ANDROID_ROOT = ENV.fetch("MOBILE_ANDROID_BUILD_ROOT", File.join(ROOT, "__NATIVE_ANDROID", ".build"))
  IOS_ROOT = ENV.fetch("MOBILE_IOS_BUILD_ROOT", File.join(ROOT, "__NATIVE_IOS", ".build"))

  module_function

  def run(argv)
    command = argv.shift
    case command
    when "list"
      Shared::MobileAppRegistry.all.each do |app|
        puts "#{app.key}\t#{app.name}\t#{app.url}\t#{app.android_package}\t#{app.ios_bundle_id}"
      end
    when "android"
      init_android(registry_app!(argv.shift))
    when "ios"
      write_ios_target(registry_app!(argv.shift))
    when "all"
      Shared::MobileAppRegistry.all.each { |app| write_ios_target(app) }
      puts "ios: generated #{Shared::MobileAppRegistry.all.size} target configs"
    else
      warn "usage: ruby tools/mobile.rb list | android APP | ios APP | all"
      exit 64
    end
  end

  def registry_app!(key)
    Shared::MobileAppRegistry.fetch(key)
  rescue KeyError => e
    warn e.message
    exit 64
  end

  def init_android(app)
    directory = File.join(ANDROID_ROOT, app.key.to_s)
    FileUtils.mkdir_p(directory)
    command = [
      "npx", "@bubblewrap/cli", "init",
      "--manifest=#{app.url}manifest.json",
      "--directory=#{directory}"
    ]
    puts "android: #{app.key}: #{command.join(" ")}"
    exec(*command)
  end

  def write_ios_target(app)
    directory = File.join(IOS_ROOT, app.key.to_s)
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, "build.settings.xcconfig"), <<~XC)
      PRODUCT_BUNDLE_IDENTIFIER = #{app.ios_bundle_id}
      MOBILE_APP_URL = #{app.url}
      MOBILE_APP_HOST = #{app.host}
      MOBILE_APP_NAME = #{app.name}
      DEVELOPMENT_TEAM = $(#{app.ios_team_id_env})
    XC
    File.write(File.join(directory, "README.md"), <<~MD)
      #{app.name}

      Bundle ID: #{app.ios_bundle_id}
      Origin: #{app.url}
      Associated domain: applinks:#{app.host}

      This target uses the shared source under __NATIVE_IOS/Sources.
      Keep product identity here; do not fork the shell.
    MD
    puts "ios: #{app.key}: #{directory}"
  end
end

MobileTool.run(ARGV)
