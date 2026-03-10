# frozen_string_literal: true

require "fiddle/import"

module Master3
  module Pledge
    extend self

    if RUBY_PLATFORM.include?("openbsd")
      extend Fiddle::Importer
      dlload "libc.so"
      extern "int pledge(const char *, const char *)"
      extern "int unveil(const char *, const char *)"

      def pledge(promises, execpromises = nil)
        result = self.__pledge(promises, execpromises)
        raise SystemCallError.new("pledge failed", Fiddle.last_error) if result == -1
      end

      def unveil(path, permissions)
        result = self.__unveil(path, permissions)
        raise SystemCallError.new("unveil failed", Fiddle.last_error) if result == -1
      end

      def lock_unveil! = unveil(nil, nil)
    else
      def pledge(*) = nil
      def unveil(*) = nil
      def lock_unveil! = nil
    end

    def apply!
      pledge("stdio rpath wpath cpath proc exec inet")
      unveil(".", "rwc")
      unveil("/tmp", "rwc")
      unveil("/usr/bin", "rx")
      unveil("/usr/local/bin", "rx")
      lock_unveil!
    end
  end
end
