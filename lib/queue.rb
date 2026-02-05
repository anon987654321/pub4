# frozen_string_literal: true

module MASTER
  class Queue
    attr_reader :items, :completed, :failed, :current

    def initialize
      @items = []
      @completed = []
      @failed = []
      @current = nil
      @paused = false
      @budget = nil
      @spent = 0.0
      @checkpoint_file = File.join(Paths.data, 'queue_checkpoint.json')
    end

    def add(item, priority: 0)
      @items << { item: item, priority: priority, added_at: Time.now }
      @items.sort_by! { |i| -i[:priority] }
      self
    end

    # Alias for compatibility
    alias push add
    alias << add

    def add_files(pattern, priority: 0)
      files = Dir.glob(pattern).select { |f| File.file?(f) }
      files = files.reject { |f| binary?(f) }
      files.each { |f| add(f, priority: priority) }
      self
    end

    def add_directory(path, extensions: %w[.rb .py .js .ts .sh .yml], recursive: true)
      pattern = recursive ? File.join(path, '**', '*') : File.join(path, '*')
      files = Dir.glob(pattern).select { |f| File.file?(f) }
      files = files.select { |f| extensions.include?(File.extname(f)) }
      files = files.reject { |f| binary?(f) }
      files = files.sort_by { |f| File.size(f) } # smallest first
      files.each { |f| add(f) }
      self
    end

    def set_budget(max_cost)
      @budget = max_cost
      self
    end

    def next
      return nil if @paused
      return nil if @budget && @spent >= @budget

      @current = @items.shift
      @current&.dig(:item)
    end

    def complete(cost: 0.0)
      return unless @current

      @spent += cost
      @completed << @current.merge(completed_at: Time.now, cost: cost)
      @current = nil
      save_checkpoint
    end

    def fail(error)
      return unless @current

      @failed << @current.merge(failed_at: Time.now, error: error.to_s)
      @current = nil
      save_checkpoint
    end

    def pause
      @paused = true
      save_checkpoint
    end

    def resume
      @paused = false
    end

    def progress
      total = @items.size + @completed.size + @failed.size + (@current ? 1 : 0)
      done = @completed.size
      {
        total: total,
        done: done,
        failed: @failed.size,
        remaining: @items.size,
        percent: total.zero? ? 100 : (done * 100.0 / total).round(1),
        spent: @spent,
        budget: @budget
      }
    end

    def status
      p = progress
      budget_str = @budget ? " / $#{'%.2f' % @budget} budget" : ""
      "#{p[:done]}/#{p[:total]} (#{p[:percent]}%) | $#{'%.4f' % p[:spent]}#{budget_str} | #{p[:remaining]} remaining"
    end

    def save_checkpoint
      data = {
        items: @items,
        completed: @completed,
        failed: @failed,
        paused: @paused,
        budget: @budget,
        spent: @spent,
        saved_at: Time.now.iso8601
      }
      FileUtils.mkdir_p(File.dirname(@checkpoint_file))
      File.write(@checkpoint_file, JSON.pretty_generate(data))
    end

    def load_checkpoint
      return false unless File.exist?(@checkpoint_file)

      data = JSON.parse(File.read(@checkpoint_file), symbolize_names: true)
      @items = data[:items] || []
      @completed = data[:completed] || []
      @failed = data[:failed] || []
      @paused = data[:paused] || false
      @budget = data[:budget]
      @spent = data[:spent] || 0.0
      true
    rescue JSON::ParserError
      false
    end

    def clear_checkpoint
      File.delete(@checkpoint_file) if File.exist?(@checkpoint_file)
    end

    def reset
      @items = []
      @completed = []
      @failed = []
      @current = nil
      @paused = false
      @spent = 0.0
      clear_checkpoint
    end

    private

    def binary?(file)
      return true if File.size(file) > 1_000_000
      return true if %w[.png .jpg .gif .mp4 .pdf .so .dylib .exe .dll .zip .gz].include?(File.extname(file).downcase)

      begin
        chunk = File.read(file, 8192)
        chunk&.include?("\x00")
      rescue
        true
      end
    end
  end
end
