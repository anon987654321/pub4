# frozen_string_literal: true

module MASTER
  module UI
    def self.table(data, header: nil)
      require "tty-table"
      TTY::Table.new(header: header) { |t| data.each { |row| t << row } }
    rescue LoadError
      lines = []
      lines << header.join(" | ") if header
      data.each { |row| lines << row.join(" | ") }
      lines.join("\n")
    end
  end
end
