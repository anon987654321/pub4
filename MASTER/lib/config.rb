require 'dotenv/load'

module MASTER
  module Config
    def self.load
      Dotenv.load
    end
  end
end
