# frozen_string_literal: true

require "sqlite3"

module MASTER
  module DB
    class << self
      attr_reader :connection

      def setup(path: "#{MASTER.root}/master.db")
        @mutex = Mutex.new
        @connection = SQLite3::Database.new(path)
        @connection.results_as_hash = true
        Schema.migrate!(@connection)
        Seeds.run(@connection)
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end
    end
  end
end
