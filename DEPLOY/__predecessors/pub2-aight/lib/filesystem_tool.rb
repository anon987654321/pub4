# encoding: utf-8
# Filesystem tool for managing files

require "fileutils"
require "logger"
require "safe_ruby"

class FileSystemTool
  def initialize
    @logger = Logger.new(STDOUT)
  end

  def read_file(path)
    return "File not found or not readable" unless file_accessible?(path, :readable?)

    content = safe_eval("File.read(#{path.inspect})")
    log_action("read", path)
    content
  rescue => e
    handle_error("read", e)
  end

  def write_file(path, content)
    return "Permission denied" unless file_accessible?(path, :writable?)

    safe_eval("File.open(#{path.inspect}, 'w') {|f| f.write(#{content.inspect})}")
    log_action("write", path)
    "File written successfully"
  rescue => e
    handle_error("write", e)
  end

  def delete_file(path)
    return "File not found" unless File.exist?(path)

    safe_eval("FileUtils.rm(#{path.inspect})")
    log_action("delete", path)
    "File deleted successfully"
  rescue => e
    handle_error("delete", e)
  end

  private

  def file_accessible?(path, access_method)
    File.exist?(path) && File.public_send(access_method, path)
  end

  def safe_eval(command)
    SafeRuby.eval(command)
  end

  def log_action(action, path)
    @logger.info("#{action.capitalize} action performed on #{path}")
  end

  def handle_error(action, error)
    @logger.error("Error during #{action} action: #{error.message}")
    "Error during #{action} action: #{error.message}"
  end
end
