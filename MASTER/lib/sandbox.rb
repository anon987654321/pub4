# frozen_string_literal: true
module Master
  module Sandbox
    def self.init
      return unless RUBY_PLATFORM =~ /openbsd/
      require "fiddle"
      libc = Fiddle.dlopen(nil)
      pledge = Fiddle::Function.new(libc["pledge"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      unveil = Fiddle::Function.new(libc["unveil"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      unveil.call(Dir.pwd, "rwc")
      unveil.call("/tmp", "rwc")
      unveil.call(nil, nil)
      pledge.call("stdio rpath wpath cpath inet dns proc exec", nil)
    rescue => e
      $stderr.puts "sandbox: #{e.message}"
    end
  end
end
