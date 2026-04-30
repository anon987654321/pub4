# frozen_string_literal: true

module MASTER
  module UI
    # Utilities - screen info and tool lookup
    module Utilities
      def screen_width
        @screen_width ||= begin
          require "tty-screen"
          TTY::Screen.width
        rescue LoadError
          80
        end
      end

      def screen_height
        @screen_height ||= begin
          require "tty-screen"
          TTY::Screen.height
        rescue LoadError
          24
        end
      end

      def platform
        @platform ||= begin
          require "tty-platform"
          TTY::Platform.new
        rescue LoadError
          Object.new.tap do |p|
            p.define_singleton_method(:os) { RbConfig::CONFIG["host_os"] }
            p.define_singleton_method(:cpu) { RbConfig::CONFIG["host_cpu"] }
            p.define_singleton_method(:arch) { RbConfig::CONFIG["arch"] }
          end
        end
      end

      def which(cmd)
        require "tty-which"
        TTY::Which.which(cmd)
      rescue LoadError
        ENV["PATH"].split(":").each do |dir|
          path = File.join(dir, cmd)
          return path if File.executable?(path)
        end
        nil
      end
    end
  end
end
