# frozen_string_literal: true

require 'fileutils'
require 'json'

module MASTER
  # Queue - Priority-based task queue with checkpoint persistence
  # Features: budget tracking, batch processing, pause/resume, binary filtering
  # Ported from MASTER v1, adapted for MASTER2's Paths and Result monad
  class Queue
    attr_reader :items, :completed, :failed, :current

    def initialize(checkpoint_file: nil)
      @items = []
      @completed = []
      @failed = []
      @current = nil
      @paused = false
      @budget = nil
      @spent = 0.0
      @checkpoint_file = checkpoint_file || File.join(Paths.data, 'queue_checkpoint.json')
    end

    # Add item to queue with optional priority (higher = processed first)
    def add(item, priority: 0)
      @items << { item: item, priority: priority, added_at: Time.now }
      @items.sort_by! { |i| -i[:priority] }
      self
    end

    # Alias for compatibility
    alias push add
    alias << add

    # Add files matching glob pattern
    def add_files(pattern, priority: 0)
      files = Dir.glob(pattern).select { |f| File.file?(f) }
      files = files.reject { |f| binary?(f) }
      files.each { |f| add(f, priority: priority) }
      self
    end

    # Add all files from directory with optional filters
    def add_directory(path, extensions: %w[.rb .py .js .ts .sh .yml .yaml], recursive: true)
      pattern = recursive ? File.join(path, '**', '*') : File.join(path, '*')
      files = Dir.glob(pattern).select { |f| File.file?(f) }
      files = files.select { |f| extensions.include?(File.extname(f)) }
      files = files.reject { |f| binary?(f) }
      files = files.sort_by { |f| File.size(f) } # smallest first
      files.each { |f| add(f) }
      self
    end

    # Set budget limit in dollars
    def set_budget(max_cost)
      @budget = max_cost
      self
    end

    # Get next item from queue (respects pause and budget)
    def next
      return nil if @paused
      return nil if @budget && @spent >= @budget

      @current = @items.shift
      @current&.dig(:item)
    end

    # Mark current item as completed
    def complete(cost: 0.0)
      return unless @current

      @spent += cost
      @completed << @current.merge(completed_at: Time.now, cost: cost)
      @current = nil
      save_checkpoint
    end

    # Mark current item as failed
    def fail(error)
      return unless @current

      @failed << @current.merge(failed_at: Time.now, error: error.to_s)
      @current = nil
      save_checkpoint
    end

    # Pause processing
    def pause
      @paused = true
      save_checkpoint
    end

    # Resume processing
    def resume
      @paused = false
    end

    # Get progress statistics
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

    # Get human-readable status string
    def status
      p = progress
      budget_str = @budget ? " / $#{'%.2f' % @budget} budget" : ""
      "#{p[:done]}/#{p[:total]} (#{p[:percent]}%) | $#{'%.4f' % p[:spent]}#{budget_str} | #{p[:remaining]} remaining"
    end

    # Save checkpoint to disk
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
      Result.ok("Checkpoint saved")
    rescue StandardError => e
      Result.err("Failed to save checkpoint: #{e.message}")
    end

    # Load checkpoint from disk
    def load_checkpoint
      return Result.err("Checkpoint file not found") unless File.exist?(@checkpoint_file)

      data = JSON.parse(File.read(@checkpoint_file), symbolize_names: true)
      @items = data[:items] || []
      @completed = data[:completed] || []
      @failed = data[:failed] || []
      @paused = data[:paused] || false
      @budget = data[:budget]
      @spent = data[:spent] || 0.0
      Result.ok("Checkpoint loaded: #{status}")
    rescue JSON::ParserError => e
      Result.err("Failed to parse checkpoint: #{e.message}")
    rescue StandardError => e
      Result.err("Failed to load checkpoint: #{e.message}")
    end

    # Delete checkpoint file
    def clear_checkpoint
      File.delete(@checkpoint_file) if File.exist?(@checkpoint_file)
      Result.ok("Checkpoint cleared")
    rescue StandardError => e
      Result.err("Failed to clear checkpoint: #{e.message}")
    end

    # Reset queue to empty state
    def reset
      @items = []
      @completed = []
      @failed = []
      @current = nil
      @paused = false
      @spent = 0.0
      clear_checkpoint
    end

    # Check if queue is empty
    def empty?
      @items.empty? && @current.nil?
    end

    # Check if queue is paused
    def paused?
      @paused
    end

    # Check if budget is exceeded
    def over_budget?
      @budget && @spent >= @budget
    end

    # Get total cost spent
    def total_spent
      @spent
    end

    # Get remaining budget
    def budget_remaining
      @budget ? (@budget - @spent) : nil
    end

    private

    # Check if file is binary (to filter out non-text files)
    def binary?(file)
      # Size check
      return true if File.size(file) > 1_000_000

      # Extension check
      binary_extensions = %w[
        .png .jpg .jpeg .gif .bmp .ico .svg
        .mp4 .avi .mov .mkv .webm
        .mp3 .wav .ogg .flac
        .pdf .doc .docx .xls .xlsx .ppt .pptx
        .zip .tar .gz .bz2 .7z .rar
        .so .dylib .dll .exe .bin .o .a
        .ttf .otf .woff .woff2
        .sqlite .db .sqlite3
      ]
      return true if binary_extensions.include?(File.extname(file).downcase)

      # Content check - look for null bytes
      begin
        chunk = File.read(file, 8192)
        chunk&.include?("\x00")
      rescue StandardError
        true
      end
    end
  end
end
