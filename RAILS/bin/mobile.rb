# frozen_string_literal: true

require "fileutils"
require_relative "../shared/lib/shared/mobile_app_registry"
require_relative "../shared/lib/shared/mobile_ios_project"

module MobileTool
  ROOT = File.expand_path("../..", __dir__)
  ANDROID_ROOT = ENV.fetch("MOBILE_ANDROID_BUILD_ROOT", File.join(ROOT, "RAILS", "mobile", "android", ".build"))
  IOS_ROOT = ENV.fetch("MOBILE_IOS_BUILD_ROOT", File.join(ROOT, "RAILS", "mobile", "ios", ".build"))

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
      registry_app!(argv.shift) if argv.first
      generate_ios_project
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

  def generate_ios_project
    directory = IOS_ROOT
    FileUtils.mkdir_p(directory)
    spec = File.join(directory, "project.yml")
    Shared::MobileIosProject.write(spec)

    unless system("xcodegen", "--version", out: File::NULL, err: File::NULL)
      warn "ios: xcodegen is required; install it with brew install xcodegen"
      exit 69
    end

    ok = system(
      "xcodegen", "generate",
      "--spec", spec,
      "--project", directory
    )
    exit 1 unless ok

    puts "ios: generated #{File.join(directory, "Pub4Mobile.xcodeproj")}"
  end
end

MobileTool.run(ARGV)
