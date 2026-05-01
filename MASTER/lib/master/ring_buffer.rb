# frozen_string_literal: true

module Master
  class RingBuffer
    include Enumerable
    include MonitorMixin

    def initialize(capacity)
      super()
      @capacity = capacity
      @buf      = Array.new(capacity)
      @start    = 0
      @size     = 0
    end

    def push(item)
      synchronize do
      write_pos = (@start + @size) % @capacity
      if @size < @capacity
        @buf[write_pos] = item
        @size += 1
      else
        @buf[@start] = item
        @start = (@start + 1) % @capacity
      end
      end
      self
    end

    alias << push

    def each
      return enum_for(__method__) unless block_given?
      synchronize { @size.times { |i| yield @buf[(@start + i) % @capacity] } }
    end

    def to_a    = @size.times.map { |i| @buf[(@start + i) % @capacity] }
    def size    = @size
    def full?   = @size == @capacity
    def empty?  = @size.zero?

    def clear
      @start = @size = 0
      self
    end
  end
end
