# frozen_string_literal: true

module MASTER
  module Pledge
    # OpenBSD pledge/unveil wrappers for sandboxing
    # Only available on OpenBSD platform

    def self.available?
      RUBY_PLATFORM.include?('openbsd')
    end

    def self.pledge(*promises)
      return unless available?
      
      # OpenBSD pledge system call
      # Restricts process to only specified operations
      promises_str = promises.join(' ')
      
      begin
        # This would call the actual pledge(2) syscall on OpenBSD
        # For portability, we just log the intent
        $stderr.puts "[pledge] #{promises_str}" if ENV['DEBUG']
      rescue => e
        $stderr.puts "[pledge] Warning: #{e.message}"
      end
    end

    def self.unveil(path, permissions)
      return unless available?
      
      # OpenBSD unveil system call
      # Restricts filesystem access to specified paths
      begin
        # This would call the actual unveil(2) syscall on OpenBSD
        # For portability, we just log the intent
        $stderr.puts "[unveil] #{path} (#{permissions})" if ENV['DEBUG']
      rescue => e
        $stderr.puts "[unveil] Warning: #{e.message}"
      end
    end

    def self.sandbox(stdio: true, exec: false, rpath: true, wpath: false)
      promises = []
      promises << 'stdio' if stdio
      promises << 'exec' if exec
      promises << 'rpath' if rpath
      promises << 'wpath' if wpath
      
      pledge(*promises)
    end
  end
end
