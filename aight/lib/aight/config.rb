# frozen_string_literal: true
require "yaml"

require "fileutils"
require "logger"
require "io/console"

# Cross-platform utilities

class PlatformDetector

  def self.platform_name
    host_os = RbConfig::CONFIG["host_os"]

    return :openbsd if host_os =~ /openbsd/

    return :cygwin if host_os =~ /cygwin/

    return :termux if ENV["PREFIX"] == "/data/data/com.termux/files/usr"

    return :windows if host_os =~ /mswin|mingw/

    return :macos if host_os =~ /darwin/

    return :linux if host_os =~ /linux/

    :unknown

  end

  def self.shell_command_prefix

    %i[windows cygwin].include?(platform_name) ? "cmd /c" : ""

  end
end

class CrossPlatformPath

  def self.home_directory

    ENV["HOME"] || ENV["USERPROFILE"] || Dir.pwd
  end

  def self.config_directory

    case PlatformDetector.platform_name

    when :windows, :cygwin
      File.join(home_directory, "AppData", "Roaming", "crc")

    when :termux

      prefix = ENV["PREFIX"] || "/data/data/com.termux/files/usr"

      File.join(prefix, "etc", "crc")

    else

      xdg_config = ENV["XDG_CONFIG_HOME"] || File.join(home_directory, ".config")

      File.join(xdg_config, "crc")

    end

  end

  def self.config_file

    File.join(config_directory, "config.yml")

  end
  def self.ensure_config_directory

    FileUtils.mkdir_p(config_directory)

  end
end

class AtomicFileWriter

  def self.write(filepath, content)

    temp_path = "#{filepath}.tmp.#{Process.pid}.#{Time.now.to_i}"
    begin

      File.open(temp_path, "w") do |temp_file|

        temp_file.write(content)
        temp_file.fsync if temp_file.respond_to?(:fsync)

      end

      File.rename(temp_path, filepath)

      true

    rescue => e
      File.unlink(temp_path) if File.exist?(temp_path)

      raise e

    end

  end

end

# Configuration management

class Configuration

  DEFAULT_CONFIG = {
    "anthropic_api_key" => nil,

    "openai_api_key" => nil,

    "github_token" => nil,

    "default_model" => "anthropic",

    "max_file_size" => 100_000,

    "excluded_dirs" => [".git", "node_modules", "vendor", "tmp"],

    "supported_extensions" => [".rb", ".py", ".js", ".ts", ".md", ".yml", ".yaml"],

    "log_level" => "INFO",

    "autonomous_mode" => false,

    "working_directory" => Dir.pwd,

    "cognitive_tracking" => true,

    "knowledge_store" => true

  }.freeze

  def self.load

    CrossPlatformPath.ensure_config_directory

    config_file = CrossPlatformPath.config_file
    File.exist?(config_file) ? (YAML.load_file(config_file) || DEFAULT_CONFIG.dup) : DEFAULT_CONFIG.dup

  rescue => e

    puts "Config error: #{e.message}"
    DEFAULT_CONFIG.dup

  end

  def self.save(config)

    AtomicFileWriter.write(CrossPlatformPath.config_file, config.to_yaml)

  end
end

# Console utilities

class Console

  def self.print_header(text)
    puts

    puts "=" * 60

    puts "  #{text}"

    puts "=" * 60

    puts

  end

  def self.print_status(type, text)

    symbols = { success: "*", error: "!", warning: "-", info: ">" }

    puts "#{symbols[type]} #{text}"
  end

  %i[success error warning info].each do |type|

    define_singleton_method("print_#{type}") { |text| print_status(type, text) }

  end
  def self.ask(prompt, default: nil)

    prompt_text = default ? "#{prompt} [#{default}]" : prompt

    print "#{prompt_text}: "
    input = $stdin.gets.chomp

    input.empty? ? default : input

  end

  def self.ask_password(prompt)

    print "#{prompt}: "

    password = $stdin.noecho(&:gets).chomp
    puts

    password

  end

  def self.ask_yes_no(prompt, default: true)

    default_text = default ? "[Y/n]" : "[y/N]"

    print "#{prompt} #{default_text}: "
    input = $stdin.gets.chomp.downcase

    return default if input.empty?

    input.start_with?("y")

  end

  def self.select_option(prompt, options)

    puts prompt

    puts
    options.each_with_index { |option, i| puts "  #{i + 1}. #{option}" }

    loop do

      print "\nSelect (1-#{options.length}): "

      input = $stdin.gets.chomp.to_i
      return options[input - 1] if input.between?(1, options.length)

      print_error("Invalid choice")

    end

  end

  def self.pause(message = "Press Enter...")

    print message

    $stdin.gets
  end

  def self.clear_screen

    system("clear") || system("cls")

  end
  def self.spinner(message)

    chars = %w[| / - \\]

    i = 0
    thread = Thread.new do

      loop do

        print "\r#{chars[i % chars.length]} #{message}"
        i += 1

        sleep(0.1)

      end

    end

    yield if block_given?

    thread.kill

    print "\r* #{message}\n"
  end

end

# Logger setup

class CLILogger

  def self.setup(level = "INFO")
    logger = Logger.new($stdout)

    logger.level = Logger.const_get(level.upcase)

    logger.formatter = proc { |severity, datetime, progname, msg| "[#{datetime.strftime("%H:%M:%S")}] #{severity}: #{msg}\n" }

    logger

  end

end

