# frozen_string_literal: true

module Master3
  module Platform
    extend self

    def openbsd? = RUBY_PLATFORM.include?("openbsd")
    def macos?   = RUBY_PLATFORM.include?("darwin")
    def linux?   = RUBY_PLATFORM.include?("linux")

    def privilege_command  = openbsd? ? "doas" : "sudo"
    def service_manager    = openbsd? ? "rcctl" : "systemctl"
    def package_manager    = openbsd? ? "pkg_add" : (macos? ? "brew" : "apt")
    def audio_player       = openbsd? ? "aucat" : (macos? ? "afplay" : "mpv")
  end
end
