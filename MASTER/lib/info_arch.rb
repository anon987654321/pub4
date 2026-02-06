# frozen_string_literal: true

module MASTER
  # Information Architecture module
  # Implements hierarchy, breadcrumbs, and progressive disclosure
  module InfoArch
    # Hierarchical navigation breadcrumbs
    class Breadcrumb
      attr_reader :path
      
      def initialize
        @path = []
      end
      
      def push(item)
        @path << item
      end
      
      def pop
        @path.pop
      end
      
      def current
        @path.last
      end
      
      def to_s
        @path.join(' → ')
      end
      
      def depth
        @path.length
      end
    end
    
    # Progressive disclosure state manager
    class Disclosure
      def initialize
        @expanded = {}
        @collapsed = {}
      end
      
      def expand(key)
        @expanded[key] = true
        @collapsed.delete(key)
      end
      
      def collapse(key)
        @collapsed[key] = true
        @expanded.delete(key)
      end
      
      def expanded?(key)
        @expanded.key?(key)
      end
      
      def collapsed?(key)
        @collapsed.key?(key)
      end
      
      def toggle(key)
        if expanded?(key)
          collapse(key)
        else
          expand(key)
        end
      end
    end
    
    # Information hierarchy with proper indentation
    class Hierarchy
      attr_reader :root
      
      def initialize(title)
        @root = Node.new(title, level: 0)
        @current = @root
      end
      
      def add_child(title, **attrs)
        child = Node.new(title, level: @current.level + 1, **attrs)
        @current.add_child(child)
        child
      end
      
      def descend(&block)
        prev = @current
        @current = @current.children.last || @current
        yield if block_given?
        @current = prev
      end
      
      def render(max_width: 72)
        lines = []
        render_node(@root, lines, max_width: max_width)
        lines.join("\n")
      end
      
      private
      
      def render_node(node, lines, indent: '', max_width: 72)
        # Render node title
        prefix = indent + (node.level == 0 ? '' : '• ')
        title = wrap_text(node.title, max_width - prefix.length)
        
        lines << prefix + title.first
        title[1..-1]&.each { |line| lines << indent + '  ' + line }
        
        # Render node content if any
        if node.content
          content_lines = wrap_text(node.content, max_width - indent.length - 2)
          content_lines.each { |line| lines << indent + '  ' + line }
        end
        
        # Render children with increased indentation
        node.children.each do |child|
          child_indent = indent + '  '
          render_node(child, lines, indent: child_indent, max_width: max_width)
        end
      end
      
      def wrap_text(text, width)
        return [text] if text.length <= width
        
        words = text.split(' ')
        lines = []
        current = ''
        
        words.each do |word|
          if (current + ' ' + word).length <= width
            current += (current.empty? ? '' : ' ') + word
          else
            lines << current unless current.empty?
            current = word
          end
        end
        
        lines << current unless current.empty?
        lines
      end
      
      class Node
        attr_reader :title, :level, :children, :content, :metadata
        
        def initialize(title, level:, content: nil, **metadata)
          @title = title
          @level = level
          @children = []
          @content = content
          @metadata = metadata
        end
        
        def add_child(node)
          @children << node
        end
      end
    end
    
    # Context-aware help system
    class ContextHelp
      def initialize
        @help_texts = {}
      end
      
      def register(context, text)
        @help_texts[context] = text
      end
      
      def get(context)
        @help_texts[context]
      end
      
      def available?(context)
        @help_texts.key?(context)
      end
    end
    
    # Smart search with scoped results
    class ScopedSearch
      def initialize(scope)
        @scope = scope
        @indices = {}
      end
      
      def index(key, content)
        words = tokenize(content)
        words.each do |word|
          @indices[word] ||= []
          @indices[word] << key unless @indices[word].include?(key)
        end
      end
      
      def search(query)
        words = tokenize(query)
        return [] if words.empty?
        
        # Find documents containing all query words
        results = words.map { |w| @indices[w] || [] }
        common = results.reduce(:&) || []
        
        # Score by frequency
        scored = common.map do |key|
          score = words.sum { |w| (@indices[w] || []).count(key) }
          { key: key, score: score }
        end
        
        scored.sort_by { |r| -r[:score] }.map { |r| r[:key] }
      end
      
      private
      
      def tokenize(text)
        text.downcase
            .gsub(/[^a-z0-9\s]/, ' ')
            .split
            .select { |w| w.length > 2 }
            .uniq
      end
    end
    
    # Pagination helper
    class Paginator
      attr_reader :page, :per_page, :total
      
      def initialize(total:, per_page: 20, page: 1)
        @total = total
        @per_page = per_page
        @page = [[page, 1].max, total_pages].min
      end
      
      def total_pages
        (@total.to_f / @per_page).ceil
      end
      
      def offset
        (@page - 1) * @per_page
      end
      
      def limit
        @per_page
      end
      
      def has_next?
        @page < total_pages
      end
      
      def has_prev?
        @page > 1
      end
      
      def next_page
        has_next? ? @page + 1 : @page
      end
      
      def prev_page
        has_prev? ? @page - 1 : @page
      end
      
      def range
        start = offset
        finish = [start + @per_page - 1, @total - 1].min
        (start..finish)
      end
      
      def to_s
        "Page #{@page}/#{total_pages} (#{@total} total)"
      end
    end
  end
end
