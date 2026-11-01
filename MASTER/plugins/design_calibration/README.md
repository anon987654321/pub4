# design_calibration (parked)

Parked layout-campaign machinery: calibration set, exemplars, geometry surfaces, surface schemas, layout search space, design baseline.

- **revive_when:** the layout campaign (P3-P5) restarts with traffic to calibrate against
- **members:** checks/data/{calibration,layout_search}.yml, checks/lib/research/{calibration,layout_search}.rb, checks/support/{check_calibration,layout_search}.rb, RAILS-side tests (calibration, layout_search, layout_search_detector)
- **returned to the tree on review:** exemplars.yml + fixtures, geometry_surfaces.yml, surface_schemas.yml, design_baseline tool+data — all have live readers (geometry_probe, dom_surface_schema, visual_quality, visual_contract, the design_baseline measure row, sweep).
- **note:** Rows removed from checks.yml; RAILS-side tests moved with the machinery.

Parked 2026-11-01 under the essentials pass; sponsor: the operator.
