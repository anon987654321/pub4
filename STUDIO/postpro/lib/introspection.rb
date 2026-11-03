# frozen_string_literal: true

# postpro.rb and the lib/ files it loads, in load order, as one text. The
# source audits read methods by name, and a method lives in whichever file
# holds its subject.
def postpro_source
  POSTPRO_SOURCE_FILES.map { |path| File.read(path) }.join("\n")
end

# Source audits need exact method spans. Regexes around `end` either stop inside
# nested blocks or absorb comments/constants after a method. Prism is a default
# gem on the supported Ruby line, so a missing parser is a real checker failure.
def postpro_source_methods(source)
  require "prism"
  parsed = Prism.parse(source)
  raise ArgumentError, "postpro source audit could not parse its own source" unless parsed.success?

  parsed.value.statements.body.each_with_object({}) do |node, methods|
    next unless node.is_a?(Prism::DefNode)

    methods[node.name.to_s] = source.byteslice(node.location.start_offset...node.location.end_offset)
  end
end

def postpro_source_method(source, name)
  postpro_source_methods(source)[name.to_s]
end

def postpro_method_calls(body)
  require "prism"
  parsed = Prism.parse(body)
  raise ArgumentError, "postpro method source could not be parsed" unless parsed.success?

  definition = parsed.value.statements.body.first
  return [] unless definition.is_a?(Prism::DefNode)

  names = []
  pending = [definition.body].compact
  until pending.empty?
    node = pending.pop
    next if node.is_a?(Prism::DefNode)

    names << node.name.to_s if node.is_a?(Prism::CallNode) && node.receiver.nil?
    pending.concat(node.child_nodes.compact)
  end
  names.uniq
end

def postpro_method_reaches?(methods, from, target, seen: [], calls: nil)
  method_name = from.to_s
  return false if seen.include?(method_name)
  return false unless methods.key?(method_name)

  calls ||= methods.transform_values { |body| postpro_method_calls(body) }
  callees = calls.fetch(method_name, [])
  return true if callees.include?(target.to_s)

  callees.any? do |callee|
    methods.key?(callee) &&
      postpro_method_reaches?(methods, callee, target, seen: seen + [method_name], calls:)
  end
end

def postpro_case_label_duplicates(body, predicate_name)
  return [] unless body

  require "prism"
  parsed = Prism.parse(body)
  raise ArgumentError, "postpro case inventory could not parse its method" unless parsed.success?

  duplicates = []
  pending = [parsed.value]
  until pending.empty?
    node = pending.pop
    if node.is_a?(Prism::CaseNode) &&
       node.predicate.is_a?(Prism::LocalVariableReadNode) &&
       node.predicate.name == predicate_name.to_sym
      seen = {}
      node.conditions.each do |branch|
        next unless branch.is_a?(Prism::WhenNode)

        branch.conditions.each do |condition|
          next unless condition.is_a?(Prism::StringNode)

          label = condition.unescaped
          previous_branch = seen[label]
          duplicates << label if previous_branch && !previous_branch.equal?(branch)
          seen[label] ||= branch
        end
      end
    end
    pending.concat(node.child_nodes.compact)
  end
  duplicates.uniq
end

def postpro_case_labels(body, predicate_name)
  return [] unless body

  require "prism"
  parsed = Prism.parse(body)
  raise ArgumentError, "postpro case inventory could not parse its method" unless parsed.success?

  labels = []
  pending = [parsed.value]
  until pending.empty?
    node = pending.pop
    if node.is_a?(Prism::CaseNode) &&
       node.predicate.is_a?(Prism::LocalVariableReadNode) &&
       node.predicate.name == predicate_name.to_sym
      node.conditions.each do |branch|
        next unless branch.is_a?(Prism::WhenNode)

        branch.conditions.each do |condition|
          labels << condition.unescaped if condition.is_a?(Prism::StringNode)
        end
      end
    end
    pending.concat(node.child_nodes.compact)
  end
  labels.uniq
end

def preset_effect_names
  source = postpro_source
  postpro_case_labels(postpro_source_method(source, EFFECT_DISPATCH), :fx)
end

# A named step is not enough: the case arm must consume the value it promises
# to read. This catches a preset field that has a matching but disconnected FX.
# A preset key must be read by executable Ruby in the matching case arm.
# Prism excludes comments and strings, which source-text matching mistakes for code.
def postpro_node_reads_p_key?(root, key)
  pending = [root].compact
  until pending.empty?
    candidate = pending.pop
    if candidate.is_a?(Prism::CallNode)
      receiver = candidate.receiver
      p_receiver = (receiver.is_a?(Prism::LocalVariableReadNode) && receiver.name == :p) ||
                   (receiver.is_a?(Prism::CallNode) && receiver.receiver.nil? && receiver.name == :p)
      if p_receiver && (candidate.name == :[] || candidate.name == :fetch)
        arguments = candidate.arguments&.arguments || []
        return true if arguments.any? do |argument|
          argument.is_a?(Prism::SymbolNode) && argument.unescaped == key.to_s
        end
      end
    end
    pending.concat(candidate.child_nodes.compact)
  end
  false
end

# The matching effect call itself must consume the key. A discarded p[:temp]
# expression elsewhere in the same when arm does not configure the rendered effect.
def preset_effect_reads_key?(preset_source, effect, key)
  return false unless preset_source

  require "prism"
  parsed = Prism.parse(preset_source)
  return false unless parsed.success?

  # Ruby executes the first matching when branch. Later duplicate labels are
  # unreachable and must not lend a key read to the active effect arm.
  pending = [parsed.value]
  dispatch = nil
  until pending.empty?
    node = pending.shift
    if node.is_a?(Prism::CaseNode) &&
       node.predicate.is_a?(Prism::LocalVariableReadNode) &&
       node.predicate.name == :fx
      dispatch = node
      break
    end
    pending.concat(node.child_nodes.compact)
  end
  return false unless dispatch

  branch = dispatch.conditions.find do |candidate|
    candidate.is_a?(Prism::WhenNode) &&
      candidate.conditions.any? do |condition|
        condition.is_a?(Prism::StringNode) && condition.unescaped == effect.to_s
      end
  end
  return false unless branch

  pending = [branch.statements].compact
  until pending.empty?
    candidate = pending.pop
    if candidate.is_a?(Prism::CallNode) && candidate.receiver.nil? && candidate.name.to_s == effect.to_s
      return true if postpro_node_reads_p_key?(candidate, key)
    end
    pending.concat(candidate.child_nodes.compact)
  end
  false
end
