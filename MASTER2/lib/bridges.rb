# frozen_string_literal: true

module Bridges
  BRIDGES = {
    # Add bridge mappings here, e.g.:
    # "github" => Bridges::GitHub,
    # "slack"  => Bridges::Slack
  }.freeze

  def self.bridges
    BRIDGES
  end

  def self.fetch(key)
    BRIDGES.fetch(key)
  end

  def self.[](key)
    BRIDGES[key]
  end
end