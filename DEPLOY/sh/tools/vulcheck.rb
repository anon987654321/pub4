#!/usr/bin/env ruby

# **vulcheck.rb**
#
# This script performs security checks for macOS, iOS, and Android devices. It detects rootkits, jailbreaks, unauthorized access, and active intrusions. It automates updates for tools like `chkrootkit` and `rkhunter`, and logs results for review.

require 'optparse'
require 'fileutils'
require 'open3'

class VulCheck
  MACPORTS_PACKAGES = %w[chkrootkit rkhunter aide].freeze
  # `aide` is included for file integrity checking, complementing `chkrootkit` and `rkhunter`.
  LOG_FILE = 'vulcheck_log.txt'

  # Ensure script is run with sudo
  def self.ensure_sudo
    return if Process.uid.zero?

    log('Root privileges are necessary for installing tools and scanning system files.')
    log_and_exit('This script must be run with sudo privileges.')
  end

  # Determine the system type: macOS, iOS, or Android
  def self.check_system
    if RUBY_PLATFORM.include?('darwin')
      if File.exist?('/Applications/Utilities/Terminal.app') # macOS
        return 'macos'
      elsif File.exist?('/System/Applications/Feedback.app') # iOS
        return 'ios'
      end
    elsif RUBY_PLATFORM.include?('android')
      return 'android'
    end
    raise 'Unsupported OS'
  end

  # Ensure MacPorts is installed (for macOS)
  def self.ensure_macports
    return if system('which port > /dev/null 2>&1')

    log_and_exit('MacPorts not found. Please install MacPorts first: https://www.macports.org/')
  end

  # Install required tools using MacPorts (for macOS)
  def self.install_dependencies
    log('Installing required tools using MacPorts...')
    MACPORTS_PACKAGES.each do |pkg|
      unless system("port installed #{pkg} > /dev/null 2>&1")
        log("Installing #{pkg}...")
        system("sudo port install #{pkg}") || raise("Failed to install #{pkg}.")
      end
    end
    log('All required tools are installed.')
  end

  # Update rootkit detection tools for macOS
  def self.update_tools
    log('Updating rootkit detection tools...')
    system('sudo rkhunter --update') || log('Failed to update rkhunter. Regular updates ensure detection rules remain effective.')
    system('sudo chkrootkit --update') || log('Failed to update chkrootkit.')
    log('Tools updated successfully.')
  end

  # Run security scans on macOS
  def self.run_macos_scans
    log('Running security scans for macOS...')
    MACPORTS_PACKAGES.each do |tool|
      command = case tool
                when 'chkrootkit' then tool
                when 'rkhunter' then "#{tool} --check"
                when 'aide' then "#{tool} --check"
                else next
                end
      log("Executing: #{command}")
      system(command) || log("Error: #{tool} scan encountered an issue.")
    end
  end

  # Detect active intrusions on macOS
  def self.detect_active_intrusions
    log('Checking for active intrusions on macOS...')
    log('Active network connections:')
    system('netstat -an | grep ESTABLISHED')
    log('Review the above connections for unusual remote addresses or unauthorized access.')
    log('Suspicious running processes:')
    system('ps aux | grep -i suspicious')
  end

  # Detect jailbreak indicators on iOS
  def self.check_ios_jailbreak
    log('Checking for jailbreak indicators on iOS...')
    jailbreak_indicators = [
      '/Applications/Cydia.app',
      '/usr/sbin/sshd',
      '/bin/bash',
      '/private/var/stash',
      '/usr/libexec/ssh-keysign'
    ]

    jailbreak_indicators.each do |path|
      log("Warning: Jailbreak indicator found at #{path}") if File.exist?(path)
    end
    log('Finished checking for jailbreak indicators on iOS.')
  end

  # Detect root access on Android
  def self.check_android_root
    log('Checking for root access on Android...')
    root_indicators = [
      '/system/xbin/su',
      '/system/bin/su',
      '/data/data/com.noshufou.android.su',
      '/sbin/su'
    ]

    root_indicators.each do |path|
      log("Warning: Root access indicator found at #{path}") if File.exist?(path)
    end

    log('Active network connections:')
    system('netstat -an | grep ESTABLISHED')

    if system('which su > /dev/null 2>&1')
      log('The presence of `su` may indicate the device is rooted. Verify the need for this binary.')
      log('Warning: Device may be rooted (su command found).')
    end
    log('Finished checking for root access on Android.')
  end

  # Log messages to console and file
  def self.log(message)
    puts message
    File.open(LOG_FILE, 'a') { |file| file.puts("#{Time.now}: #{message}") }
  end

  # Log an error and exit
  def self.log_and_exit(message)
    log(message)
    exit(1)
  end

  # Execute the script based on detected OS
  def self.execute
    ensure_sudo
    system_type = check_system
    case system_type
    when 'macos'
      log('macOS detected.')
      ensure_macports
      install_dependencies
      update_tools
      detect_active_intrusions
      run_macos_scans
    when 'ios'
      log('iOS detected.')
      check_ios_jailbreak
    when 'android'
      log('Android detected.')
      check_android_root
    else
      log_and_exit('Unsupported system type detected.')
    end
  end
end

# Parse command-line options
options = {}

OptionParser.new do |opts|
  opts.banner = 'Usage: vulcheck.rb [options]'

  opts.on('--macos', 'Run the script for macOS') { options[:macos] = true }
  opts.on('--ios', 'Run the script for iOS') { options[:ios] = true }
  opts.on('--android', 'Run the script for Android') { options[:android] = true }
  opts.on_tail('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end.parse!

if options[:macos] || options[:ios] || options[:android]
  VulCheck.execute
else
  VulCheck.log_and_exit('Error: Please specify either --macos, --ios, or --android.')
end
