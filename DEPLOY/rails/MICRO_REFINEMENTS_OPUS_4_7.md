# Rails / Stimulus micro-refinement inventory for Opus 4.7

Scope: `DEPLOY/rails` apps and shared baseline.

Use this as a concrete autofix queue. Prefer real source changes over docs-only changes. Keep changes small, reversible, and app-neutral when the behavior can be shared by Amber, Brgen, Blognet, Baibl, bsdports, or Hjerterom.

## Shared architecture and extraction

1. Move reusable reactions into `DEPLOY/rails/shared` and keep app wrappers thin.
2. Move reusable follows into `DEPLOY/rails/shared` and support user/profile/community follow targets.
3. Move reusable notifications into `DEPLOY/rails/shared` and allow app-specific notification kinds.
4. Move reusable review workflow into `Shared::ReviewCase`.
5. Move media upload validation into `Shared::MediaGuard`.
6. Move media variant processing into `Shared::MediaProcessingJob`.
7. Move live search into `Shared::LiveSearch` and `Shared::LiveSearchable`.
8. Move structured app telemetry into `Shared::EventEmitter`.
9. Keep Brgen-specific code limited to city-local concepts: community, post, vote, feed, proximity.
10. Keep Amber-specific code limited to wardrobe/outfit concepts.
11. Keep Blognet-specific code limited to publishing/editorial concepts.
12. Keep Baibl-specific code limited to scripture/translation/study concepts.
13. Keep bsdports-specific code limited to ports/advisories/imports.
14. Keep Hjerterom-specific code limited to parcels, donors, volunteers, beneficiaries.
15. Add a shared app installer task for copying baseline files into each app tree.
16. Make the installer idempotent and safe to run repeatedly.
17. Add a shared README explaining which files are copied versus referenced.
18. Add shared namespacing conventions for copied models versus inherited shared models.
19. Avoid duplicate Brgen-only social logic where Amber can reuse it.
20. Use app-local wrappers only when database compatibility requires it.

## Rails model style and consistency

21. Order model files as constants, associations, validations, scopes, callbacks, public methods, private methods.
22. Prefer explicit constants for enum/string allowed values.
23. Avoid mixed enum/string state styles in the same app.
24. Normalize state naming: `state` for workflow state, `kind` for type/category.
25. Avoid vague column names like `type` unless STI is intended.
26. Add `inverse_of` to bidirectional associations where useful.
27. Add `optional: true` only when the schema allows null.
28. Align `belongs_to optional: true` with migration nullability.
29. Add `dependent:` behavior to all `has_many` associations.
30. Prefer `dependent: :nullify` for optional audit-like links.
31. Prefer `dependent: :destroy` for owned child rows.
32. Avoid callback side effects when a service object is clearer.
33. Keep callback payloads small and resilient.
34. Use `after_create_commit`/`after_update_commit`, not `after_save`, for broadcasts.
35. Avoid callbacks that can recursively create rows without guardrails.
36. Add `to_param` only for stable slugs, not mutable titles.
37. Validate slug presence and uniqueness where `to_param` uses slug.
38. Normalize email validation with `URI::MailTo::EMAIL_REGEXP` only when email is optional or required explicitly.
39. Add before-validation cleanup for names/slugs where supported.
40. Avoid `Arel.sql` unless necessary and localized.

## Migration/schema refinements

41. Add foreign keys for every `t.references` unless deliberately impossible.
42. Add indexes for every lookup field used by scopes.
43. Add unique indexes matching model uniqueness validations.
44. Add composite unique index for reactions: user + target + kind.
45. Add composite unique index for follows: follower + target.
46. Add index for notifications: user + read_at.
47. Add index for notifications: user + created_at.
48. Add index for review cases: state + created_at.
49. Add index for review cases: reviewable_type + reviewable_id.
50. Add index for Hjerterom boxes: beneficiary_id + week_start.
51. Add index for Hjerterom shifts: volunteer_id + starts_at.
52. Add index for Hjerterom food_items: box_id + quality_state.
53. Add index for Hjerterom food_items: donation_id + category.
54. Add index for bsdports ports search fields or FTS5 virtual table.
55. Add index for bsdports dependencies: port_id + depends_on_id + dep_type.
56. Add index for bsdports security advisories: port_id + severity + published_at.
57. Add index for Baibl verses: book_index + chapter + number.
58. Add index for Baibl annotations: verse_id + created_at.
59. Add index for Amber outfit items: outfit_id + position.
60. Use deterministic migration timestamps per app sequence.
61. Keep shared migrations under `DEPLOY/rails/shared/db/migrate` and document how apps copy them.
62. Do not create tables from shared migrations unless app has corresponding models/routes planned.
63. Ensure migrations are reversible.
64. Avoid raw SQL migrations unless behind adapter checks.
65. Add comments to non-obvious indexes.

## Service object refinements

66. Make all service objects expose `.call`.
67. Keep initializer arguments keyword-based for clarity.
68. Return simple values from toggles: boolean active/inactive.
69. Emit structured events from service objects, not controllers, when the domain action occurs.
70. Avoid hard-coded app class names inside shared services.
71. Detect app-local wrappers carefully with `defined?(::Reaction)` only when intended.
72. Prefer dependency injection over global constant lookup for future hardening.
73. Make `Shared::ReactionToggle` work with both app-local and shared model classes.
74. Make `Shared::FollowToggle` work with both polymorphic followable and legacy followed-user schemas.
75. Make `Shared::LiveSearch` adapter-aware for SQLite/Postgres.
76. Add tests for blank-query live search returning ordered base scope.
77. Add tests for escaped wildcard characters in search queries.
78. Add tests for reaction toggle idempotence.
79. Add tests for follow toggle self-follow prevention.
80. Add tests for event emitter fallback logging.
81. Add tests for media guard MIME allowlist.
82. Add tests for media guard size limit.
83. Add tests for outfit ordering preserving missing IDs.
84. Add tests for bsdports search fallback.
85. Add tests for Hjerterom shift time validation.

## Controllers/routes/views to add next

86. Add shared reactions controller.
87. Add shared follows controller.
88. Add shared notifications controller.
89. Add shared review cases controller.
90. Add shared media uploads controller with connector-safe incremental patching.
91. Add Brgen reactions route pointing to shared service.
92. Add Brgen follows route pointing to shared service.
93. Add Brgen notifications routes: index, update/read, read_all.
94. Add Brgen review cases routes for report/create/review.
95. Add Amber reactions route for items/outfits/posts.
96. Add Amber follows route for wardrobes/users/profiles.
97. Add Amber outfit ordering route.
98. Add Amber wardrobe upload route.
99. Add bsdports search route using `PortsSearch`.
100. Add bsdports import route/admin trigger guarded by auth.
101. Add Baibl scripture search route.
102. Add Baibl annotation create/update routes.
103. Add Baibl analysis request route backed by `AnalysisJob`.
104. Add Hjerterom donations resources.
105. Add Hjerterom boxes resources.
106. Add Hjerterom volunteers and shifts resources.
107. Add Hjerterom donors and beneficiaries resources.
108. Add Blognet author profile resources.
109. Add Blognet editorial workflow routes.
110. Add Foodielicious recipe/ingredient routes.

## Stimulus Components refinements

111. Register only controllers each app actually uses.
112. Keep Stimulus bootstrap tree-shakeable where bundling exists.
113. Add Clipboard for share URLs and install commands.
114. Add Notification for upload/job/action feedback.
115. Add Reveal for advanced/raw metadata.
116. Add Dropdown for filters and state selectors.
117. Add Dialog for previews and confirmations.
118. Add Lightbox for Amber item photos and Foodielicious galleries.
119. Add Timeago for all recent feed/event timestamps.
120. Add Content Loader for progressive search result panels.
121. Add Auto Submit for live filters.
122. Add Sortable for Amber outfit items and playlist tracks.
123. Add Character Counter for post/comment/editor fields.
124. Add Textarea Autogrow for comments, posts, notes, annotations.
125. Add Hotkey for search focus and chapter navigation.
126. Add Read More for long package descriptions and articles.
127. Add Popover for metadata hints.
128. Add Sound only where product-appropriate, not globally.
129. Add Speech Recognition only to prompt/search surfaces where useful.
130. Add progressive fallback for every Stimulus behavior.

## App-specific refinements

131. Brgen: wire city/proximity filters after shared social controllers exist.
132. Brgen: add city-scoped subdomain routing.
133. Brgen: add SQLite FTS5 for posts, comments, communities.
134. Brgen: add media attachments and variants for posts/comments.
135. Brgen: add local feed ranking service separate from Reddit-like vote ranking.
136. Brgen: add community moderation role model.
137. Brgen: add report/review workflow using `Shared::ReviewCase`.
138. Brgen: re-attempt direct/private messages with small safe patches.
139. Amber: wire `WardrobeMediaJob` after item photo attach.
140. Amber: add Lightbox to item photo cards.
141. Amber: add Sortable to outfit item ordering.
142. Amber: add underused/never-worn content loader panel.
143. Amber: add share/copy links for items and outfits.
144. bsdports: implement real ports-tree import parser.
145. bsdports: add dependency tree endpoint and partial.
146. bsdports: add security advisory filters.
147. bsdports: add copy install command partial.
148. bsdports: run WCAG AAA pass on index/search.
149. Baibl: add book/chapter navigation index.
150. Baibl: add translation comparison view.
151. Baibl: add annotation partial and Turbo Stream append.
152. Baibl: add analysis pending/done states.
153. Blognet: add author profile model/controllers/views.
154. Blognet: add RSS/Atom feed.
155. Blognet: add article schema.org metadata.
156. Blognet: add editorial workflow states.
157. Foodielicious: add Recipe model.
158. Foodielicious: add Ingredient model.
159. Foodielicious: add recipe step model.
160. Foodielicious: add recipe Lightbox gallery.
161. Hjerterom: add donation intake controller/view.
162. Hjerterom: add weekly box planning view.
163. Hjerterom: add shift scheduling controller/view.
164. Hjerterom: add donor contact copy partial.
165. Hjerterom: add beneficiary priority sorting.
166. Hjerterom: add reporting job skeleton.

## CI, quality, and rollout

167. Add app-local `bin/ci` for every DEPLOY/rails app.
168. Add `zeitwerk:check` to each CI script.
169. Add model tests for every new skeleton model.
170. Add service tests for every service object.
171. Add route tests for every added controller.
172. Add system tests for high-value Stimulus flows where app trees are complete.
173. Add RuboCop Rails config if repo standardizes on RuboCop.
174. Add Brakeman or security scan for Rails apps if acceptable.
175. Add migration smoke test for each app.
176. Add seed data for Hjerterom.
177. Add seed data for bsdports sample platforms/categories/ports.
178. Add seed data for Baibl Genesis sample if not already present.
179. Add sample Amber item/outfit fixtures.
180. Add sample Brgen communities/posts/comments.
181. Add shared fixtures for reactions/follows/notifications.
182. Add README section showing how to run shared installer.
183. Add deploy script hook for shared installer.
184. Add rollback note for copied shared files.
185. Keep `apps.yml` status synced with implemented files.
186. Convert completed `port` items to `done` only after tests pass.
187. Keep handoff PRs mergeable by limiting cross-app conflicts.
188. Split production wiring into follow-up PRs per app.
189. Prefer additive changes until app trees are fully restored.
190. Remove stale rollout docs once code replaces them.
191. Re-run PR compare after each major batch.
192. Use draft PRs for large app-specific wiring until CI exists.
193. Add merge-risk notes to every handoff PR.
194. Record connector-blocked files in handoff docs.
195. Avoid claiming production completeness without app-local test runs.
196. Keep shared migrations copied, not magically loaded, until app loading strategy is explicit.
197. Verify all namespaced shared models resolve under Zeitwerk.
198. Verify app-local wrappers do not shadow shared constants unintentionally.
199. Add final style pass after controllers/routes are present.
200. Close the loop by updating `DEPLOY/rails/RESTORE_OPPORTUNITIES.md` with completed work.
