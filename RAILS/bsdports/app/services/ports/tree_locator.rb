# frozen_string_literal: true

require "pathname"

module Ports
  class TreeLocator
    SKIP_ROOTS = %w[CVS distfiles packages templates .git].freeze

    def self.resolve(platform:, override: nil)
      candidate = override.presence || platform.tree_path.presence || ENV["BSDPORTS_TREE_PATH"]
      return nil if candidate.blank?

      path = Pathname.new(candidate)
      path.directory? ? path : nil
    end

    def self.each_port(tree_root)
      root = Pathname.new(tree_root)
      return enum_for(:each_port, tree_root) unless block_given?

      root.children.select(&:directory?).each do |category_path|
        category = category_path.basename.to_s
        next if SKIP_ROOTS.include?(category)

        category_path.children.select(&:directory?).each do |port_path|
          makefile = port_path.join("Makefile")
          yield(category, port_path.basename.to_s, makefile) if makefile.file?
        end
      end
    end
  end
end
