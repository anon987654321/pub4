# frozen_string_literal: true

# Laws recovered from the deleted master.json/master.yml design layer and the
# Rails/UI archaeology in pub/__OLD_BACKUPS. Keep the invariant, not the old
# framework or token values.

require "yaml"

Law.define(:README_VISION) do
  source "pub3 master.json documentation.readme_structure.vision — project vision leads README"
  scope :file
  detect do |text|
    paragraph = text.split(/\n\s*\n/).find do |block|
      line = block.strip
      !line.empty? && !line.start_with?("#")
    end.to_s.gsub(/\s+/, " ").strip
    sentences = paragraph.to_s.scan(/[^.!?]+[.!?](?=\s|\z)/).length
    paragraph.to_s.empty? || sentences > 3
  end
  fix "Put a concise 1–3 sentence project vision in the README's first prose paragraph."
  bad <<~X
    # pub4

    Setup details first.
    Run the command below.
    Then read the architecture.
    Finally you will discover what the project is for.
  X
  good <<~X
    # pub4

    MASTER governs the repository as an OpenBSD-like, self-cleaning system. It
    preserves working behavior while continuously reducing unnecessary
    complexity.
  X
end

Law.define(:HTML_HEADING_HIERARCHY) do
  source "pub prompt lineage — semantic HTML5 structure; h1 for title, h2 for sections, h3 for subsections"
  ask "Does the rendered document expose a coherent heading hierarchy? Require one meaningful page heading, then descend one level at a time through sections; do not use heading tags for visual sizing or skip from h1 to h3 merely for styling. Return CLEAN when the hierarchy matches the information architecture."
  fix "Use heading levels to express document structure, then control visual size with typography tokens instead of heading-tag jumps."
  bad <<~X
    <h1>Orders</h1>
    <h3>Recent orders</h3>
    <h4>Today</h4>
  X
  good <<~X
    <h1>Orders</h1>
    <h2>Recent orders</h2>
    <h3>Today</h3>
  X
end

Law.define(:VISUAL_IDENTITY_SOURCE_OF_TRUTH) do
  source "pub4 visual identity contract — canonical tokens, measured contrast and semantic face accent"
  scope :file
  detect do |text|
    document = YAML.safe_load(text, aliases: true)
    tokens = document.fetch("tokens")
    identity = tokens.fetch("visual_identity")
    anchors = tokens.fetch("face_root").fetch("anchors")
    signal = identity.fetch("signal")
    ink = identity.fetch("signal_ink")
    light_ink = identity.fetch("signal_on_light")
    fraction = Float(identity.fetch("max_highlight_area_fraction"))
    display_size = identity.fetch("display_size").to_s
    contrast_floors = identity.fetch("contrast")
    ink_floor = Float(contrast_floors.fetch("signal_on_ink_min"))
    white_floor = Float(contrast_floors.fetch("signal_on_white_min"))
    paper_floor = Float(contrast_floors.fetch("signal_on_paper_min"))
    motion = identity.fetch("motion")
    art_direction = identity.fetch("art_direction")
    typography_roles = identity.fetch("typography_roles")
    adaptations = identity.fetch("adaptations")
    avoid = identity.fetch("avoid")

    luminance = lambda do |hex|
      channels = hex.to_s.delete_prefix("#").scan(/../).map { |channel| channel.to_i(16) / 255.0 }
      next nil unless channels.length == 3

      linear = channels.map do |value|
        value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
      end
      0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    end
    contrast = lambda do |foreground, background|
      values = [luminance.call(foreground), luminance.call(background)]
      next 0.0 if values.any?(&:nil?)

      high, low = values.sort.reverse
      (high + 0.05) / (low + 0.05)
    end
    valid_hex = ->(value) { value.to_s.match?(/\A#[0-9a-f]{6}\z/i) }
    required_adapters = %w[master brgen amber bsdports openbsd studio]

    !identity.fetch("name").eql?("signal_and_stillness") ||
      !valid_hex.call(signal) || !valid_hex.call(ink) || !valid_hex.call(light_ink) ||
      !display_size.match?(/\Aclamp\([^)]*\)\z/) ||
      ink_floor < 7.0 || white_floor < 4.5 || paper_floor < 4.5 ||
      contrast.call(signal, ink) < ink_floor ||
      contrast.call(light_ink, "#FFFFFF") < white_floor ||
      contrast.call(light_ink, "#EFEFEF") < paper_floor ||
      fraction <= 0.0 || fraction > 0.08 ||
      anchors.fetch("c_accent") != "var(--pub4-signal)" ||
      motion.fetch("default") != "still" ||
      motion.fetch("change_requires_semantic_state") != true ||
      motion.fetch("reduced_motion_must_preserve_meaning") != true ||
      art_direction.fetch("subject_count").to_i != 1 ||
      art_direction.fetch("preserve_media_colour") != true ||
      art_direction.fetch("preserve_likeness") != true ||
      art_direction.fetch("grade_is_explicit") != true ||
      !art_direction.fetch("typography_layer").to_s.include?("editable") ||
      !art_direction.fetch("signal_usage").to_s.include?("never colour-grade") ||
      typography_roles.fetch("display") != "text-display" ||
      typography_roles.fetch("body") != "text-base" ||
      typography_roles.fetch("technical") != "font-mono" ||
      !typography_roles.fetch("wordmark").to_s.include?("original") ||
      !avoid.any? { |item| item.to_s.include?("protected brand expression") } ||
      !required_adapters.all? { |key| adaptations.fetch(key).is_a?(String) && !adaptations.fetch(key).empty? }
  rescue Psych::Exception, KeyError, TypeError, ArgumentError
    true
  end
  fix "Restore the canonical signal-and-stillness tokens, measured contrast, still-by-default motion, local dialect adapters and var(--pub4-signal) face anchor."
  bad <<~YAML
    tokens:
      visual_identity:
        name: signal_and_stillness
        signal: "#C8F55F"
        signal_ink: "#101010"
      face_root:
        anchors:
          c_accent: "#C8F55F"
  YAML
  good <<~YAML
    tokens:
      visual_identity:
        name: signal_and_stillness
        signal: "#C8F55F"
        signal_ink: "#101010"
        signal_on_light: "#50630A"
        display_size: "clamp(40px, 6vw, 88px)"
        contrast:
          signal_on_ink_min: 7.0
          signal_on_white_min: 4.5
          signal_on_paper_min: 4.5
        max_highlight_area_fraction: 0.08
        avoid: ["copied protected brand expression"]
        motion:
          default: still
          change_requires_semantic_state: true
          reduced_motion_must_preserve_meaning: true
        art_direction:
          subject_count: 1
          typography_layer: "separate and editable critical copy"
          signal_usage: "original graphics only; never colour-grade photographic subjects with the signal"
          preserve_media_colour: true
          preserve_likeness: true
          grade_is_explicit: true
        typography_roles:
          display: text-display
          body: text-base
          technical: font-mono
          wordmark: original pub4 artwork only
        adaptations:
          master: "signal on ink"
          brgen: "retain deep-blue identity"
          amber: "preserve garment colour"
          bsdports: "retain terminal green"
          openbsd: "plain operational text"
          studio: "operator-owned media grades"
      face_root:
        anchors:
          c_accent: "var(--pub4-signal)"
  YAML
end

Law.define(:VISUAL_PARTICLE_STIPPLE_PRIMARY) do
  source "pub4 primary material — greyscale particle stipple, many carriers resolving into one form"
  scope :file

  detect do |text|
    tokens = YAML.safe_load(text, aliases: true).fetch("tokens")
    face = tokens.fetch("face_interface")

    modes = face.fetch("state").fetch("modes").map(&:to_s).sort
    forces = face.fetch("stipple_force")
    memberships = face.fetch("stipple_membership")

    force_words = %w[residual ripple gather fragment settle]
    membership_words = %w[unturned transitional turned locked]
    required_terms = %w[pluribus unum signal turned unturned residual void gather ripple fragment settle]
    required_bans = %w[solid_mesh_as_primary_face_material motion_without_semantic_state
                       signal_as_large_background_fill erasing_all_residual_individuality_in_idle]

    tokens.fetch("visual_identity").fetch("material") != "greyscale_particle_stipple" ||
      !required_terms.all? { |term| face.fetch("stipple_vocabulary").fetch(term).to_s.strip != "" } ||
      forces.keys.sort != modes || memberships.keys.sort != modes ||
      !(forces.values - force_words).empty? || !(memberships.values - membership_words).empty? ||
      forces.fetch("idle") != "residual" ||
      !(required_bans - face.fetch("stipple_forbidden")).empty?
  rescue Psych::Exception, KeyError, TypeError, ArgumentError
    true
  end

  fix "Keep greyscale particle stipple as the identity material; give every face state a membership and " \
      "a force from the stipple vocabulary, and let idle keep its residual."

  bad <<~YAML
    tokens:
      visual_identity:
        material: "glossy_mesh_skin"

      face_interface:
        state:
          modes: [idle]

        stipple_vocabulary: {}
        stipple_membership: { idle: turned }
        stipple_force: { idle: glow }
        stipple_forbidden: []
  YAML

  good <<~YAML
    tokens:
      visual_identity:
        material: "greyscale_particle_stipple"

      face_interface:
        state:
          modes: [idle]

        stipple_vocabulary:
          pluribus: "many discrete carriers"
          unum: "one readable form"
          signal: "propagating change"
          turned: "admitted into the field"
          unturned: "not yet joined"
          residual: "the particular inside the collective"
          void: "negative space"
          gather: "parts pull toward one locus"
          ripple: "a signal crosses the field"
          fragment: "parts leave the form"
          settle: "the field re-coheres"

        stipple_membership: { idle: transitional }
        stipple_force: { idle: residual }
        stipple_forbidden:
          - solid_mesh_as_primary_face_material
          - motion_without_semantic_state
          - signal_as_large_background_fill
          - erasing_all_residual_individuality_in_idle
  YAML
end

Law.define(:INTERACTION_SEMANTICS) do
  source "pub3 master.json HTML semantics + WAI-ARIA — navigation is a link, an action is a button"
  ask "For interactive controls, is the native element honest about the action? Use an anchor for navigation, a button for an in-page action, and a form control for form input. Reject clickable div/span substitutes, href=# used as an action, and ARIA used to repair a native-element choice. Return CLEAN when native interaction semantics are already correct."
  fix "Use the native interactive element that matches the user's action, then add ARIA only for state or additional semantics."
  bad <<~X
    <div class="save" data-action="click->editor#save">Save</div>
    <a href="#" data-action="click->menu#open">Open menu</a>
  X
  good <<~X
    <button type="button" class="save" data-action="click->editor#save">Save</button>
    <%= link_to "Read the article", article_path(@article) %>
  X
end

Law.define(:CONFIGURATION_SHAPE) do
  source "pub2 master.json anti_sectionitis — consolidate related configuration; keep nesting shallow"
  scope :file
  detect do |text|
    value = YAML.safe_load(text)
    next false unless value.is_a?(Hash)

    max_depth = lambda do |node, depth|
      case node
      when Hash
        [depth, *node.values.map { |child| max_depth.call(child, depth + 1) }].max
      when Array
        [depth, *node.map { |child| max_depth.call(child, depth + 1) }].max
      else
        depth
      end
    end

    max_depth.call(value, 1) > 4 || value.size > 18
  rescue Psych::Exception
    false
  end
  fix "Flatten incidental nesting and consolidate related top-level sections; keep configuration shallow and grouped by purpose."
  bad <<~X
    {
      "a": {
        "b": {
          "c": {
            "d": {
              "e": true
            }
          }
        }
      }
    }
  X
  good <<~X
    {
      "retries": 3,
      "timeout": 30,
      "logging": {
        "level": "info"
      }
    }
  X
end

Law.define(:STYLE_FOLLOWS_STRUCTURE) do
  source "pub3 anti_divitis + anti_sectionitis — structure before decoration"
  ask "Before adding CSS selectors, wrappers, spacing hacks, or decorative rules, is the HTML structure itself semantic, minimal, and ordered for the content? Prefer changing the structural source over painting around a malformed hierarchy. Return CLEAN when semantic structure already carries the hierarchy and styling follows it."
  fix "Fix semantic structure and content hierarchy first; then simplify selectors and tokens to style that structure."
  bad <<~X
    <div class="content-wrapper">
      <div class="content-title">Orders</div>
      <div class="content-copy">No orders yet.</div>
    </div>

    .content-wrapper .content-title { margin-bottom: 13px; }
    .content-wrapper .content-copy { margin-top: 7px; }
  X
  good <<~X
    <section aria-labelledby="orders-title">
      <h2 id="orders-title">Orders</h2>
      <p>No orders yet.</p>
    </section>

    section { padding-block: 16px; }
    h2 { margin-block-end: 8px; }
  X
end
