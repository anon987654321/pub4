#!/usr/bin/env ruby
# frozen_string_literal: true

module MASTER
  # OpenBSD security wrappers
  # pledge(2) and unveil(2) for process restrictions
  module Pledge
    class << self
      # Apply pledge restrictions
      # On non-OpenBSD systems, this is a no-op
      def apply(promises)
        return unless openbsd?
        
        # Ruby doesn't have native pledge binding yet
        # This would require FFI or C extension
        # For now, document intent
        warn "pledge(#{promises})" if ENV['DEBUG']
      end

      # Apply unveil restrictions
      # On non-OpenBSD systems, this is a no-op
      def unveil(path, permissions)
        return unless openbsd?
        
        # Ruby doesn't have native unveil binding yet
        # This would require FFI or C extension
        warn "unveil(#{path}, #{permissions})" if ENV['DEBUG']
      end

      # Lock unveil (no more paths can be unveiled)
      def unveil_lock
        return unless openbsd?
        
        warn "unveil(NULL, NULL)" if ENV['DEBUG']
      end

      # Check if running on OpenBSD
      def openbsd?
        RUBY_PLATFORM.include?('openbsd')
      end

      # Sandbox helper for common patterns
      # Usage: Pledge.sandbox('stdio rpath', ['/etc', '/tmp']) { ... }
      def sandbox(promises, paths = [])
        paths.each { |p, perms| unveil(p, perms || 'r') }
        unveil_lock
        apply(promises)
        yield if block_given?
      end
    end
  end
end
