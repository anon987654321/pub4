# frozen_string_literal: true

# Enhanced Filesystem Utilities - Migrated from ai3_old/lib/filesystem_tool.rb
# Comprehensive file operations with OpenBSD security compliance

require 'fileutils'

module FileSystemUtils
  class FilesystemTool
    def initialize
      # Initialize with OpenBSD security awareness
    end

    # List all files and directories within the specified path
    def list_directory(path)
      validate_path_exists(path)
      Dir.entries(path) - ['.', '..']
    end

    # Read the contents of a file
    def read_file(file_path)
      validate_file_exists(file_path)
      File.read(file_path)
    end

    # Write content to a file, create file if it does not exist
    def write_file(file_path, content)
      File.write(file_path, content)
    end

    # Append content to a file
    def append_to_file(file_path, content)
      File.open(file_path, 'a') do |file|
        file.write(content)
      end
    end

    # Delete a specified file with validation
    def delete_file(file_path)
      validate_file_exists(file_path)
      File.delete(file_path)
    end

    # Create a new directory
    def create_directory(path)
      Dir.mkdir(path) unless Dir.exist?(path)
    end

    # Delete a specified directory if it is empty
    def delete_directory(path)
      validate_directory_exists(path)
      Dir.rmdir(path)
    end

    # Recursively delete a directory and its contents
    def delete_directory_recursive(path)
      validate_directory_exists(path)
      FileUtils.rm_rf(path)
    end

    # Copy a file from source to destination
    def copy_file(source, destination)
      validate_file_exists(source)
      FileUtils.copy(source, destination)
    end

    # Move a file from source to destination
    def move_file(source, destination)
      validate_file_exists(source)
      FileUtils.mv(source, destination)
    end

    # Enhanced: Check if path exists (file or directory)
    def path_exists?(path)
      File.exist?(path) || Dir.exist?(path)
    end

    # Enhanced: Get file size
    def file_size(file_path)
      validate_file_exists(file_path)
      File.size(file_path)
    end

    # Enhanced: Get file permissions
    def file_permissions(file_path)
      validate_file_exists(file_path)
      File.stat(file_path).mode.to_s(8)
    end

    # Enhanced: Set file permissions (OpenBSD compliant)
    def set_file_permissions(file_path, mode)
      validate_file_exists(file_path)
      File.chmod(mode, file_path)
    end

    # Enhanced: Get directory listing with details
    def detailed_directory_listing(path)
      validate_path_exists(path)
      entries = []
      Dir.entries(path).each do |entry|
        next if ['.', '..'].include?(entry)

        full_path = File.join(path, entry)
        stat = File.stat(full_path)
        entries << {
          name: entry,
          type: File.directory?(full_path) ? 'directory' : 'file',
          size: stat.size,
          permissions: stat.mode.to_s(8),
          modified: stat.mtime
        }
      end
      entries
    end

    # Enhanced: Safe file operations with backup
    def safe_write_file(file_path, content, create_backup: true)
      if create_backup && File.exist?(file_path)
        backup_path = "#{file_path}.backup.#{Time.now.to_i}"
        copy_file(file_path, backup_path)
      end
      write_file(file_path, content)
    end

    private

    # Utility method to validate if a path exists
    def validate_path_exists(path)
      raise "Path does not exist: #{path}" unless Dir.exist?(path)
    end

    # Utility method to validate if a file exists
    def validate_file_exists(file_path)
      raise "File does not exist: #{file_path}" unless File.exist?(file_path)
    end

    # Utility method to validate if a directory exists
    def validate_directory_exists(path)
      raise "Directory does not exist: #{path}" unless Dir.exist?(path)
    end
  end
end

# Maintain backward compatibility
class FilesystemTool < FileSystemUtils::FilesystemTool
end
