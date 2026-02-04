# frozen_string_literal: true
module Master
  class Result
    attr_reader :value, :error
    def initialize(ok:, value: nil, error: nil)
      @ok, @value, @error = ok, value, error
    end
    def ok? = @ok
    def err? = !@ok
    def self.ok(value = nil) = new(ok: true, value: value)
    def self.err(error) = new(ok: false, error: error)
  end
end
