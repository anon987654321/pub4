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

  # A renderer being migrated onto the spine has to be able to emit the graph it
  # emits today, including where that graph is wrong. render_industrial omits
  # normalize=0 on all three of its amix calls, and measured against a 440Hz
  # reference that is 4.1 dB quieter than the same weights give under
  # normalize=0 (-21.07 against -16.94 RMS). Its bed then feeds a sidechain
  # compressor at -24dB, a tanh saturator and a compressor at -14dB, so the
  # difference is audible rather than bookkeeping.
  #
  # Passing the legacy string is how a migration proves parity first and changes
  # the sound second, as two decisions instead of one. It is not a default:
  # AMIX_OPTIONS is, and anything new gets the explicit form.
  def initialize(amix_options: AMIX_OPTIONS)
    @amix_options = amix_options
    @channels = []
    @buses = {}
    @order = []
    @master_chain = []
  end

  attr_reader :channels, :buses

  def channel(name, input:, chain: [], gain: 1.0, bus: :master)
    raise ArgumentError, "duplicate channel #{name}" if @channels.any? { |c| c.name == name.to_sym }

    @channels << Channel.new(name: name.to_sym, input: input.to_s, chain: Array(chain),
                             gain: gain, bus: bus.to_sym)
    @order << [:channel, name.to_sym]
    self
  end

  def bus(name, chain: [], gain: 1.0, into: :master)
    name = name.to_sym
    raise ArgumentError, "duplicate bus #{name}" if @buses.key?(name)
    raise ArgumentError, "a bus cannot feed itself" if name == into.to_sym

    @buses[name] = Bus.new(name: name, chain: Array(chain), gain: gain, into: into.to_sym)
    @order << [:bus, name]
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

    # Declaration order across BOTH kinds. Summing every channel and then every
    # bus put a bus last however early it was declared, which reorders amix's
    # inputs. That is the same sum arithmetically -- each weight travels with
    # its input -- but a different graph as text, and migrations here are proved
    # by comparing graphs as text. It also broke the invariant this class
    # documents at the top.
    parts = []
    @order.each do |kind, name|
      if kind == :channel
        found = feeding_channels.find { |c| c.name == name } or next
        parts << ["[#{channel_label(found)}]", found.gain]
      else
        found = feeding_buses.find { |b| b.name == name } or next
        _, label = emit_bus(found, clauses)
        parts << ["[#{label}]", found.gain] if label
      end
    end
    return [clauses, nil] if parts.empty?

    # One input is not a mix. amix with inputs=1 still resamples and reweights,
    # so a single-channel bus would not be bit-identical to the channel itself.
    return [clauses, parts.first[0].delete("[]")] if parts.one? && parts.first[1] == 1.0

    label = "#{target}_sum"
    clauses << "#{parts.map(&:first).join}amix=inputs=#{parts.size}:" \
               "weights=#{parts.map { |(_, g)| format_gain(g) }.join(' ')}:#{@amix_options}[#{label}]"
    [clauses, label]
  end

  # The label the master sum landed on, once to_filter_complex has run. A
  # renderer migrating one section at a time needs this: render_industrial sums
  # a bed and then keeps building by hand -- sidechain, reverb send, delay send
  # -- so it wants the sum and its label, not a finished graph ending in [out].
  attr_reader :sum_label

  # out_label: nil emits the sum and stops. Anything else appends the master
  # chain (or anull) and lands on that label.
  def to_filter_complex(out_label: "out")
    clauses = []
    @channels.each { |c| (clause = channel_clause(c)) && clauses << clause }
    _, summed = sum_into(:master, clauses)
    raise ArgumentError, "nothing routes to master" unless summed

    @sum_label = summed
    return clauses.join(";") if out_label.nil?

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

  # A channel whose source is already a label and which applies nothing is that
  # label. Emitting [drums]anull[kit] would be audibly identical and textually
  # different, and the whole migration strategy here rests on comparing graphs
  # as text -- so a pass-through of an existing label stays that label rather
  # than growing a rename nobody asked for.
  #
  # Deliberately not extended to input specifiers like 0:a. Those can be fed to
  # amix directly too, but then the channel's name never appears in the graph
  # and a reader cannot tell which source is which.
  def pass_through?(channel)
    channel.input.start_with?("[") && channel.chain.none? { |f| f.to_s.strip != "" }
  end

  def channel_label(channel)
    pass_through?(channel) ? channel.input.delete("[]") : channel.name.to_s
  end

  def channel_clause(channel)
    return nil if pass_through?(channel)

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
