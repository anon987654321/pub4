# lib/tools/filesystem_tool.rb
#
# FilesystemTool: Provides safe file reading and writing.
#
# Usage:
#   fs = FilesystemTool.new
#   content = fs.read("file.txt")
#   fs.write("file.txt", "Some content")

require "logger"

class FilesystemTool
  def initialize
    @logger = Logger.new(STDOUT)
  end

  def read(file_path)
    File.read(file_path)
  rescue Errno::ENOENT => e
    @logger.error("File not found: #{file_path} – #{e.message}")
    nil
  rescue StandardError => e
    @logger.error("Error reading file #{file_path}: #{e.message}")
    nil
  end

  def write(file_path, content)
    File.write(file_path, content)
    @logger.info("Wrote content to #{file_path}")
    true
  rescue StandardError => e
    @logger.error("Error writing to file #{file_path}: #{e.message}")
    false
  end

  # Execute method provides a unified interface.
  # Defaults to "read" if no explicit action is provided.
  def execute(action = "read", *args)
    case action.downcase
    when "read"
      read(args.first)
    when "write"
      write(args.first, args[1])
    else
      "Unknown action"
    end
  end
end

