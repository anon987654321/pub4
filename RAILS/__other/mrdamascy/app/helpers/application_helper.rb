# frozen_string_literal: true

# Presentation helpers shared across the app (APP_SPEC §6/§7). Money is
# integer øre everywhere; the chip helpers map straight onto the §1/§7
# palette (mint/gold/pom) that the stylesheet owns.
module ApplicationHelper
  # money(1500) → "15 kr" — whole øre render without decimals; anything with
  # a remainder falls back to Norwegian comma decimals ("15,50 kr").
  def money(ore)
    kroner, rester = ore.to_i.divmod(100)
    rester.zero? ? "#{kroner} kr" : format("%d,%02d kr", kroner, rester)
  end

  # Three dots; lit dots take their own level colour (1 mint-500 Mild, 2 gold
  # Middels, 3 pom Sterk!) so the scale reads at a glance.
  # SCSS contract: .heat-dots > .heat-dot.heat-1|heat-2|heat-3 + .is-lit.
  def heat_dots(item)
    heat = item.heat.to_i.clamp(0, 3)
    dots = (1..3).map do |level|
      classes = ["heat-dot", "heat-#{level}"]
      classes << "is-lit" if level <= heat
      tag.span("", class: classes.join(" "))
    end
    label = t("menu.heat.#{heat}")
    tag.span(safe_join(dots), class: "heat-dots", "aria-label": label, title: label)
  end

  # Flag-free origin chip ("Damaskus"); the two-sentence story from
  # origins.<origin> rides along as the title tooltip.
  def origin_chip(item)
    origin = item.origin.to_s
    tag.span(t("menu.origin_chip", origin: origin_label(origin)),
             class: "chip chip-origin",
             title: t(origin_story_key(origin)))
  end

  # State chip colours per APP_SPEC §7: placed mint, confirmed gold,
  # preparing gold-deep, ready mint-700, delivered ink-soft, cancelled pom.
  # SCSS contract: .state-chip.state-<state>.
  def state_chip(order)
    state = order.state.to_s
    tag.span(t("orders.states.#{state}"), class: "state-chip state-#{state}")
  end

  # "tel_aviv" / "Tel Aviv" → "origins.tel_aviv" (APP_SPEC §10 keys).
  def origin_story_key(origin)
    "origins.#{origin.to_s.parameterize.underscore}"
  end

  # "tel_aviv" → "Tel Aviv" — proper nouns render as-is in either locale.
  def origin_label(origin)
    origin.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
  end
end
