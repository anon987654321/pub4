# Layout micro-refinement matrix

332 browser-layout micro-refinements are implemented from one shared pass. Each target contributes four or more deliberate adjustments; the goal is not visual uniformity between dialects, but tighter geometry, stronger semantics, safer overflow, and better optical alignment while preserving each app's own visual language.

The pass covers Amber, Brgen, BSDports, shared chrome, commerce chrome, mobile sheets, feed primitives, forms, overlays, tables, media, and footer surfaces. Mailer HTML/text layouts remain isolated because email-client layout is a separate rendering system.

001. semantic — body — min-block-size: 100dvh — stable viewport frame and cleaner text rasterisation
002. semantic — body — overflow-x: clip — stable viewport frame and cleaner text rasterisation
003. semantic — body — text-rendering: optimizeLegibility — stable viewport frame and cleaner text rasterisation
004. semantic — body — font-kerning: normal — stable viewport frame and cleaner text rasterisation
005. semantic — .theme-root — min-inline-size: 0 — bounded paint root during async chrome updates
006. semantic — .theme-root — overflow-wrap: anywhere — bounded paint root during async chrome updates
007. semantic — .theme-root — isolation: isolate — bounded paint root during async chrome updates
008. semantic — .theme-root — overflow-anchor: none — bounded paint root during async chrome updates
009. semantic — .app-shell — min-inline-size: 0 — prevents intrinsic-width leaks and creates a clean local stacking context
010. semantic — .app-shell — min-block-size: 0 — prevents intrinsic-width leaks and creates a clean local stacking context
011. semantic — .app-shell — position: relative — prevents intrinsic-width leaks and creates a clean local stacking context
012. semantic — .app-shell — isolation: isolate — prevents intrinsic-width leaks and creates a clean local stacking context
013. semantic — .layout — min-inline-size: 0 — keeps shell geometry shrinkable and explicit
014. semantic — .layout — align-items: stretch — keeps shell geometry shrinkable and explicit
015. semantic — .layout — overflow-wrap: anywhere — keeps shell geometry shrinkable and explicit
016. semantic — .layout — box-sizing: border-box — keeps shell geometry shrinkable and explicit
017. semantic — main#main-content — min-inline-size: 0 — keeps reading surfaces inside their tracks and clears fixed chrome
018. semantic — main#main-content — overflow-wrap: anywhere — keeps reading surfaces inside their tracks and clears fixed chrome
019. semantic — main#main-content — box-sizing: border-box — keeps reading surfaces inside their tracks and clears fixed chrome
020. semantic — main#main-content — scroll-margin-block-start: calc(var(--top-band-block, 56px) + var(--space-4)) — keeps reading surfaces inside their tracks and clears fixed chrome
021. semantic — .page-header — min-inline-size: 0 — resilient page-heading groups under locale expansion
022. semantic — .page-header — box-sizing: border-box — resilient page-heading groups under locale expansion
023. semantic — .page-header — text-wrap: pretty — resilient page-heading groups under locale expansion
024. semantic — .page-header — overflow-wrap: anywhere — resilient page-heading groups under locale expansion
025. visual — .page-header h1 — max-inline-size: 100% — tighter headline rag shape without clipping
026. visual — .page-header h1 — overflow-wrap: anywhere — tighter headline rag shape without clipping
027. visual — .page-header h1 — text-wrap: balance — tighter headline rag shape without clipping
028. visual — .page-header h1 — hyphens: auto — tighter headline rag shape without clipping
029. visual — .page-header p — max-inline-size: var(--measure) — calmer supporting-copy measure
030. visual — .page-header p — line-height: var(--leading-snug) — calmer supporting-copy measure
031. visual — .page-header p — text-wrap: pretty — calmer supporting-copy measure
032. visual — .page-header p — overflow-wrap: anywhere — calmer supporting-copy measure
033. visual — .page-actions — display: flex — predictable action clusters at narrow widths
034. visual — .page-actions — align-items: center — predictable action clusters at narrow widths
035. visual — .page-actions — flex-wrap: wrap — predictable action clusters at narrow widths
036. visual — .page-actions — gap: var(--space-2) — predictable action clusters at narrow widths
037. visual — .sidebar — min-inline-size: 0 — independently scrollable secondary navigation
038. visual — .sidebar — overflow-y: auto — independently scrollable secondary navigation
039. visual — .sidebar — overscroll-behavior: contain — independently scrollable secondary navigation
040. visual — .sidebar — scrollbar-gutter: stable — independently scrollable secondary navigation
041. visual — .widgets — min-inline-size: 0 — stable auxiliary-widget geometry
042. visual — .widgets — overflow-y: auto — stable auxiliary-widget geometry
043. visual — .widgets — overscroll-behavior: contain — stable auxiliary-widget geometry
044. visual — .widgets — scrollbar-gutter: stable — stable auxiliary-widget geometry
045. abstract — .nav_swiper — min-inline-size: 0 — self-contained horizontal primary navigation
046. abstract — .nav_swiper — overscroll-behavior-inline: contain — self-contained horizontal primary navigation
047. abstract — .nav_swiper — scrollbar-width: thin — self-contained horizontal primary navigation
048. abstract — .nav_swiper — scroll-behavior: smooth — self-contained horizontal primary navigation
049. abstract — .nav_swiper_bar — min-block-size: var(--tap-min) — stable nav band and baseline
050. abstract — .nav_swiper_bar — align-items: center — stable nav band and baseline
051. abstract — .nav_swiper_bar — gap: var(--space-2) — stable nav band and baseline
052. abstract — .nav_swiper_bar — scrollbar-gutter: stable — stable nav band and baseline
053. optical — .nav_link — min-inline-size: var(--tap-min) — centred, legible primary-nav hit boxes
054. optical — .nav_link — align-items: center — centred, legible primary-nav hit boxes
055. optical — .nav_link — justify-content: center — centred, legible primary-nav hit boxes
056. optical — .nav_link — text-decoration-skip-ink: auto — centred, legible primary-nav hit boxes
057. optical — .nav_link_badge — line-height: 1 — true typographic qualifier geometry
058. optical — .nav_link_badge — vertical-align: super — true typographic qualifier geometry
059. optical — .nav_link_badge — margin-inline-start: var(--space-1) — true typographic qualifier geometry
060. optical — .nav_link_badge — font-variant-numeric: tabular-nums — true typographic qualifier geometry
061. optical — .brand-mark — display: inline-flex — wordmark anchored to the chrome baseline
062. optical — .brand-mark — align-items: baseline — wordmark anchored to the chrome baseline
063. optical — .brand-mark — white-space: nowrap — wordmark anchored to the chrome baseline
064. optical — .brand-mark — text-wrap: nowrap — wordmark anchored to the chrome baseline
065. optical — .chrome-corner — display: flex — compact account/theme control unit
066. optical — .chrome-corner — align-items: center — compact account/theme control unit
067. optical — .chrome-corner — gap: var(--space-1) — compact account/theme control unit
068. optical — .chrome-corner — min-inline-size: 0 — compact account/theme control unit
069. visual — .tab-bar — box-sizing: border-box — even mobile chrome distribution and gesture isolation
070. visual — .tab-bar — align-items: center — even mobile chrome distribution and gesture isolation
071. visual — .tab-bar — justify-content: space-around — even mobile chrome distribution and gesture isolation
072. visual — .tab-bar — overscroll-behavior: contain — even mobile chrome distribution and gesture isolation
073. optical — .tab-item — display: inline-flex — centred icon/label ink
074. optical — .tab-item — align-items: center — centred icon/label ink
075. optical — .tab-item — justify-content: center — centred icon/label ink
076. optical — .tab-item — line-height: 1 — centred icon/label ink
077. abstract — .tab-bar-peel — touch-action: manipulation — discoverable hidden-menu reveal target
078. abstract — .tab-bar-peel — min-inline-size: var(--tap-min) — discoverable hidden-menu reveal target
079. abstract — .tab-bar-peel — min-block-size: var(--tap-min) — discoverable hidden-menu reveal target
080. abstract — .tab-bar-peel — box-sizing: border-box — discoverable hidden-menu reveal target
081. visual — .tab-bar-coach — max-inline-size: min(28rem, calc(100vw - 2 * var(--space-4))) — viewport-safe onboarding copy
082. visual — .tab-bar-coach — overflow-wrap: anywhere — viewport-safe onboarding copy
083. visual — .tab-bar-coach — text-wrap: pretty — viewport-safe onboarding copy
084. visual — .tab-bar-coach — box-sizing: border-box — viewport-safe onboarding copy
085. abstract — .mobile-sheet — max-block-size: calc(100dvh - var(--space-4)) — independently scrolling sheets
086. abstract — .mobile-sheet — overflow-y: auto — independently scrolling sheets
087. abstract — .mobile-sheet — overscroll-behavior-block: contain — independently scrolling sheets
088. abstract — .mobile-sheet — scrollbar-gutter: stable — independently scrolling sheets
089. optical — .mobile-sheet-handle — inline-size: 36px — centred restrained grabber
090. optical — .mobile-sheet-handle — min-block-size: 4px — centred restrained grabber
091. optical — .mobile-sheet-handle — margin-inline: auto — centred restrained grabber
092. optical — .mobile-sheet-handle — border-radius: var(--radius-pill) — centred restrained grabber
093. visual — .mobile-sheet-links — display: grid — calm sheet link rhythm with safe-area clearance
094. visual — .mobile-sheet-links — gap: var(--space-1) — calm sheet link rhythm with safe-area clearance
095. visual — .mobile-sheet-links — min-inline-size: 0 — calm sheet link rhythm with safe-area clearance
096. visual — .mobile-sheet-links — padding-block-end: var(--safe-bottom) — calm sheet link rhythm with safe-area clearance
097. abstract — .mobile-sheet-backdrop — overscroll-behavior: contain — background gesture isolation while the sheet owns input
098. abstract — .mobile-sheet-backdrop — touch-action: none — background gesture isolation while the sheet owns input
099. abstract — .mobile-sheet-backdrop — user-select: none — background gesture isolation while the sheet owns input
100. abstract — .mobile-sheet-backdrop — -webkit-user-select: none — background gesture isolation while the sheet owns input
101. semantic — .search — min-inline-size: 0 — bounded search shell
102. semantic — .search — max-inline-size: 100% — bounded search shell
103. semantic — .search — box-sizing: border-box — bounded search shell
104. semantic — .search — isolation: isolate — bounded search shell
105. semantic — .search input — min-inline-size: 0 — contained search input
106. semantic — .search input — max-inline-size: 100% — contained search input
107. semantic — .search input — box-sizing: border-box — contained search input
108. semantic — .search input — text-overflow: ellipsis — contained search input
109. visual — .nav-search-input — min-inline-size: 0 — compact long-query geometry
110. visual — .nav-search-input — max-inline-size: 100% — compact long-query geometry
111. visual — .nav-search-input — line-height: 1.25 — compact long-query geometry
112. visual — .nav-search-input — text-overflow: ellipsis — compact long-query geometry
113. optical — .nav-search-submit — display: inline-flex — centred search icon target
114. optical — .nav-search-submit — align-items: center — centred search icon target
115. optical — .nav-search-submit — justify-content: center — centred search icon target
116. optical — .nav-search-submit — min-inline-size: var(--tap-min) — centred search icon target
117. optical — .nav-search-submit — min-block-size: var(--tap-min) — centred search icon target
118. semantic — form — min-inline-size: 0 — bounded form layout participant
119. semantic — form — max-inline-size: 100% — bounded form layout participant
120. semantic — form — overflow-wrap: anywhere — bounded form layout participant
121. semantic — form — box-sizing: border-box — bounded form layout participant
122. semantic — form .field — min-inline-size: 0 — compact field geometry
123. semantic — form .field — align-content: start — compact field geometry
124. semantic — form .field — row-gap: var(--space-2) — compact field geometry
125. semantic — form .field — box-sizing: border-box — compact field geometry
126. visual — form label — max-inline-size: 100% — localization-safe labels
127. visual — form label — line-height: 1.4 — localization-safe labels
128. visual — form label — text-wrap: pretty — localization-safe labels
129. visual — form label — overflow-wrap: anywhere — localization-safe labels
130. semantic — form input:not(.btn) — min-inline-size: 0 — stable native input geometry and focus clearance
131. semantic — form input:not(.btn) — box-sizing: border-box — stable native input geometry and focus clearance
132. semantic — form input:not(.btn) — caret-color: var(--accent) — stable native input geometry and focus clearance
133. semantic — form input:not(.btn) — scroll-margin-block-start: calc(var(--top-band-block, 56px) + var(--space-4)) — stable native input geometry and focus clearance
134. semantic — form textarea — min-inline-size: 0 — long user text cannot widen the form
135. semantic — form textarea — max-inline-size: 100% — long user text cannot widen the form
136. semantic — form textarea — overflow-wrap: anywhere — long user text cannot widen the form
137. semantic — form textarea — box-sizing: border-box — long user text cannot widen the form
138. semantic — form select — min-inline-size: 0 — contained native select geometry
139. semantic — form select — max-inline-size: 100% — contained native select geometry
140. semantic — form select — box-sizing: border-box — contained native select geometry
141. semantic — form select — text-overflow: ellipsis — contained native select geometry
142. visual — form .actions — display: flex — resilient submit/cancel rows
143. visual — form .actions — align-items: center — resilient submit/cancel rows
144. visual — form .actions — flex-wrap: wrap — resilient submit/cancel rows
145. visual — form .actions — gap: var(--space-2) — resilient submit/cancel rows
146. optical — .btn — box-sizing: border-box — centred localized action labels
147. optical — .btn — text-align: center — centred localized action labels
148. optical — .btn — text-decoration-skip-ink: auto — centred localized action labels
149. optical — .btn — white-space: normal — centred localized action labels
150. optical — .btn.btn-sm — line-height: 1.2 — compact controls retain touch and numeric alignment
151. optical — .btn.btn-sm — min-inline-size: var(--tap-min) — compact controls retain touch and numeric alignment
152. optical — .btn.btn-sm — box-sizing: border-box — compact controls retain touch and numeric alignment
153. optical — .btn.btn-sm — font-variant-numeric: tabular-nums — compact controls retain touch and numeric alignment
154. semantic — .feed-card — min-inline-size: 0 — shrinkable stable feed rows
155. semantic — .feed-card — box-sizing: border-box — shrinkable stable feed rows
156. semantic — .feed-card — overflow-wrap: anywhere — shrinkable stable feed rows
157. semantic — .feed-card — overflow-anchor: auto — shrinkable stable feed rows
158. semantic — .feed-card-content — min-inline-size: 0 — contained text column
159. semantic — .feed-card-content — max-inline-size: 100% — contained text column
160. semantic — .feed-card-content — overflow-wrap: anywhere — contained text column
161. semantic — .feed-card-content — box-sizing: border-box — contained text column
162. optical — .feed-card-header — align-items: baseline — shared baseline when bylines wrap
163. optical — .feed-card-header — column-gap: var(--space-1) — shared baseline when bylines wrap
164. optical — .feed-card-header — row-gap: var(--space-0-5) — shared baseline when bylines wrap
165. optical — .feed-card-header — min-inline-size: 0 — shared baseline when bylines wrap
166. visual — .feed-card-text — max-inline-size: 66ch — disciplined post reading width
167. visual — .feed-card-text — margin-block-start: 0 — disciplined post reading width
168. visual — .feed-card-text — text-wrap: pretty — disciplined post reading width
169. visual — .feed-card-text — line-height: 1.5 — disciplined post reading width
170. visual — .feed-card-meta — line-height: 1.35 — calmer repeatable metadata
171. visual — .feed-card-meta — font-variant-numeric: tabular-nums — calmer repeatable metadata
172. visual — .feed-card-meta — overflow-wrap: anywhere — calmer repeatable metadata
173. visual — .feed-card-meta — text-wrap: pretty — calmer repeatable metadata
174. visual — .feed-card-actions — min-inline-size: 0 — wrap-safe action clusters
175. visual — .feed-card-actions — display: flex — wrap-safe action clusters
176. visual — .feed-card-actions — flex-wrap: wrap — wrap-safe action clusters
177. visual — .feed-card-actions — align-items: center — wrap-safe action clusters
178. visual — .feed-card-actions — gap: var(--space-1) — wrap-safe action clusters
179. optical — .feed-action — display: inline-flex — icon/count optical centring
180. optical — .feed-action — align-items: center — icon/count optical centring
181. optical — .feed-action — justify-content: center — icon/count optical centring
182. optical — .feed-action — line-height: 1 — icon/count optical centring
183. optical — .feed-action — box-sizing: border-box — icon/count optical centring
184. visual — .post-reading-title — max-inline-size: 18ch — deliberate editorial headline silhouette
185. visual — .post-reading-title — text-wrap: balance — deliberate editorial headline silhouette
186. visual — .post-reading-title — overflow-wrap: anywhere — deliberate editorial headline silhouette
187. visual — .post-reading-title — line-height: 1.05 — deliberate editorial headline silhouette
188. visual — .post-reading-preview — max-inline-size: 72ch — readable preview without grid widening
189. visual — .post-reading-preview — min-inline-size: 0 — readable preview without grid widening
190. visual — .post-reading-preview — overflow-wrap: anywhere — readable preview without grid widening
191. visual — .post-reading-preview — box-sizing: border-box — readable preview without grid widening
192. abstract — .card — min-inline-size: 0 — predictable generic cards
193. abstract — .card — box-sizing: border-box — predictable generic cards
194. abstract — .card — overflow-wrap: anywhere — predictable generic cards
195. abstract — .card — align-content: start — predictable generic cards
196. abstract — .card-grid — min-inline-size: 0 — controlled card row sizing
197. abstract — .card-grid — grid-auto-rows: minmax(0, auto) — controlled card row sizing
198. abstract — .card-grid — overflow-anchor: none — controlled card row sizing
199. abstract — .card-grid — box-sizing: border-box — controlled card row sizing
200. visual — .empty-state — min-inline-size: 0 — contained empty-state geometry
201. visual — .empty-state — max-inline-size: 100% — contained empty-state geometry
202. visual — .empty-state — text-wrap: pretty — contained empty-state geometry
203. visual — .empty-state — box-sizing: border-box — contained empty-state geometry
204. visual — .empty-state-body — max-inline-size: 56ch — short balanced explanatory text
205. visual — .empty-state-body — margin-inline: auto — short balanced explanatory text
206. visual — .empty-state-body — text-wrap: pretty — short balanced explanatory text
207. visual — .empty-state-body — overflow-wrap: anywhere — short balanced explanatory text
208. visual — .toast — max-inline-size: min(32rem, calc(100vw - 2 * var(--space-4))) — viewport-safe transient feedback
209. visual — .toast — box-sizing: border-box — viewport-safe transient feedback
210. visual — .toast — overflow-wrap: anywhere — viewport-safe transient feedback
211. visual — .toast — text-wrap: pretty — viewport-safe transient feedback
212. abstract — .toast-stack — min-inline-size: 0 — stable transient stack above device chrome
213. abstract — .toast-stack — pointer-events: none — stable transient stack above device chrome
214. abstract — .toast-stack — overflow-anchor: none — stable transient stack above device chrome
215. abstract — .toast-stack — padding-block-end: env(safe-area-inset-bottom) — stable transient stack above device chrome
216. semantic — .flash-alert — min-inline-size: 0 — server feedback cannot reflow the page
217. semantic — .flash-alert — max-inline-size: 100% — server feedback cannot reflow the page
218. semantic — .flash-alert — overflow-wrap: anywhere — server feedback cannot reflow the page
219. semantic — .flash-alert — text-wrap: pretty — server feedback cannot reflow the page
220. semantic — .errors — min-inline-size: 0 — robust validation panel geometry
221. semantic — .errors — max-inline-size: 100% — robust validation panel geometry
222. semantic — .errors — overflow-wrap: anywhere — robust validation panel geometry
223. semantic — .errors — box-sizing: border-box — robust validation panel geometry
224. semantic — .errors-list — margin-block-start: var(--space-2) — controlled semantic error-list indent
225. semantic — .errors-list — padding-inline-start: 1.25em — controlled semantic error-list indent
226. semantic — .errors-list — min-inline-size: 0 — controlled semantic error-list indent
227. semantic — .errors-list — text-wrap: pretty — controlled semantic error-list indent
228. visual — .cookie-banner — min-inline-size: 0 — bounded consent UI
229. visual — .cookie-banner — max-inline-size: min(100%, 72rem) — bounded consent UI
230. visual — .cookie-banner — box-sizing: border-box — bounded consent UI
231. visual — .cookie-banner — overflow-wrap: anywhere — bounded consent UI
232. visual — .install-prompt — min-inline-size: 0 — compact viewport-safe install UI
233. visual — .install-prompt — max-inline-size: min(28rem, calc(100vw - 2 * var(--space-4))) — compact viewport-safe install UI
234. visual — .install-prompt — box-sizing: border-box — compact viewport-safe install UI
235. visual — .install-prompt — overflow-wrap: anywhere — compact viewport-safe install UI
236. semantic — .post-auth-prompt — min-inline-size: 0 — stable guest-auth overlay
237. semantic — .post-auth-prompt — max-inline-size: min(28rem, calc(100vw - 2 * var(--space-4))) — stable guest-auth overlay
238. semantic — .post-auth-prompt — box-sizing: border-box — stable guest-auth overlay
239. semantic — .post-auth-prompt — overflow-wrap: anywhere — stable guest-auth overlay
240. visual — .site-legal-footer — min-inline-size: 0 — legal copy remains inside footer columns
241. visual — .site-legal-footer — overflow-wrap: anywhere — legal copy remains inside footer columns
242. visual — .site-legal-footer — text-wrap: pretty — legal copy remains inside footer columns
243. visual — .site-legal-footer — box-sizing: border-box — legal copy remains inside footer columns
244. visual — footer — min-inline-size: 0 — shared footer containment
245. visual — footer — max-inline-size: 100% — shared footer containment
246. visual — footer — overflow-wrap: anywhere — shared footer containment
247. visual — footer — box-sizing: border-box — shared footer containment
248. optical — figure — margin-inline: 0 — figures align to the reading grid
249. optical — figure — max-inline-size: 100% — figures align to the reading grid
250. optical — figure — text-wrap: pretty — figures align to the reading grid
251. optical — figure — box-sizing: border-box — figures align to the reading grid
252. abstract — table — inline-size: 100% — contained natural table layout
253. abstract — table — max-inline-size: 100% — contained natural table layout
254. abstract — table — table-layout: auto — contained natural table layout
255. abstract — table — box-sizing: border-box — contained natural table layout
256. semantic — th — text-align: start — directional numeric table headings
257. semantic — th — vertical-align: top — directional numeric table headings
258. semantic — th — overflow-wrap: anywhere — directional numeric table headings
259. semantic — th — font-variant-numeric: tabular-nums — directional numeric table headings
260. semantic — td — text-align: start — aligned resilient table values
261. semantic — td — vertical-align: top — aligned resilient table values
262. semantic — td — overflow-wrap: anywhere — aligned resilient table values
263. semantic — td — font-variant-numeric: tabular-nums — aligned resilient table values
264. abstract — pre — max-inline-size: 100% — technical blocks fit without widening pages
265. abstract — pre — overflow: auto — technical blocks fit without widening pages
266. abstract — pre — white-space: pre-wrap — technical blocks fit without widening pages
267. abstract — pre — tab-size: 2 — technical blocks fit without widening pages
268. optical — blockquote — max-inline-size: 66ch — disciplined quotation measure
269. optical — blockquote — margin-inline: auto — disciplined quotation measure
270. optical — blockquote — text-wrap: pretty — disciplined quotation measure
271. optical — blockquote — line-height: 1.55 — disciplined quotation measure
272. abstract — img — max-inline-size: 100% — normalised replaced-element geometry
273. abstract — img — block-size: auto — normalised replaced-element geometry
274. abstract — img — object-fit: cover — normalised replaced-element geometry
275. abstract — img — overflow: clip — normalised replaced-element geometry
276. abstract — svg — max-inline-size: 100% — crisp inline icon geometry
277. abstract — svg — flex: 0 0 auto — crisp inline icon geometry
278. abstract — svg — overflow: visible — crisp inline icon geometry
279. abstract — svg — shape-rendering: geometricPrecision — crisp inline icon geometry
280. abstract — video — max-inline-size: 100% — media stays inside its track
281. abstract — video — block-size: auto — media stays inside its track
282. abstract — video — object-fit: contain — media stays inside its track
283. abstract — video — background: transparent — media stays inside its track
284. abstract — iframe — max-inline-size: 100% — embedded content stays bounded
285. abstract — iframe — border: 0 — embedded content stays bounded
286. abstract — iframe — box-sizing: border-box — embedded content stays bounded
287. abstract — iframe — aspect-ratio: 16 / 9 — embedded content stays bounded
288. optical — .storefront-bol-header — min-inline-size: 0 — commerce masthead alignment
289. optical — .storefront-bol-header — align-items: center — commerce masthead alignment
290. optical — .storefront-bol-header — column-gap: var(--space-3) — commerce masthead alignment
291. optical — .storefront-bol-header — box-sizing: border-box — commerce masthead alignment
292. visual — .storefront-bol-account — display: flex — account/cart grouping
293. visual — .storefront-bol-account — align-items: center — account/cart grouping
294. visual — .storefront-bol-account — gap: var(--space-2) — account/cart grouping
295. visual — .storefront-bol-account — min-inline-size: 0 — account/cart grouping
296. visual — .storefront-bol-mainnav — min-inline-size: 0 — commerce navigation wraps deliberately
297. visual — .storefront-bol-mainnav — display: flex — commerce navigation wraps deliberately
298. visual — .storefront-bol-mainnav — align-items: center — commerce navigation wraps deliberately
299. visual — .storefront-bol-mainnav — gap: var(--space-2) — commerce navigation wraps deliberately
300. visual — .storefront-bol-mainnav — flex-wrap: wrap — commerce navigation wraps deliberately
301. semantic — .storefront-bol-categories — min-inline-size: 0 — stable category disclosure
302. semantic — .storefront-bol-categories — box-sizing: border-box — stable category disclosure
303. semantic — .storefront-bol-categories — overscroll-behavior-block: contain — stable category disclosure
304. semantic — .storefront-bol-categories — scrollbar-gutter: stable — stable category disclosure
305. visual — .storefront-bol-mega — min-inline-size: 0 — bounded catalogue mega menu
306. visual — .storefront-bol-mega — max-inline-size: min(calc(100vw - 2 * var(--space-4)), var(--container-max)) — bounded catalogue mega menu
307. visual — .storefront-bol-mega — box-sizing: border-box — bounded catalogue mega menu
308. visual — .storefront-bol-mega — overflow-wrap: anywhere — bounded catalogue mega menu
309. visual — .storefront-utility — min-inline-size: 0 — stable commerce utility strip
310. visual — .storefront-utility — display: flex — stable commerce utility strip
311. visual — .storefront-utility — align-items: baseline — stable commerce utility strip
312. visual — .storefront-utility — flex-wrap: wrap — stable commerce utility strip
313. visual — .storefront-utility — gap: var(--space-2) var(--space-4) — stable commerce utility strip
314. semantic — #topHalf — min-inline-size: 0 — resilient legacy storefront first row
315. semantic — #topHalf — box-sizing: border-box — resilient legacy storefront first row
316. semantic — #topHalf — display: flex — resilient legacy storefront first row
317. semantic — #topHalf — align-items: center — resilient legacy storefront first row
318. semantic — #topHalf — flex-wrap: wrap — resilient legacy storefront first row
319. semantic — #topHalf — row-gap: var(--space-1) — resilient legacy storefront first row
320. semantic — #bottomHalf — min-inline-size: 0 — resilient storefront secondary row
321. semantic — #bottomHalf — box-sizing: border-box — resilient storefront secondary row
322. semantic — #bottomHalf — display: flex — resilient storefront secondary row
323. semantic — #bottomHalf — align-items: center — resilient storefront secondary row
324. semantic — #bottomHalf — flex-wrap: wrap — resilient storefront secondary row
325. semantic — #bottomHalf — gap: var(--space-2) — resilient storefront secondary row
326. visual — #sections — min-inline-size: 0 — compact storefront section links
327. visual — #sections — display: flex — compact storefront section links
328. visual — #sections — align-items: center — compact storefront section links
329. visual — #sections — gap: var(--space-1) — compact storefront section links
330. visual — #sections — flex-wrap: wrap — compact storefront section links
331. visual — #accountStuff — min-inline-size: 0 — wrap-safe storefront utilities
332. visual — #accountStuff — display: flex — wrap-safe storefront utilities
333. visual — #accountStuff — align-items: center — wrap-safe storefront utilities
334. visual — #accountStuff — gap: var(--space-1) — wrap-safe storefront utilities
335. visual — #accountStuff — flex-wrap: wrap — wrap-safe storefront utilities
336. optical — #navBar — min-inline-size: 0 — single storefront chrome geometry unit
337. optical — #navBar — box-sizing: border-box — single storefront chrome geometry unit
338. optical — #navBar — overflow-wrap: anywhere — single storefront chrome geometry unit
339. optical — #navBar — isolation: isolate — single storefront chrome geometry unit
340. optical — .nav-actions — display: flex — grouped BSDports account actions
341. optical — .nav-actions — align-items: center — grouped BSDports account actions
342. optical — .nav-actions — gap: var(--space-1) — grouped BSDports account actions
343. optical — .nav-actions — flex-wrap: wrap — grouped BSDports account actions