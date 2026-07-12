#!/usr/bin/env ruby
# frozen_string_literal: true

AUTH_COLS = [
  '    t.string "remember_token"',
  '    t.datetime "remember_token_expires_at"',
  '    t.string "magic_link_token"',
  '    t.datetime "magic_link_expires_at"',
  '    t.datetime "deletion_scheduled_at"',
  '    t.datetime "deleted_at"',
  '    t.string "otp_secret"',
  '    t.boolean "two_factor_enabled", default: false, null: false'
].freeze

AUTH_IDX = [
  '    t.index ["remember_token"], name: "index_users_on_remember_token", unique: true',
  '    t.index ["magic_link_token"], name: "index_users_on_magic_link_token", unique: true',
  '    t.index ["deletion_scheduled_at"], name: "index_users_on_deletion_scheduled_at"'
].freeze

ROOT = File.expand_path("..", __dir__)

%w[amber brgen bsdports].each do |app|
  path = File.join(ROOT, app, "db", "schema.rb")
  lines = File.readlines(path)
  next if lines.any? { |line| line.include?("remember_token") }

  start = lines.index { |line| line.include?('create_table "users"') }
  abort "users table missing in #{path}" unless start

  email_idx = lines.index.with_index(start) { |line, _| line.include?('t.index ["email_address"]') }
  abort "email index missing in #{path}" unless email_idx

  insert = AUTH_COLS + AUTH_IDX
  lines.insert(email_idx, *insert.map { |line| "#{line}\n" })
  File.write(path, lines.join)
  puts "updated #{path}"
end
