module MASTER
  module InfoDesign
    def self.collapsible(title, content, expanded = false)
      icon = expanded ? "▼" : "▶"
      header = "#{icon} #{title}"
      expanded ? [header, "  #{content}"].join("\n") : header
    end
    
    def self.search_bar(query = "")
      "🔍 Search: #{query}_"
    end
    
    def self.status_bar(location, items = [])
      status_items = items.join(" | ")
      "#{location} #{status_items}"
    end
    
    ICONS = {
      file: "📄", folder: "📁", success: "✓", error: "✗", 
      warning: "⚠", info: "ℹ", help: "?", search: "🔍"
    }.freeze
  end
end
