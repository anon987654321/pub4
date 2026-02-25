# frozen_string_literal: true

module MASTER
  module Mode
    OPS      = :ops
    REFACTOR = :refactor
    CHAT     = :chat
    DOC      = :doc
    CREATIVE = :creative

    ALL = [OPS, REFACTOR, CHAT, DOC, CREATIVE].freeze

    module_function

    def valid?(mode)
      ALL.include?(mode)
    end
  end
end
