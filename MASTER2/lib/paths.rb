# frozen_string_literal: true

module MASTER
  module Paths
    def self.var
      File.join(MASTER.root, "var")
    end

    def self.tmp
      File.join(MASTER.root, "tmp")
    end

    def self.data
      File.join(MASTER.root, "data")
    end
  end
end
