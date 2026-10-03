# Surface micro-refinement matrix — 288 concrete adjustments

Each numbered item maps to one property declaration in _surface_micro_refinements.scss.
The pass is additive and leaves the existing 343-rule layout_micro_refinements contract intact.

001. shared · page ground — background: var(--bg)
002. shared · page ground — color: var(--text)
003. shared · page ground — text-rendering: optimizeLegibility
004. shared · page ground — overscroll-behavior-x: none
005. shared · shell — min-block-size: 100dvh
006. shared · shell — min-inline-size: 0
007. shared · shell — background: var(--bg)
008. shared · shell — isolation: isolate
009. shared · main — min-inline-size: 0
010. shared · main — scroll-margin-block-start: calc(var(--top-band-block, 0px) + var(--nav-swiper-h, 0px) + var(--space-3))
011. shared · main — padding-inline: clamp(var(--space-3), 4vw, var(--space-8))
012. shared · main — padding-block-end: calc(var(--space-12) + var(--safe-bottom))
013. shared · page header — align-items: baseline
014. shared · page header — gap: clamp(var(--space-2), 2vw, var(--space-4))
015. shared · page header — margin-block: 0 var(--space-4)
016. shared · page header — border: 0
017. shared · heading — font-size: clamp(var(--text-lg), 3.2vw, var(--text-2xl))
018. shared · heading — line-height: 1.05
019. shared · heading — letter-spacing: var(--tracking-tight)
020. shared · heading — text-wrap: balance
021. shared · navigation clusters — display: flex
022. shared · navigation clusters — align-items: center
023. shared · navigation clusters — gap: var(--space-1)
024. shared · navigation clusters — flex-wrap: wrap
025. shared · navigation links — min-block-size: var(--tap-min)
026. shared · navigation links — padding-inline: var(--space-2)
027. shared · navigation links — border: 0
028. shared · navigation links — border-radius: var(--radius-pill)
029. shared · chip — min-block-size: 30px
030. shared · chip — padding-inline: var(--space-2)
031. shared · chip — border: 0
032. shared · chip — border-radius: var(--radius-pill)
033. shared · form fields — min-inline-size: 0
034. shared · form fields — margin-block-end: var(--space-4)
035. shared · form fields — gap: var(--space-2)
036. shared · form fields — padding-inline: 0
037. shared · fieldset — border: 0
038. shared · fieldset — padding: 0
039. shared · fieldset — margin: 0
040. shared · fieldset — background: transparent
041. shared · form labels — font-size: var(--text-sm)
042. shared · form labels — line-height: 1.4
043. shared · form labels — font-weight: var(--weight-bold)
044. shared · form labels — letter-spacing: var(--tracking-tight)
045. shared · form controls — border: 0
046. shared · form controls — box-shadow: none
047. shared · form controls — border-radius: 0
048. shared · form controls — background: color-mix(in srgb, var(--surface) 88%, var(--bg))
049. shared · focused controls — outline: var(--focus-ring)
050. shared · focused controls — outline-offset: 2px
051. shared · focused controls — border: 0
052. shared · focused controls — background: var(--surface-elevated)
053. shared · textareas — min-block-size: clamp(7rem, 18vw, 12rem)
054. shared · textareas — resize: vertical
055. shared · textareas — line-height: 1.55
056. shared · textareas — padding-block: var(--space-3)
057. shared · form actions — display: flex
058. shared · form actions — align-items: center
059. shared · form actions — gap: var(--space-2)
060. shared · form actions — flex-wrap: wrap
061. shared · button floor — min-block-size: var(--tap-min)
062. shared · button floor — padding-inline: var(--control-pad-inline)
063. shared · button floor — border: 0
064. shared · button floor — border-radius: var(--radius-pill)
065. shared · primary button — background: var(--accent)
066. shared · primary button — color: var(--accent-ink, var(--bg))
067. shared · primary button — border: 0
068. shared · primary button — font-weight: var(--weight-bold)
069. shared · ghost button — background: transparent
070. shared · ghost button — color: var(--text)
071. shared · ghost button — border: 0
072. shared · ghost button — font-weight: var(--weight-bold)
073. shared · danger button — background: var(--danger)
074. shared · danger button — color: var(--bg)
075. shared · danger button — border: 0
076. shared · danger button — font-weight: var(--weight-bold)
077. shared · compose surface — border: 0
078. shared · compose surface — border-radius: 0
079. shared · compose surface — background: var(--surface)
080. shared · compose surface — overflow: hidden
081. shared · compose input — border: 0
082. shared · compose input — border-radius: 0
083. shared · compose input — background: transparent
084. shared · compose input — min-block-size: clamp(9rem, 24vw, 15rem)
085. shared · tiptap toolbar — display: flex
086. shared · tiptap toolbar — align-items: center
087. shared · tiptap toolbar — gap: var(--space-1)
088. shared · tiptap toolbar — padding-block: var(--space-1)
089. shared · tiptap button — min-inline-size: var(--tap-min)
090. shared · tiptap button — min-block-size: var(--tap-min)
091. shared · tiptap button — border: 0
092. shared · tiptap button — border-radius: var(--radius-xs)
093. shared · character counter — display: block
094. shared · character counter — min-block-size: 1rem
095. shared · character counter — margin-block-start: var(--space-1)
096. shared · character counter — font-variant-numeric: tabular-nums
097. shared · comment form — display: grid
098. shared · comment form — gap: var(--space-2)
099. shared · comment form — margin-block: var(--space-5)
100. shared · comment form — border: 0
101. shared · comment — margin-block: 0
102. shared · comment — padding-block: var(--space-3)
103. shared · comment — padding-inline: 0
104. shared · comment — border: 0
105. shared · comment header — display: flex
106. shared · comment header — align-items: baseline
107. shared · comment header — gap: var(--space-1)
108. shared · comment header — font-size: var(--text-sm)
109. shared · comment body — max-inline-size: 68ch
110. shared · comment body — line-height: 1.55
111. shared · comment body — overflow-wrap: anywhere
112. shared · comment body — color: var(--text)
113. shared · reply disclosure — margin-block: var(--space-2)
114. shared · reply disclosure — padding: 0
115. shared · reply disclosure — border: 0
116. shared · reply disclosure — background: transparent
117. shared · nested comments — min-inline-size: 0
118. shared · nested comments — margin-inline-start: clamp(var(--space-3), 4vw, var(--space-6))
119. shared · nested comments — padding-inline-start: var(--space-2)
120. shared · nested comments — border-inline-start: 0
121. shared · post card ground — background: transparent
122. shared · post card ground — border: 0
123. shared · post card ground — border-radius: 0
124. shared · post card ground — box-shadow: none
125. shared · reading layout — grid-template-columns: 48px minmax(0, 1fr)
126. shared · reading layout — gap: clamp(var(--space-2), 2vw, var(--space-4))
127. shared · reading layout — min-inline-size: 0
128. shared · reading layout — align-items: start
129. shared · reading text — max-inline-size: 74ch
130. shared · reading text — line-height: 1.45
131. shared · reading text — text-wrap: pretty
132. shared · reading text — overflow-wrap: anywhere
133. shared · action row — display: flex
134. shared · action row — align-items: center
135. shared · action row — gap: var(--space-1)
136. shared · action row — border: 0
137. shared · vote rail — inline-size: 48px
138. shared · vote rail — top: calc(var(--top-band-block, 0px) + var(--space-3))
139. shared · vote rail — gap: 0
140. shared · vote rail — justify-items: center
141. shared · vote button — inline-size: var(--tap-min)
142. shared · vote button — block-size: var(--tap-min)
143. shared · vote button — border: 0
144. shared · vote button — border-radius: 50%
145. shared · chat minimal shell — box-sizing: border-box
146. shared · chat minimal shell — border: 0
147. shared · chat minimal shell — border-radius: 0
148. shared · chat minimal shell — box-shadow: none
149. shared · chat controls — min-block-size: var(--tap-min)
150. shared · chat controls — border: 0
151. shared · chat controls — border-radius: 0
152. shared · chat controls — box-shadow: none
153. radio · home shell — max-inline-size: 72rem
154. radio · home shell — margin-inline: auto
155. radio · home shell — padding-inline: clamp(var(--space-3), 5vw, var(--space-8))
156. radio · home shell — min-inline-size: 0
157. radio · home header — display: grid
158. radio · home header — gap: clamp(var(--space-3), 3vw, var(--space-6))
159. radio · home header — align-items: end
160. radio · home header — padding-block-end: var(--space-5)
161. radio · navigation — display: flex
162. radio · navigation — align-items: center
163. radio · navigation — gap: var(--space-1)
164. radio · navigation — flex-wrap: wrap
165. radio · featured — margin-block: 0 var(--space-8)
166. radio · featured — padding: 0
167. radio · featured — border: 0
168. radio · featured — background: transparent
169. radio · section header — display: flex
170. radio · section header — align-items: end
171. radio · section header — justify-content: space-between
172. radio · section header — gap: var(--space-3)
173. radio · lists — display: grid
174. radio · lists — gap: 1px
175. radio · lists — padding: 0
176. radio · lists — margin: 0
177. radio · track card — display: grid
178. radio · track card — grid-template-columns: minmax(0, 1fr) auto
179. radio · track card — align-items: center
180. radio · track card — gap: var(--space-2)
181. radio · track main — display: grid
182. radio · track main — grid-template-columns: 64px minmax(0, 1fr)
183. radio · track main — align-items: center
184. radio · track main — gap: var(--space-3)
185. radio · track art — inline-size: 64px
186. radio · track art — aspect-ratio: 1
187. radio · track art — background: var(--surface-elevated)
188. radio · track art — border-radius: 0
189. radio · track copy — min-inline-size: 0
190. radio · track copy — display: grid
191. radio · track copy — gap: 4px
192. radio · track copy — line-height: 1.2
193. radio · share — min-block-size: var(--tap-min)
194. radio · share — padding-inline: var(--space-2)
195. radio · share — border: 0
196. radio · share — background: transparent
197. radio · player shell — max-inline-size: 72rem
198. radio · player shell — margin-inline: auto
199. radio · player shell — padding-inline: clamp(var(--space-3), 4vw, var(--space-8))
200. radio · player shell — border: 0
201. radio · player stage — aspect-ratio: 16 / 9
202. radio · player stage — min-block-size: min(50dvh, 36rem)
203. radio · player stage — overflow: hidden
204. radio · player stage — border-radius: 0
205. radio · queue — display: grid
206. radio · queue — gap: 0
207. radio · queue — margin-block: var(--space-5)
208. radio · queue — border: 0
209. radio · queue item — display: grid
210. radio · queue item — grid-template-columns: 2rem 48px minmax(0, 1fr)
211. radio · queue item — align-items: center
212. radio · queue item — min-block-size: 64px
213. radio · now playing — display: flex
214. radio · now playing — align-items: center
215. radio · now playing — gap: var(--space-2)
216. radio · now playing — min-block-size: var(--tap-min)
217. market · storefront frame — min-inline-size: 0
218. market · storefront frame — background: var(--bg)
219. market · storefront frame — border: 0
220. market · storefront frame — box-shadow: none
221. market · header — min-inline-size: 0
222. market · header — gap: clamp(var(--space-2), 2vw, var(--space-4))
223. market · header — align-items: center
224. market · header — background: transparent
225. market · brand — min-inline-size: 0
226. market · brand — border: 0
227. market · brand — background: transparent
228. market · brand — text-decoration: none
229. market · account row — display: flex
230. market · account row — align-items: center
231. market · account row — gap: var(--space-1)
232. market · account row — min-block-size: var(--tap-min)
233. market · search — min-inline-size: 0
234. market · search — width: 100%
235. market · search — background: transparent
236. market · search — border: 0
237. market · main nav — display: flex
238. market · main nav — align-items: center
239. market · main nav — gap: var(--space-2)
240. market · main nav — border: 0
241. market · mega menu — display: grid
242. market · mega menu — grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr))
243. market · mega menu — gap: var(--space-4)
244. market · mega menu — border: 0
245. market · hero — display: grid
246. market · hero — grid-template-columns: minmax(0, 1.15fr) minmax(12rem, .85fr)
247. market · hero — gap: clamp(var(--space-4), 5vw, var(--space-8))
248. market · hero — border: 0
249. market · hero copy — display: grid
250. market · hero copy — align-content: center
251. market · hero copy — gap: var(--space-2)
252. market · hero copy — max-inline-size: 54ch
253. market · hero media — aspect-ratio: 4 / 3
254. market · hero media — overflow: hidden
255. market · hero media — border-radius: 0
256. market · hero media — background: var(--surface-elevated)
257. market · kind tabs — display: flex
258. market · kind tabs — gap: var(--space-1)
259. market · kind tabs — overflow-x: auto
260. market · kind tabs — border: 0
261. market · catalogue — min-inline-size: 0
262. market · catalogue — gap: clamp(var(--space-3), 3vw, var(--space-6))
263. market · catalogue — align-items: start
264. market · catalogue — border: 0
265. market · filters — min-inline-size: 0
266. market · filters — background: transparent
267. market · filters — border: 0
268. market · filters — box-shadow: none
269. market · filter controls — display: flex
270. market · filter controls — flex-wrap: wrap
271. market · filter controls — gap: var(--space-1)
272. market · filter controls — min-inline-size: 0
273. market · results — min-inline-size: 0
274. market · results — max-inline-size: 100%
275. market · results — margin-inline: 0
276. market · results — padding-inline: 0
277. market · deal card — border: 0
278. market · deal card — border-radius: 0
279. market · deal card — box-shadow: none
280. market · deal card — background: transparent
281. market · deal content — min-inline-size: 0
282. market · deal content — gap: var(--space-1)
283. market · deal content — border: 0
284. market · deal content — box-shadow: none
285. market · pdp family — min-inline-size: 0
286. market · pdp family — border: 0
287. market · pdp family — box-shadow: none
288. market · pdp family — border-radius: 0

## Archaeology-informed rules

- Keep useful old brgen information density; remove Bootstrap-era boxes, shadows and redundant action chrome.
- Keep Amber's editorial pacing and strong hierarchy; discard gradients, filters and decorative elevation.
- Keep the player + queue + sharing/comments idea as one Radio surface.
- Keep pub3's fullscreen visualizer discipline: safe areas, tiny functional chrome, flat surfaces and reduced motion.
- Preserve marketplace discovery, filters, seller identity and a clear purchase action; use spacing and imagery instead of nested boxes.
