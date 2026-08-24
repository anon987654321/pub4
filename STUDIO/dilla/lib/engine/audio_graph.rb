# frozen_string_literal: true

# The routing spine: channels into buses into a master.
#
# dilla already builds exactly this shape and builds it by hand. render_dilla
# accumulates `filt` (a list of ffmpeg filter_complex clauses), `mix_labels` and
# `mix_weights`, joins them with amix, and appends the master chain -- roughly
# eighty lines of string assembly in which the routing decisions are literals
# scattered through conditionals. The other three renderers do not do it at all:
# render_techno, render_industrial and render_analog go straight to
# normalise_genre_master! and never see a bus, which is why the console strip in
# tape_master is reachable from render_dilla and from nothing else.
#
# This is not a new audio path. It emits the same filter_complex, and
# test_audio_graph.rb pins that against the string render_dilla would have
# produced for the same channels. It exists so that "route this to the drum bus"
# is a thing the engine can say, and so a genre can be a set of channel
# definitions rather than its own renderer.
#
# What it deliberately does NOT do:
#
#   - decide gains. Weights come from the caller, because the numbers currently
#     in render_dilla (0.68 chops, 0.72 sub, 0.75 padbed, 0.35 vinyl) were
#     tuned by ear against real material and are not this object's to invent.
#   - touch ffmpeg. It returns a string. Shelling out stays in shell.rb, which
#     is the one place that already knows about timeouts and SIGTTIN.
#   - reorder anything. Emission order follows insertion order, because amix
#     weights are positional and a reordered graph is a different mix.
class AudioGraph
  # input:  an ffmpeg input specifier -- "0:a", "[chops]", or a bare label.
  # chain:  filters applied to this source alone, in order, as strings.
  # gain:   the amix weight for this channel within its bus.
  # bus:    which bus collects it.
  Channel = Struct.new(:name, :input, :chain, :gain, :bus, keyword_init: true)

  # chain: filters applied to the summed bus, after amix, before its parent.
  # into:  the bus this one feeds. :master is the root.
  Bus = Struct.new(:name, :chain, :gain, :into, keyword_init: true)

  # amix's own defaults are wrong for a mix bus: duration=longest pads every
  # channel to the longest one, and normalize=1 silently rescales by input count
  # so adding a quiet channel drops everything else. render_dilla already passes
  # both explicitly; the spine keeps that rather than rediscovering it.
  AMIX_OPTIONS = "duration=first:normalize=0"

  def initialize
    @channels = []
    @buses = {}
    @master_chain = []
  end

  attr_reader :channels, :buses

  def channel(name, input:, chain: [], gain: 1.0, bus: :master)
    raise ArgumentError, "duplicate channel #{name}" if @channels.any? { |c| c.name == name.to_sym }

    @channels << Channel.new(name: name.to_sym, input: input.to_s, chain: Array(chain),
                             gain: gain, bus: bus.to_sym)
    self
  end

  def bus(name, chain: [], gain: 1.0, into: :master)
    name = name.to_sym
    raise ArgumentError, "duplicate bus #{name}" if @buses.key?(name)
    raise ArgumentError, "a bus cannot feed itself" if name == into.to_sym

    @buses[name] = Bus.new(name: name, chain: Array(chain), gain: gain, into: into.to_sym)
    self
  end

  def master(chain)
    @master_chain = Array(chain)
    self
  end

  # Every bus that feeds `target`, plus every channel that does, as one summed
  # node. Returns [clauses, label] or [clauses, nil] when nothing feeds it.
  def sum_into(target, clauses)
    target = target.to_sym
    feeding_channels = @channels.select { |c| c.bus == target }
    feeding_buses = @buses.values.select { |b| b.into == target }

    parts = feeding_channels.map { |c| ["[#{c.name}]", c.gain] }
    feeding_buses.each do |b|
      _, label = emit_bus(b, clauses)
      parts << ["[#{label}]", b.gain] if label
    end
    return [clauses, nil] if parts.empty?

    # One input is not a mix. amix with inputs=1 still resamples and reweights,
    # so a single-channel bus would not be bit-identical to the channel itself.
    return [clauses, parts.first[0].delete("[]")] if parts.one? && parts.first[1] == 1.0

    label = "#{target}_sum"
    clauses << "#{parts.map(&:first).join}amix=inputs=#{parts.size}:" \
               "weights=#{parts.map { |(_, g)| format_gain(g) }.join(' ')}:#{AMIX_OPTIONS}[#{label}]"
    [clauses, label]
  end

  def to_filter_complex(out_label: "out")
    clauses = []
    @channels.each { |c| clauses << channel_clause(c) }
    _, summed = sum_into(:master, clauses)
    raise ArgumentError, "nothing routes to master" unless summed

    tail = @master_chain.reject { |f| f.to_s.strip.empty? }
    if tail.empty?
      # No master chain: rename the sum rather than leave the caller guessing
      # which label to map. anull is the cheapest no-op ffmpeg has.
      clauses << "[#{summed}]anull[#{out_label}]"
    else
      clauses << "[#{summed}]#{tail.join(',')}[#{out_label}]"
    end
    clauses.join(";")
  end

  private

  def emit_bus(bus, clauses)
    return [clauses, @emitted_buses[bus.name]] if (@emitted_buses ||= {}).key?(bus.name)

    _, summed = sum_into(bus.name, clauses)
    return [clauses, @emitted_buses[bus.name] = nil] unless summed

    label = bus.name.to_s
    if bus.chain.empty?
      @emitted_buses[bus.name] = summed
    else
      clauses << "[#{summed}]#{bus.chain.join(',')}[#{label}]"
      @emitted_buses[bus.name] = label
    end
    [clauses, @emitted_buses[bus.name]]
  end

  def channel_clause(channel)
    source = channel.input.start_with?("[") ? channel.input : "[#{channel.input}]"
    chain = channel.chain.reject { |f| f.to_s.strip.empty? }
    chain = ["anull"] if chain.empty?
    "#{source}#{chain.join(',')}[#{channel.name}]"
  end

  # Weights are positional strings in amix. 1.0 renders as "1", not "1.0", to
  # match what render_dilla already writes -- the graphs are compared as text.
  def format_gain(value)
    f = value.to_f
    f == f.to_i ? f.to_i.to_s : f.to_s
  end
end
