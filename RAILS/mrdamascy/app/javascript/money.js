// The money() rule from ApplicationHelper, for the controllers that redraw
// amounts in the page: whole kroner print without decimals ("129 kr"), any
// øre remainder with Norwegian comma decimals ("15,50 kr"), never grouped.
const withOre = new Intl.NumberFormat("nb-NO", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
  useGrouping: false,
})

export function formatOre(ore) {
  const value = Math.round(Number(ore) || 0)
  return value % 100 === 0 ? `${value / 100} kr` : `${withOre.format(value / 100)} kr`
}
