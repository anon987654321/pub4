# frozen_string_literal: true

require "fiddle"

module MASTER
  module Pledge
    class Error < RuntimeError; end

    begin
      LIBC = Fiddle.dlopen(nil)
    rescue Fiddle::DLError
      LIBC = nil
    end

    def self.available? = RUBY_PLATFORM.include?("openbsd") && !LIBC.nil?

    def self.pledge(promises, execpromises = nil)
      raise Error, "pledge(2) unavailable on #{RUBY_PLATFORM}" unless available?

      fn = Fiddle::Function.new(
        LIBC["pledge"],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )
      r = fn.call(promises, execpromises)
      raise Error, "pledge(2) failed: errno #{Fiddle.last_error}" unless r.zero?
    end

    def self.unveil(path, permissions)
      raise Error, "unveil(2) unavailable on #{RUBY_PLATFORM}" unless available?

      fn = Fiddle::Function.new(
        LIBC["unveil"],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )
      r = fn.call(path, permissions)
      raise Error, "unveil(2) failed: errno #{Fiddle.last_error}" unless r.zero?
    end
  end
end
