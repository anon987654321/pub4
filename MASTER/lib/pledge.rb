# frozen_string_literal: true

require "fiddle"

module MASTER
  module Pledge
    class PledgeError < RuntimeError; end

    def self.available?
      RUBY_PLATFORM.include?("openbsd")
    end

    def self.pledge(promises, execpromises = nil)
      raise PledgeError, "pledge(2) is only available on OpenBSD" unless available?

      libc = Fiddle.dlopen(nil)
      pledge_func = libc["pledge"]
      
      promises_ptr = Fiddle::Pointer[promises]
      execpromises_ptr = execpromises ? Fiddle::Pointer[execpromises] : nil
      
      result = Fiddle::Function.new(
        pledge_func,
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      ).call(promises_ptr, execpromises_ptr)
      
      raise PledgeError, "pledge(2) failed with code #{result}" if result != 0
    end

    def self.unveil(path, permissions)
      raise PledgeError, "unveil(2) is only available on OpenBSD" unless available?

      libc = Fiddle.dlopen(nil)
      unveil_func = libc["unveil"]
      
      path_ptr = path ? Fiddle::Pointer[path] : nil
      permissions_ptr = permissions ? Fiddle::Pointer[permissions] : nil
      
      result = Fiddle::Function.new(
        unveil_func,
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      ).call(path_ptr, permissions_ptr)
      
      raise PledgeError, "unveil(2) failed with code #{result}" if result != 0
    end

    def self.lock_unveil
      unveil(nil, nil)
    end
  end
end
