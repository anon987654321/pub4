#!/usr/bin/env ruby
# frozen_string_literal: true

require "socket"

errors = []
hostname = Socket.gethostname
errors << "not running as root (uid=#{Process.uid})" unless Process.uid.zero?
errors << "hostname missing" if hostname.nil? || hostname.empty?
errors << "repo path missing" unless File.directory?(File.expand_path("../..", __dir__))
errors << "/etc/master.env missing" unless File.exist?("/etc/master.env")

if errors.any?
  warn "deploy identity check failed: #{errors.join('; ')}"
  exit 1
end

puts "deploy identity ok: host=#{hostname} uid=#{Process.uid}"
