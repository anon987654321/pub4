# frozen_string_literal: true

module Master
  class RingBuffer
    include Enumerable

    def initialize(capacity)
      @capacity = capacity
      @buf      = Array.new(capacity)
      @start    = 0
      @size     = 0
    end

    def push(item)
      idx = (@start + @size) % @capacity
      if @size < @capacity
        @buf[idx] = item
        @size += 1
      else
        @buf[@start] = item
        @start = (@start + 1) % @capacity
      end
      self
    end

    alias << push

    def each(&)
      @size.times { |i| yield @buf[(@start + i) % @capacity] }
    end

    def to_a = each.to_a
    def size  = @size
    def full? = @size == @capacity
    def empty? = @size.zero?
    def clear  = (@start = @size = 0) && self
  end
end
