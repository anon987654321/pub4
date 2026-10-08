# Surface micro-refinement matrix II

This pass adds four explicit property refinements to each selector below.

001. shared — .flash, .flash-alert — padding-block: var(--space-2)
002. shared — .flash, .flash-alert — margin-block: var(--space-2)
003. shared — .flash, .flash-alert — line-height: 1.35
004. shared — .flash, .flash-alert — min-inline-size: 0
005. shared — .errors — border: 0
006. shared — .errors — border-radius: 0
007. shared — .errors — box-shadow: none
008. shared — .errors — background: transparent
009. shared — .errors-list — font-size: var(--text-sm)
010. shared — .errors-list — line-height: 1.4
011. shared — .errors-list — overflow-wrap: anywhere
012. shared — .errors-list — text-wrap: pretty
013. shared — .auth-form-footer — min-inline-size: 0
014. shared — .auth-form-footer — display: flex
015. shared — .auth-form-footer — align-items: center
016. shared — .auth-form-footer — gap: var(--space-2)
017. shared — .oauth-links — min-inline-size: 0
018. shared — .oauth-links — display: grid
019. shared — .oauth-links — gap: var(--space-2)
020. shared — .oauth-links — align-content: start
021. shared — .oauth-button — min-block-size: var(--tap-min)
022. shared — .oauth-button — min-inline-size: var(--tap-min)
023. shared — .oauth-button — padding-inline: var(--space-2)
024. shared — .oauth-button — border: 0
025. shared — .oauth-button::before — border: 0
026. shared — .oauth-button::before — border-radius: 0
027. shared — .oauth-button::before — box-shadow: none
028. shared — .oauth-button::before — background: transparent
029. shared — .oauth-button::after — font-size: var(--text-sm)
030. shared — .oauth-button::after — line-height: 1.4
031. shared — .oauth-button::after — overflow-wrap: anywhere
032. shared — .oauth-button::after — text-wrap: pretty
033. shared — .oauth-divider — min-inline-size: 0
034. shared — .oauth-divider — display: flex
035. shared — .oauth-divider — align-items: center
036. shared — .oauth-divider — gap: var(--space-2)
037. shared — .auth-form-qr — min-inline-size: 0
038. shared — .auth-form-qr — display: grid
039. shared — .auth-form-qr — gap: var(--space-2)
040. shared — .auth-form-qr — align-content: start
041. chat — .link-preview — min-inline-size: 0
042. chat — .link-preview — display: grid
043. chat — .link-preview — gap: var(--space-2)
044. chat — .link-preview — align-content: start
045. chat — .link-preview-body — font-size: var(--text-sm)
046. chat — .link-preview-body — line-height: 1.4
047. chat — .link-preview-body — overflow-wrap: anywhere
048. chat — .link-preview-body — text-wrap: pretty
049. chat — .msg-actions — border: 0
050. chat — .msg-actions — border-radius: 0
051. chat — .msg-actions — box-shadow: none
052. chat — .msg-actions — background: transparent
053. chat — .msg-action — min-block-size: var(--tap-min)
054. chat — .msg-action — min-inline-size: var(--tap-min)
055. chat — .msg-action — padding-inline: var(--space-2)
056. chat — .msg-action — border: 0
057. chat — .msg-forwarded — font-size: var(--text-sm)
058. chat — .msg-forwarded — line-height: 1.4
059. chat — .msg-forwarded — overflow-wrap: anywhere
060. chat — .msg-forwarded — text-wrap: pretty
061. chat — .msg-reply-context — font-size: var(--text-sm)
062. chat — .msg-reply-context — line-height: 1.4
063. chat — .msg-reply-context — overflow-wrap: anywhere
064. chat — .msg-reply-context — text-wrap: pretty
065. chat — .expiry-chip — font-size: var(--text-sm)
066. chat — .expiry-chip — line-height: 1.4
067. chat — .expiry-chip — overflow-wrap: anywhere
068. chat — .expiry-chip — text-wrap: pretty
069. chat — .edited-mark — font-size: var(--text-sm)
070. chat — .edited-mark — line-height: 1.4
071. chat — .edited-mark — overflow-wrap: anywhere
072. chat — .edited-mark — text-wrap: pretty
073. chat — .conversation-log — display: grid
074. chat — .conversation-log — gap: 0
075. chat — .conversation-log — min-inline-size: 0
076. chat — .conversation-log — margin: 0
077. chat — .conversation-log > li — padding-block: var(--space-2)
078. chat — .conversation-log > li — margin-block: var(--space-2)
079. chat — .conversation-log > li — line-height: 1.35
080. chat — .conversation-log > li — min-inline-size: 0
081. chat — .messenger-composer-box — min-inline-size: 0
082. chat — .messenger-composer-box — display: grid
083. chat — .messenger-composer-box — gap: var(--space-2)
084. chat — .messenger-composer-box — align-content: start
085. chat — .messenger-composer-tool — min-block-size: var(--tap-min)
086. chat — .messenger-composer-tool — min-inline-size: var(--tap-min)
087. chat — .messenger-composer-tool — padding-inline: var(--space-2)
088. chat — .messenger-composer-tool — border: 0
089. chat — .messenger-composer-field — min-inline-size: 0
090. chat — .messenger-composer-field — display: grid
091. chat — .messenger-composer-field — gap: var(--space-2)
092. chat — .messenger-composer-field — align-content: start
093. chat — .messenger-composer-field .char-counter — font-size: var(--text-sm)
094. chat — .messenger-composer-field .char-counter — line-height: 1.4
095. chat — .messenger-composer-field .char-counter — overflow-wrap: anywhere
096. chat — .messenger-composer-field .char-counter — text-wrap: pretty
097. chat — .messenger-composer-send — min-block-size: var(--tap-min)
098. chat — .messenger-composer-send — min-inline-size: var(--tap-min)
099. chat — .messenger-composer-send — padding-inline: var(--space-2)
100. chat — .messenger-composer-send — border: 0
101. chat — .channel-composer — min-inline-size: 0
102. chat — .channel-composer — display: grid
103. chat — .channel-composer — gap: var(--space-2)
104. chat — .channel-composer — align-content: start
105. chat — .channel-composer .field — min-inline-size: 0
106. chat — .channel-composer .field — display: grid
107. chat — .channel-composer .field — gap: var(--space-2)
108. chat — .channel-composer .field — align-content: start
109. chat — .channel-composer textarea — padding-block: var(--space-2)
110. chat — .channel-composer textarea — margin-block: var(--space-2)
111. chat — .channel-composer textarea — line-height: 1.35
112. chat — .channel-composer textarea — min-inline-size: 0
113. chat — .msg_reaction_picker — min-inline-size: 0
114. chat — .msg_reaction_picker — display: flex
115. chat — .msg_reaction_picker — align-items: center
116. chat — .msg_reaction_picker — gap: var(--space-2)
117. chat — .channel_presence — min-inline-size: 0
118. chat — .channel_presence — display: flex
119. chat — .channel_presence — align-items: center
120. chat — .channel_presence — gap: var(--space-2)
121. ads — .ad-slot — border: 0
122. ads — .ad-slot — border-radius: 0
123. ads — .ad-slot — box-shadow: none
124. ads — .ad-slot — background: transparent
125. ads — .ad-slot-label — font-size: var(--text-sm)
126. ads — .ad-slot-label — line-height: 1.4
127. ads — .ad-slot-label — overflow-wrap: anywhere
128. ads — .ad-slot-label — text-wrap: pretty
129. ads — .store-promo — border: 0
130. ads — .store-promo — border-radius: 0
131. ads — .store-promo — box-shadow: none
132. ads — .store-promo — background: transparent
133. ads — .store-promo-copy — min-inline-size: 0
134. ads — .store-promo-copy — display: grid
135. ads — .store-promo-copy — gap: var(--space-2)
136. ads — .store-promo-copy — align-content: start
137. ads — .store-promo-badge — min-block-size: var(--tap-min)
138. ads — .store-promo-badge — min-inline-size: var(--tap-min)
139. ads — .store-promo-badge — padding-inline: var(--space-2)
140. ads — .store-promo-badge — border: 0
141. ads — .store-promo-offer — font-size: var(--text-sm)
142. ads — .store-promo-offer — line-height: 1.4
143. ads — .store-promo-offer — overflow-wrap: anywhere
144. ads — .store-promo-offer — text-wrap: pretty
145. ads — .store-promo-cta — min-block-size: var(--tap-min)
146. ads — .store-promo-cta — min-inline-size: var(--tap-min)
147. ads — .store-promo-cta — padding-inline: var(--space-2)
148. ads — .store-promo-cta — border: 0
149. ads — .store-promo-art — border: 0
150. ads — .store-promo-art — border-radius: 0
151. ads — .store-promo-art — box-shadow: none
152. ads — .store-promo-art — background: transparent
153. ads — .store-promo-product — max-inline-size: 100%
154. ads — .store-promo-product — display: block
155. ads — .store-promo-product — object-fit: contain
156. ads — .store-promo-product — border-radius: 0
157. ads — .store-promo-art-placeholder — border: 0
158. ads — .store-promo-art-placeholder — border-radius: 0
159. ads — .store-promo-art-placeholder — box-shadow: none
160. ads — .store-promo-art-placeholder — background: transparent
161. brgen — .brgen-vertical-promo — border: 0
162. brgen — .brgen-vertical-promo — border-radius: 0
163. brgen — .brgen-vertical-promo — box-shadow: none
164. brgen — .brgen-vertical-promo — background: transparent
165. brgen — .brgen-vertical-promo__link — min-inline-size: 0
166. brgen — .brgen-vertical-promo__link — display: grid
167. brgen — .brgen-vertical-promo__link — gap: var(--space-2)
168. brgen — .brgen-vertical-promo__link — align-content: start
169. brgen — .brgen-vertical-promo__copy — min-inline-size: 0
170. brgen — .brgen-vertical-promo__copy — display: grid
171. brgen — .brgen-vertical-promo__copy — gap: var(--space-2)
172. brgen — .brgen-vertical-promo__copy — align-content: start
173. brgen — .brgen-vertical-promo__title — font-size: var(--text-sm)
174. brgen — .brgen-vertical-promo__title — line-height: 1.4
175. brgen — .brgen-vertical-promo__title — overflow-wrap: anywhere
176. brgen — .brgen-vertical-promo__title — text-wrap: pretty
177. brgen — .brgen-vertical-promo__body — font-size: var(--text-sm)
178. brgen — .brgen-vertical-promo__body — line-height: 1.4
179. brgen — .brgen-vertical-promo__body — overflow-wrap: anywhere
180. brgen — .brgen-vertical-promo__body — text-wrap: pretty
181. brgen — .home-feed-views — min-inline-size: 0
182. brgen — .home-feed-views — display: flex
183. brgen — .home-feed-views — align-items: center
184. brgen — .home-feed-views — gap: var(--space-2)
185. brgen — .home-feed-view — min-block-size: var(--tap-min)
186. brgen — .home-feed-view — min-inline-size: var(--tap-min)
187. brgen — .home-feed-view — padding-inline: var(--space-2)
188. brgen — .home-feed-view — border: 0
189. brgen — .listing-published-notice — min-inline-size: 0
190. brgen — .listing-published-notice — display: flex
191. brgen — .listing-published-notice — align-items: center
192. brgen — .listing-published-notice — gap: var(--space-2)
193. brgen — .marketplace-actions — min-inline-size: 0
194. brgen — .marketplace-actions — display: flex
195. brgen — .marketplace-actions — align-items: center
196. brgen — .marketplace-actions — gap: var(--space-2)
197. brgen — .feed-hint — font-size: var(--text-sm)
198. brgen — .feed-hint — line-height: 1.4
199. brgen — .feed-hint — overflow-wrap: anywhere
200. brgen — .feed-hint — text-wrap: pretty
201. amber — .amber-message — min-inline-size: 0
202. amber — .amber-message — display: grid
203. amber — .amber-message — gap: var(--space-2)
204. amber — .amber-message — align-content: start
205. amber — .amber-message--mine — border: 0
206. amber — .amber-message--mine — border-radius: 0
207. amber — .amber-message--mine — box-shadow: none
208. amber — .amber-message--mine — background: transparent
209. amber — .amber-message > header — font-size: var(--text-sm)
210. amber — .amber-message > header — line-height: 1.4
211. amber — .amber-message > header — overflow-wrap: anywhere
212. amber — .amber-message > header — text-wrap: pretty
213. amber — .amber-message > p — font-size: var(--text-sm)
214. amber — .amber-message > p — line-height: 1.4
215. amber — .amber-message > p — overflow-wrap: anywhere
216. amber — .amber-message > p — text-wrap: pretty
217. amber — .amber-looks — display: grid
218. amber — .amber-looks — gap: 0
219. amber — .amber-looks — min-inline-size: 0
220. amber — .amber-looks — margin: 0
221. amber — .amber-look — min-inline-size: 0
222. amber — .amber-look — display: grid
223. amber — .amber-look — gap: var(--space-2)
224. amber — .amber-look — align-content: start
225. amber — .amber-look-title — font-size: var(--text-sm)
226. amber — .amber-look-title — line-height: 1.4
227. amber — .amber-look-title — overflow-wrap: anywhere
228. amber — .amber-look-title — text-wrap: pretty
229. amber — .amber-look-track — min-inline-size: 0
230. amber — .amber-look-track — display: flex
231. amber — .amber-look-track — align-items: center
232. amber — .amber-look-track — gap: var(--space-2)
233. amber — .amber-look-slide — padding-block: var(--space-2)
234. amber — .amber-look-slide — margin-block: var(--space-2)
235. amber — .amber-look-slide — line-height: 1.35
236. amber — .amber-look-slide — min-inline-size: 0
237. amber — .amber-look-slide figcaption — min-inline-size: 0
238. amber — .amber-look-slide figcaption — display: flex
239. amber — .amber-look-slide figcaption — align-items: center
240. amber — .amber-look-slide figcaption — gap: var(--space-2)
241. amber — .weather-bar — padding-block: var(--space-2)
242. amber — .weather-bar — margin-block: var(--space-2)
243. amber — .weather-bar — line-height: 1.35
244. amber — .weather-bar — min-inline-size: 0
245. amber — .dash-stats — min-inline-size: 0
246. amber — .dash-stats — display: grid
247. amber — .dash-stats — gap: var(--space-2)
248. amber — .dash-stats — align-content: start
249. amber — .dash-stats dl — display: grid
250. amber — .dash-stats dl — gap: 0
251. amber — .dash-stats dl — min-inline-size: 0
252. amber — .dash-stats dl — margin: 0
253. amber — .dash-stats dl > div — padding-block: var(--space-2)
254. amber — .dash-stats dl > div — margin-block: var(--space-2)
255. amber — .dash-stats dl > div — line-height: 1.35
256. amber — .dash-stats dl > div — min-inline-size: 0
257. amber — .plan-list, .cpw-list — display: grid
258. amber — .plan-list, .cpw-list — gap: 0
259. amber — .plan-list, .cpw-list — min-inline-size: 0
260. amber — .plan-list, .cpw-list — margin: 0
261. amber — .plan-row, .cpw-row — min-inline-size: 0
262. amber — .plan-row, .cpw-row — display: flex
263. amber — .plan-row, .cpw-row — align-items: center
264. amber — .plan-row, .cpw-row — gap: var(--space-2)
265. amber — .nested-form — min-inline-size: 0
266. amber — .nested-form — display: grid
267. amber — .nested-form — gap: var(--space-2)
268. amber — .nested-form — align-content: start
269. amber — .wardrobe-action-group — min-inline-size: 0
270. amber — .wardrobe-action-group — display: flex
271. amber — .wardrobe-action-group — align-items: center
272. amber — .wardrobe-action-group — gap: var(--space-2)
273. amber — .wardrobe-more-tools .wardrobe-action-group — border: 0
274. amber — .wardrobe-more-tools .wardrobe-action-group — border-radius: 0
275. amber — .wardrobe-more-tools .wardrobe-action-group — box-shadow: none
276. amber — .wardrobe-more-tools .wardrobe-action-group — background: transparent
277. amber — .item-grid, .items-grid — display: grid
278. amber — .item-grid, .items-grid — gap: 0
279. amber — .item-grid, .items-grid — min-inline-size: 0
280. amber — .item-grid, .items-grid — margin: 0
281. amber — .item-card — border: 0
282. amber — .item-card — border-radius: 0
283. amber — .item-card — box-shadow: none
284. amber — .item-card — background: transparent
285. amber — .item-card .item-photo — max-inline-size: 100%
286. amber — .item-card .item-photo — display: block
287. amber — .item-card .item-photo — object-fit: contain
288. amber — .item-card .item-photo — border-radius: 0
289. amber — .item-card .item-title — font-size: var(--text-sm)
290. amber — .item-card .item-title — line-height: 1.4
291. amber — .item-card .item-title — overflow-wrap: anywhere
292. amber — .item-card .item-title — text-wrap: pretty
293. amber — .ai-card — border: 0
294. amber — .ai-card — border-radius: 0
295. amber — .ai-card — box-shadow: none
296. amber — .ai-card — background: transparent
297. amber — .form .actions — min-inline-size: 0
298. amber — .form .actions — display: flex
299. amber — .form .actions — align-items: center
300. amber — .form .actions — gap: var(--space-2)
301. amber — .form-note, .form-help — font-size: var(--text-sm)
302. amber — .form-note, .form-help — line-height: 1.4
303. amber — .form-note, .form-help — overflow-wrap: anywhere
304. amber — .form-note, .form-help — text-wrap: pretty
305. market — .listing-step — border: 0
306. market — .listing-step — border-radius: 0
307. market — .listing-step — box-shadow: none
308. market — .listing-step — background: transparent
309. market — .listing-step-actions — min-inline-size: 0
310. market — .listing-step-actions — display: flex
311. market — .listing-step-actions — align-items: center
312. market — .listing-step-actions — gap: var(--space-2)
313. market — .listing-source-choice — min-inline-size: 0
314. market — .listing-source-choice — display: flex
315. market — .listing-source-choice — align-items: center
316. market — .listing-source-choice — gap: var(--space-2)
317. market — .listing-source-option — min-block-size: var(--tap-min)
318. market — .listing-source-option — min-inline-size: var(--tap-min)
319. market — .listing-source-option — padding-inline: var(--space-2)
320. market — .listing-source-option — border: 0
321. market — .listing-photo-camera, .listing-photo-gallery — min-block-size: var(--tap-min)
322. market — .listing-photo-camera, .listing-photo-gallery — min-inline-size: var(--tap-min)
323. market — .listing-photo-camera, .listing-photo-gallery — padding-inline: var(--space-2)
324. market — .listing-photo-camera, .listing-photo-gallery — border: 0
325. market — .listing-photo-guidance — min-inline-size: 0
326. market — .listing-photo-guidance — display: flex
327. market — .listing-photo-guidance — align-items: center
328. market — .listing-photo-guidance — gap: var(--space-2)
329. market — .listing-media-preview, [data-media-picker-target=preview] — display: grid
330. market — .listing-media-preview, [data-media-picker-target=preview] — gap: 0
331. market — .listing-media-preview, [data-media-picker-target=preview] — min-inline-size: 0
332. market — .listing-media-preview, [data-media-picker-target=preview] — margin: 0
333. market — .listing-location-row — min-inline-size: 0
334. market — .listing-location-row — display: grid
335. market — .listing-location-row — gap: var(--space-2)
336. market — .listing-location-row — align-content: start
337. market — .advanced-fields — padding-block: var(--space-2)
338. market — .advanced-fields — margin-block: var(--space-2)
339. market — .advanced-fields — line-height: 1.35
340. market — .advanced-fields — min-inline-size: 0
341. market — .marketplace-listing-header — min-inline-size: 0
342. market — .marketplace-listing-header — display: flex
343. market — .marketplace-listing-header — align-items: center
344. market — .marketplace-listing-header — gap: var(--space-2)
345. market — .listing-price, .store-buybox-price — font-size: var(--text-sm)
346. market — .listing-price, .store-buybox-price — line-height: 1.4
347. market — .listing-price, .store-buybox-price — overflow-wrap: anywhere
348. market — .listing-price, .store-buybox-price — text-wrap: pretty
349. market — .listing-status — font-size: var(--text-sm)
350. market — .listing-status — line-height: 1.4
351. market — .listing-status — overflow-wrap: anywhere
352. market — .listing-status — text-wrap: pretty
353. market — .listing-delivery — font-size: var(--text-sm)
354. market — .listing-delivery — line-height: 1.4
355. market — .listing-delivery — overflow-wrap: anywhere
356. market — .listing-delivery — text-wrap: pretty
357. market — .cart-item — min-inline-size: 0
358. market — .cart-item — display: grid
359. market — .cart-item — gap: var(--space-2)
360. market — .cart-item — align-content: start
361. market — .cart-item-sum — min-inline-size: 0
362. market — .cart-item-sum — display: grid
363. market — .cart-item-sum — gap: var(--space-2)
364. market — .cart-item-sum — align-content: start
365. market — .cart-summary — border: 0
366. market — .cart-summary — border-radius: 0
367. market — .cart-summary — box-shadow: none
368. market — .cart-summary — background: transparent
369. market — .cart-pay-actions — min-inline-size: 0
370. market — .cart-pay-actions — display: grid
371. market — .cart-pay-actions — gap: var(--space-2)
372. market — .cart-pay-actions — align-content: start
373. market — .cart-address — min-inline-size: 0
374. market — .cart-address — display: grid
375. market — .cart-address — gap: var(--space-2)
376. market — .cart-address — align-content: start
377. market — .store-badge, .deal-badge — min-block-size: var(--tap-min)
378. market — .store-badge, .deal-badge — min-inline-size: var(--tap-min)
379. market — .store-badge, .deal-badge — padding-inline: var(--space-2)
380. market — .store-badge, .deal-badge — border: 0
381. market — .deal-card-subtitle — font-size: var(--text-sm)
382. market — .deal-card-subtitle — line-height: 1.4
383. market — .deal-card-subtitle — overflow-wrap: anywhere
384. market — .deal-card-subtitle — text-wrap: pretty
385. market — .marketplace-deal — min-inline-size: 0
386. market — .marketplace-deal — display: grid
387. market — .marketplace-deal — gap: var(--space-2)
388. market — .marketplace-deal — align-content: start
389. market — .deal-listing — min-inline-size: 0
390. market — .deal-listing — display: grid
391. market — .deal-listing — gap: var(--space-2)
392. market — .deal-listing — align-content: start
393. market — .store-breadcrumb — min-inline-size: 0
394. market — .store-breadcrumb — display: flex
395. market — .store-breadcrumb — align-items: center
396. market — .store-breadcrumb — gap: var(--space-2)
397. market — .store-pdp-media — border: 0
398. market — .store-pdp-media — border-radius: 0
399. market — .store-pdp-media — box-shadow: none
400. market — .store-pdp-media — background: transparent
401. market — .listing-video — max-inline-size: 100%
402. market — .listing-video — display: block
403. market — .listing-video — object-fit: contain
404. market — .listing-video — border-radius: 0
405. market — .listing-questions, .listing-question — min-inline-size: 0
406. market — .listing-questions, .listing-question — display: grid
407. market — .listing-questions, .listing-question — gap: var(--space-2)
408. market — .listing-questions, .listing-question — align-content: start
409. market — .section-divider — border: 0
410. market — .section-divider — border-radius: 0
411. market — .section-divider — box-shadow: none
412. market — .section-divider — background: transparent
413. market — .store-results-head — min-inline-size: 0
414. market — .store-results-head — display: flex
415. market — .store-results-head — align-items: center
416. market — .store-results-head — gap: var(--space-2)
417. radio — .playlist-top, .radio-header — min-inline-size: 0
418. radio — .playlist-top, .radio-header — display: flex
419. radio — .playlist-top, .radio-header — align-items: center
420. radio — .playlist-top, .radio-header — gap: var(--space-2)
421. radio — .playlist-top-action — min-block-size: var(--tap-min)
422. radio — .playlist-top-action — min-inline-size: var(--tap-min)
423. radio — .playlist-top-action — padding-inline: var(--space-2)
424. radio — .playlist-top-action — border: 0
425. radio — .radio-overlay — min-inline-size: 0
426. radio — .radio-overlay — display: grid
427. radio — .radio-overlay — gap: var(--space-2)
428. radio — .radio-overlay — align-content: start
429. radio — .radio-start-hint — font-size: var(--text-sm)
430. radio — .radio-start-hint — line-height: 1.4
431. radio — .radio-start-hint — overflow-wrap: anywhere
432. radio — .radio-start-hint — text-wrap: pretty
433. radio — .radio-nav — min-inline-size: 0
434. radio — .radio-nav — display: flex
435. radio — .radio-nav — align-items: center
436. radio — .radio-nav — gap: var(--space-2)
437. radio — .radio-library-item, .playlist-row — min-block-size: var(--tap-min)
438. radio — .radio-library-item, .playlist-row — min-inline-size: var(--tap-min)
439. radio — .radio-library-item, .playlist-row — padding-inline: var(--space-2)
440. radio — .radio-library-item, .playlist-row — border: 0
441. radio — .playlist-comment-form — min-inline-size: 0
442. radio — .playlist-comment-form — display: flex
443. radio — .playlist-comment-form — align-items: center
444. radio — .playlist-comment-form — gap: var(--space-2)
445. radio — .playlist-comment — min-inline-size: 0
446. radio — .playlist-comment — display: grid
447. radio — .playlist-comment — gap: var(--space-2)
448. radio — .playlist-comment — align-content: start
449. radio — .playlist-comment .time — font-size: var(--text-sm)
450. radio — .playlist-comment .time — line-height: 1.4
451. radio — .playlist-comment .time — overflow-wrap: anywhere
452. radio — .playlist-comment .time — text-wrap: pretty
453. radio — .playlist-comment .text — font-size: var(--text-sm)
454. radio — .playlist-comment .text — line-height: 1.4
455. radio — .playlist-comment .text — overflow-wrap: anywhere
456. radio — .playlist-comment .text — text-wrap: pretty
457. radio — .playlist-embed-frame — max-inline-size: 100%
458. radio — .playlist-embed-frame — display: block
459. radio — .playlist-embed-frame — object-fit: contain
460. radio — .playlist-embed-frame — border-radius: 0
461. radio — .playlist-queue-heading — font-size: var(--text-sm)
462. radio — .playlist-queue-heading — line-height: 1.4
463. radio — .playlist-queue-heading — overflow-wrap: anywhere
464. radio — .playlist-queue-heading — text-wrap: pretty
465. radio — .playlist-queue-index — font-size: var(--text-sm)
466. radio — .playlist-queue-index — line-height: 1.4
467. radio — .playlist-queue-index — overflow-wrap: anywhere
468. radio — .playlist-queue-index — text-wrap: pretty
469. radio — .playlist-queue-art — max-inline-size: 100%
470. radio — .playlist-queue-art — display: block
471. radio — .playlist-queue-art — object-fit: contain
472. radio — .playlist-queue-art — border-radius: 0
473. radio — .playlist-queue-meta — min-inline-size: 0
474. radio — .playlist-queue-meta — display: grid
475. radio — .playlist-queue-meta — gap: var(--space-2)
476. radio — .playlist-queue-meta — align-content: start
477. radio — .playlist-queue-item — border: 0
478. radio — .playlist-queue-item — border-radius: 0
479. radio — .playlist-queue-item — box-shadow: none
480. radio — .playlist-queue-item — background: transparent
481. radio — .playlist-add-comment — min-block-size: var(--tap-min)
482. radio — .playlist-add-comment — min-inline-size: var(--tap-min)
483. radio — .playlist-add-comment — padding-inline: var(--space-2)
484. radio — .playlist-add-comment — border: 0
485. radio — .radio-now-playing — padding-block: var(--space-2)
486. radio — .radio-now-playing — margin-block: var(--space-2)
487. radio — .radio-now-playing — line-height: 1.35
488. radio — .radio-now-playing — min-inline-size: 0
489. radio — .radio-track-display — font-size: var(--text-sm)
490. radio — .radio-track-display — line-height: 1.4
491. radio — .radio-track-display — overflow-wrap: anywhere
492. radio — .radio-track-display — text-wrap: pretty
493. radio — .playlist-stage — border: 0
494. radio — .playlist-stage — border-radius: 0
495. radio — .playlist-stage — box-shadow: none
496. radio — .playlist-stage — background: transparent
