# frozen_string_literal: true

module PostproBootstrap
  def self.dmesg(msg)
    puts "[postpro] #{msg}"
  end

  def self.startup_banner
    ruby_version = RUBY_VERSION
    os = RbConfig::CONFIG["host_os"]
    dmesg "boot ruby=#{ruby_version} os=#{os}"
  end

  def self.ensure_gems
    vips_available = ensure_vips
    tty_available = ensure_tty_prompt
    dmesg "vipsgem=#{vips_available} tty=#{tty_available}"
    { vips: vips_available, tty: tty_available }
  end

  def self.ensure_vips
    require "vips"
    true
  rescue LoadError
    dmesg "WARN ruby-vips gem missing, attempting install..."
    begin
      if system("gem install ruby-vips --no-document")
        require "vips"
        dmesg "OK ruby-vips gem installed"
        true
      else
        dmesg "WARN ruby-vips install failed"
        probe_and_install_libvips
        false
      end
    rescue => e
      dmesg "WARN ruby-vips unavailable: #{e.message}"
      false
    end
  end

  def self.ensure_tty_prompt
    require "tty-prompt"
    true
  rescue LoadError
    dmesg "WARN tty-prompt gem missing, attempting install..."
    begin
      if system("gem install tty-prompt --no-document")
        require "tty-prompt"
        dmesg "OK tty-prompt gem installed"
        true
      else
        dmesg "WARN tty-prompt install failed, degraded prompt experience"
        false
      end
    rescue => e
      dmesg "WARN tty-prompt unavailable: #{e.message}"
      false
    end
  end

  def self.probe_and_install_libvips
    dmesg "probing libvips installation..."
    if system("pkg-config --exists vips 2>/dev/null")
      dmesg "OK libvips already installed"
      return true
    end

    dmesg "WARN libvips not found, attempting installation..."
    os = RbConfig::CONFIG["host_os"]
    success = case os
    when /openbsd/
      if system("which pkg_add > /dev/null 2>&1")
        dmesg "attempting: doas pkg_add vips"
        system("doas pkg_add vips") || system("pkg_add vips")
      else
        dmesg "ERROR pkg_add not found"
        false
      end
    when /darwin/
      if system("which brew > /dev/null 2>&1")
        dmesg "attempting: brew install vips"
        system("brew install vips")
      else
        dmesg "ERROR homebrew not found, install manually: brew install vips"
        false
      end
    when /linux/
      if system("which apt > /dev/null 2>&1")
        dmesg "attempting: apt install libvips-dev libvips42"
        system("sudo apt update && sudo apt install -y libvips-dev libvips42")
      elsif system("which dnf > /dev/null 2>&1")
        dmesg "attempting: dnf install vips-devel"
        system("sudo dnf install -y vips-devel")
      elsif system("which yum > /dev/null 2>&1")
        dmesg "attempting: yum install vips-devel"
        system("sudo yum install -y vips-devel")
      elsif system("which apk > /dev/null 2>&1")
        dmesg "attempting: apk add vips-dev"
        system("sudo apk add vips-dev")
      elsif system("which pacman > /dev/null 2>&1")
        dmesg "attempting: pacman -S libvips"
        system("sudo pacman -S --noconfirm libvips")
      else
        dmesg "ERROR no supported package manager found"
        false
      end
    else
      dmesg "ERROR unsupported OS: #{os}"
      puts "\nManual installation required:"
      puts "  macOS:   brew install vips"
      puts "  Ubuntu:  sudo apt install libvips-dev libvips42"
      puts "  OpenBSD: doas pkg_add vips"
      puts "  Arch:    sudo pacman -S libvips"
      puts "\nDocs: https://libvips.github.io/libvips/install.html"
      false
    end

    if system("pkg-config --exists vips 2>/dev/null")
      dmesg "OK libvips installation successful"
      true
    else
      dmesg "ERROR libvips installation failed"
      puts "\n❌ libvips installation failed!"
      puts "Please install manually:"
      puts "  OpenBSD: doas pkg_add vips"
      puts "  macOS:   brew install vips"
      puts "  Ubuntu:  sudo apt install libvips-dev libvips42"
      false
    end
  end

  def self.load_camera_profiles(profiles_path)
    profiles = {}
    unless Dir.exist?(profiles_path)
      dmesg "WARN camera profiles directory not found: #{profiles_path}"
      return profiles
    end

    Dir.glob(File.join(profiles_path, "*.json")).each do |file|
      begin
        data = JSON.parse(File.read(file))
        vendor = data["vendor"]
        if vendor && data["profiles"]
          profiles[vendor] = data["profiles"]
        end
      rescue => e
        dmesg "WARN failed to load profile #{File.basename(file)}: #{e.message}"
      end
    end

    brands = profiles.keys.join(",")
    dmesg "camera_profiles=#{brands.empty? ? 'none' : brands}"
    profiles
  end

  def self.load_master_config
    return {} unless File.exist?("master.json")

    begin
      master = JSON.parse(File.read("master.json").gsub(/^.*\/\/.*$/, ""))
      config = master.dig("config", "multimedia", "postpro") || {}
      dmesg "OK loaded defaults from master.json"
      config
    rescue => e
      dmesg "WARN failed to parse master.json: #{e.message}"
      {}
    end
  end

  def self.run
    startup_banner
    gems = ensure_gems
    unless gems[:vips]
      dmesg "FATAL libvips unavailable - image processing impossible"
      puts "\nPostpro.rb requires libvips for image processing."
      puts "Installation failed. Please install manually:"
      puts "  macOS: brew install vips"
      puts "  Ubuntu/Debian: sudo apt install libvips-dev"
      puts "  OpenBSD: doas pkg_add vips"
      exit 1
    end

    profiles_path = "camera_profiles"
    camera_profiles = load_camera_profiles(profiles_path)
    config = load_master_config
    { gems: gems, camera_profiles: camera_profiles, config: config }
  end
end
