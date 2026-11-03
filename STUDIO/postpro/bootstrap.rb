# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../subprocess"
require "rbconfig"
require "time"

BOOT_TIME = Time.now.freeze

module PostproBootstrap
  def self.dmesg(msg)
    elapsed = defined?(BOOT_TIME) ? " +%.3fs" % (Time.now - BOOT_TIME) : ""
    # FATAL is in this list because it was not, and the one message that uses
    # it — libvips unavailable, on the line before `exit 1` — printed as
    # "postpro: ok: FATAL libvips unavailable".
    tag = if msg.start_with?("ERROR", "error", "FATAL", "fatal")
            "fix:"
          elsif msg.start_with?("WARN", "warn")
            "warn:"
          else
            "ok:"
          end
    text = msg.sub(/\A(?:OK|WARN|ERROR|FATAL)\s+/i, "")
    $stdout.puts "postpro#{elapsed}: #{tag} #{text}"
    $stdout.flush
  end

  def self.startup_banner
    dmesg "ruby#{RUBY_VERSION} os=#{RbConfig::CONFIG["host_os"]} pid=#{Process.pid}"
  end

  # Whether installing is allowed at all.
  #
  # This is conditional. Unconditional, with `BOOTSTRAP = PostproBootstrap.run`
  # running at file scope, *loading* postpro.rb can `gem install ruby-vips`, and on a
  # miss go on to `brew install vips`, `apt install libvips-dev` or
  # `doas pkg_add -I libvips`. STUDIO's own check loads this file to check that it
  # boots, which made `rake check` a command that could mutate the machine it was
  # supposed to be measuring. A check observes; it does not repair.
  #
  # Default is observe. POSTPRO_INSTALL_DEPS=1 opts in, and `rake
  # postpro:bootstrap` is the spelling meant for a human. Never inferred from a
  # tty: the check's probe inherits one when rake is run from a terminal, which
  # would put the mutation right back under the check.
  def self.install_allowed? = ENV["POSTPRO_INSTALL_DEPS"] == "1"

  def self.ensure_gems
    vips_available = ensure_vips
    tty_available = ensure_tty_prompt

    dmesg "vipsgem=#{vips_available} tty=#{tty_available} install=#{install_allowed?}"
    { vips: vips_available, tty: tty_available }
  end

  def self.ensure_vips
    require "vips"
    true
  rescue LoadError
    unless install_allowed?
      dmesg "WARN ruby-vips gem missing — `rake postpro:bootstrap` installs it, " \
            "or POSTPRO_INSTALL_DEPS=1 to allow it from here"
      return false
    end

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
    rescue StandardError => e
      dmesg "WARN ruby-vips unavailable: #{e.message}"
      false
    end
  end

  def self.ensure_tty_prompt
    require "tty-prompt"
    true
  rescue LoadError
    unless install_allowed?
      dmesg "WARN tty-prompt gem missing — degraded prompt experience; " \
            "`rake postpro:bootstrap` installs it"
      return false
    end

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
    rescue StandardError => e
      dmesg "WARN tty-prompt unavailable: #{e.message}"
      false
    end
  end

  def self.probe_and_install_libvips
    dmesg "probing libvips installation..."

    if system("pkg-config", "--exists", "vips", out: File::NULL, err: File::NULL)
      dmesg "OK libvips already installed"
      return true
    end

    # Detect package manager and attempt install
    os = RbConfig::CONFIG["host_os"]
    case os
    when /darwin/
      if Studio::Subprocess.on_path?("brew")
        dmesg "attempting: brew install vips"
        system("brew", "install", "vips")
      else
        dmesg "ERROR homebrew not found, install manually: brew install vips"
      end
    when /linux/
      if Studio::Subprocess.on_path?("apt")
        dmesg "attempting: apt install libvips-dev"
        system("apt", "update") && system("apt", "install", "-y", "libvips-dev")
      elsif Studio::Subprocess.on_path?("dnf")
        dmesg "attempting: dnf install vips-devel"
        system("dnf", "install", "-y", "vips-devel")
      elsif Studio::Subprocess.on_path?("yum")
        dmesg "attempting: yum install vips-devel"
        system("yum", "install", "-y", "vips-devel")
      elsif Studio::Subprocess.on_path?("apk")
        dmesg "attempting: apk add vips-dev"
        system("apk", "add", "vips-dev")
      elsif Studio::Subprocess.on_path?("pacman")
        dmesg "attempting: pacman -S libvips"
        system("pacman", "-S", "--noconfirm", "libvips")
      else
        dmesg "ERROR no supported package manager found"
      end
    when /openbsd/
      if Studio::Subprocess.on_path?("pkg_add")
        dmesg "attempting: pkg_add libvips"
        if Process.uid.zero?
          system("pkg_add", "-I", "libvips")
        elsif Studio::Subprocess.on_path?("doas")
          system("doas", "-n", "pkg_add", "-I", "libvips")
        else
          dmesg "ERROR pkg_add needs root or doas"
        end
      else
        dmesg "ERROR pkg_add not found"
      end
    else
      dmesg "ERROR unsupported OS: #{os}"
    end

    # Verify installation
    if system("pkg-config", "--exists", "vips", out: File::NULL, err: File::NULL)
      dmesg "OK libvips installation successful"
      true
    else
      dmesg "ERROR libvips installation failed"
      false
    end
  end

  # One file keyed by vendor, each vendor's bodies keyed by EXIF model.
  def self.load_camera_profiles(profiles_path)
    unless File.file?(profiles_path)
      dmesg "WARN camera profiles not found: #{profiles_path}"
      return {}
    end

    profiles = begin
      JSON.parse(File.read(profiles_path))
    rescue StandardError => e
      dmesg "WARN failed to load #{File.basename(profiles_path)}: #{e.message}"
      {}
    end

    brands = profiles.keys.join(",")
    dmesg "camera_profiles=#{brands.empty? ? 'none' : brands}"
    profiles
  end

  # Anchored to this file, for the same reason the camera profiles and
  # REPLICATE_PATH are: `File.exist?("master.json")` asked the shell's working
  # directory, which is wherever the operator happened to be standing. It has
  # therefore been false on every invocation, so CONFIG has always been {} and
  # all twelve `CONFIG[...]` reads in this file have always taken their
  # fallback — including apply_camera_profile_first, which is the switch for
  # get_camera_profile and apply_camera_profile, fifty lines that have never
  # run. The same defect was found and fixed one screen below this, twice, and
  # left here.
  #
  # POSTPRO_CONFIG overrides, so a config can live somewhere other than beside
  # the script without moving the script.
  def self.master_config_path
    File.expand_path(ENV.fetch("POSTPRO_CONFIG", File.join(__dir__, "master.json")))
  end

  def self.load_master_config
    path = master_config_path
    return {} unless File.exist?(path)

    begin
      # Whole-line // comments only: a pattern matching // anywhere on the line
      # also erased every line carrying a URL in a string value.
      master = JSON.parse(File.read(path).gsub(%r{^\s*//.*$}, ""))
      config = master.dig("config", "multimedia", "postpro") || {}
      dmesg "OK loaded defaults from #{path}"
      config
    rescue StandardError => e
      dmesg "WARN failed to parse #{path}: #{e.message}"
      {}
    end
  end

  def self.run
    startup_banner
    gems = ensure_gems

    unless gems[:vips]
      dmesg "FATAL libvips unavailable; macOS: brew install vips; Ubuntu: apt install libvips-dev; OpenBSD: doas pkg_add -I libvips"
      exit 1
    end

    # Anchored to this file, not to the shell's working directory, for the same
    # reason as REPLICATE_PATH below: a relative path finds the profiles only
    # from the one directory nobody runs from.
    profiles_path = File.expand_path("camera_profiles.json", __dir__)
    camera_profiles = load_camera_profiles(profiles_path)
    config = load_master_config

    {
      gems:,
      camera_profiles:,
      config:,
    }
  end
end
