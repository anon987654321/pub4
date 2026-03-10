module MASTER
  class Error < StandardError; end

  class SchemaMissing < Error
    def message
      "executor schema missing — run `master doctor`"
    end
  end

  class ToolMissing < Error
    def message
      "tool registry not initialized"
    end
  end
end
