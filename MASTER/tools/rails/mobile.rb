# frozen_string_literal: true

require "fileutils"
require_relative "../../lib/io/exec"
require_relative "../../../RAILS/__shared/lib/shared/mobile_app_registry"
require_relative "../../../RAILS/__shared/lib/shared/mobile_ios_project"

module MobileTool
  ANDROID_ROOT = ENV.fetch("MOBILE_ANDROID_BUILD_ROOT", File.join(Dir.tmpdir, "pub4-mobile", "android"))
  IOS_ROOT = ENV.fetch("MOBILE_IOS_BUILD_ROOT", File.join(Dir.tmpdir, "pub4-mobile", "ios"))

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
      warn "usage: ruby MASTER/tools/rails/mobile.rb list | android APP | ios APP | all"
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
    output, status = Master::Io::Exec.capture2e(*command, timeout: 300)
    puts output unless output.to_s.empty?
    exit status.exitstatus || 1 unless status.success?
  end

  def generate_ios_project
    directory = IOS_ROOT
    FileUtils.mkdir_p(directory)
    spec = File.join(directory, "project.yml")
    Shared::MobileIosProject.write(spec)

    version_output, version_status = Master::Io::Exec.capture2e("xcodegen", "--version", timeout: 30)
    unless version_status.success?
      warn "ios: xcodegen is required; install it with brew install xcodegen"
      exit 69
    end

    output, status = Master::Io::Exec.capture2e(
      "xcodegen", "generate",
      "--spec", spec,
      "--project", directory,
      timeout: 120
    )
    puts version_output unless version_output.to_s.empty?
    puts output unless output.to_s.empty?
    exit status.exitstatus || 1 unless status.success?

    puts "ios: generated #{File.join(directory, "Pub4Mobile.xcodeproj")}"
  end
end

MobileTool.run(ARGV)
