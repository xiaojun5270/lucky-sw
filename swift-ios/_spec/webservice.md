# Web 服务 (webservice) — exact behavioural spec for 1:1 SwiftUI port

Source of truth:
- Screen: `C:\Users\xiaoj\Desktop\lucky\app\webservice.tsx` (3209 lines)
- Service: `C:\Users\xiaoj\Desktop\lucky\src\services\webservice.ts` (568 lines)
- Transport: `C:\Users\xiaoj\Desktop\lucky\src\lib\lucky-fetch.ts`
- Shared UI: `C:\Users\xiaoj\Desktop\lucky\src\components\lucky-ui.tsx`
- JSON editor/viewer: `C:\Users\xiaoj\Desktop\lucky\src\components\structured-form.tsx`
- Colour roles: `C:\Users\xiaoj\Desktop\lucky\src\lib\theme.ts`
- Query defaults: `C:\Users\xiaoj\Desktop\lucky\src\lib\query-client.ts`

All Chinese strings below are verbatim and must be reproduced byte-for-byte,
including full-width punctuation (`（）`, `“”`, `？`, `。`, `·`) and the
three-dot ellipsis in `保存中...` (contrast: the editor uses `保存中` with no dots).

## 1. Transport contract (`luckyFetch`)

Every service call goes through `luckyFetch(path, options)`:
- URL = `baseUrl` (trailing slashes stripped) + path, then a cache-busting nonce is
  appended: `?_=` or `&_=` + `String(Date.now()).slice(0, -1)` followed by
  `(sum of those digits) % 8`.
- Headers: `Accept: application/json` (unless set); `Content-Type: application/json`
  when a body exists and it is not FormData/Blob; `Lucky-Admin-Token: <token>`.
- Default timeout 12000 ms; the folder upload overrides it to 600000 ms.
- Envelope: response is normalised to `{ ret: number, msg?: string, ...rest }`.
  `ret` is coerced from string; non-object JSON becomes `{ ret: 0, data: parsed }`.
  HTTP 204 or `content-length: 0` → `{ ret: 0 }`.
- HTTP 401 or `ret === -1` → token refresh via `POST /api/login`, then exactly one
  retry; on failure the session ends and `LuckyAuthError` is thrown with
  `payload.msg` or `登录已失效，请重新登录`.
- `!response.ok || ret !== 0` → `throw new Error(payload.msg || "请求失败（HTTP <status>）")`.
- Abort mapping: external abort → `请求已取消`; timeout → `请求超时，请检查服务器连接`.
- Empty base URL → `请输入 Lucky 服务地址`.

## 2. Response-unwrapping helpers (service module, private)

`query(params)` — drops `undefined` values, `encodeURIComponent(k)=encodeURIComponent(String(v))`
joined with `&`, prefixed with `?`; returns `""` when nothing remains.

`json(value)` = `JSON.stringify(value)`.

`isRecord(v)` = truthy && `typeof v === "object"` && not an array.

`list(payload, keys)` — breadth-first search returning an array of records:
1. Queue starts at `{ value: payload, depth: 0, allowArray: true }`; a `visited` set
   guards cycles; wrapper regex is `/^(?:data|result|response|payload)$/i`.
2. Array node: keep only record elements. If `allowArray` and non-empty → return.
   If `allowArray` and empty → remember as `emptyMatch` (first one wins).
   If `depth < 5`, enqueue each element with `allowArray: false`.
3. Object node: for every own entry whose lower-cased key is in `keys` and whose
   value is an array → filter records; non-empty returns immediately, empty is
   remembered as `emptyMatch`.
4. Then, if `depth < 5`, enqueue every object-valued child; children are sorted so
   wrapper-named keys (`data|result|response|payload`) come first, and **only**
   those wrapper children get `allowArray: true`.
5. Fallback return `emptyMatch ?? []`.

`record(payload, keys)` — for each wanted key **in order**, BFS from the payload root
(depth limit 5, `visited` guard) for the first case-insensitive key match whose value
`isRecord`; the first wanted key that hits wins and the loop breaks. If nothing
matches, the payload itself is used. Result = shallow copy with `ret` and `msg` deleted.

`toCount(value)` → number: `Math.max(0, Math.trunc(v))` when finite. String: blank →
`undefined`, else `Number(v)` finite → `Math.max(0, Math.trunc(...))`. Else `undefined`.

`webServiceGroupSubRuleCount(value)` — BFS, depth limit 4. At each node: first try
`toCount(node)` directly; then any key whose lower-case form is in
`WEB_SERVICE_GROUP_COUNT_KEYS`; then enqueue object children.
`WEB_SERVICE_GROUP_COUNT_KEYS` (verbatim, already lower-case):
`["subrulecount", "subrulenum", "subrulescount", "rulecount", "rulescount", "count"]`
`WEB_SERVICE_GROUP_COUNT_CONCURRENCY = 4`.

## 3. Service factories (exported; plain default objects)

`newWebServiceDefaultProxy()`
```
Key: "default", GroupKey: "", WebServiceType: "reverseproxy", Locations: [],
CorazaWAFInstance: "", SafeIPMode: "blacklist", EasyLucky: false,
LocationInsecureSkipVerify: true, UseTargetHost: false, AutoProxyLocation: false,
AutoProxyLocationWithoutSameHost: false, EnableAccessLog: true, LogLevel: 4,
AccessLogMaxNum: 256, WebListShowLastLogMaxCount: 10,
RequestInfoLogFormat: "[#{clientIP}][#{remoteIP}]#{tab}[#{method}][#{host}#{url}]",
RemoteIPHeaders: ["X-Forwarded-For", "X-Real-IP"], EnableBasicAuth: false,
BasicAuthUserList: "", UseRuleGlobalAuthSettings: false,
OtherParams: { WebAuth: false }
```

`newWebServiceRule()`
```
RuleName: "", RuleKey: "", DiaglogShowMode: "simple", Enable: true,
Network: "tcp6", ListenIP: "", ListenPort: 16666, IPFilterRule: "disable",
CorazaWAFInstance: "", AutoOptionsFirewall: true, EnableTLS: false,
TLSMinVersion: 2, MaxHeaderKBytes: 32, Http3: false,
DefaultProxy: newWebServiceDefaultProxy(), ProxyList: []
```
`newWebServiceSubRule()`
```
Enable: true, Key: "", Remark: "", GroupKey: "", WebServiceType: "reverseproxy",
Domains: [""], Locations: [""], CorazaWAFInstance: "", SafeIPMode: "blacklist",
LocationInsecureSkipVerify: true, UseTargetHost: false, AutoProxyLocation: false,
AutoProxyLocationWithoutSameHost: false, EnableAccessLog: true, LogLevel: 4,
AccessLogMaxNum: 256, WebListShowLastLogMaxCount: 10,
RequestInfoLogFormat: "[#{clientIP}][#{remoteIP}]#{tab}[#{method}][#{host}#{url}]",
RemoteIPHeaders: ["X-Forwarded-For", "X-Real-IP"], EasyLucky: true,
EnableBasicAuth: false, BasicAuthUserList: "", UseRuleGlobalAuthSettings: false,
OtherParams: { WebAuth: false }
```
Differences vs `newWebServiceDefaultProxy()`: has `Remark`/`Domains`, `EasyLucky: true`
(default proxy is `false`), no `Key: "default"`, and no top-level `Locations: []`
(uses `Locations: [""]`).

`newWebServiceGroup()` → `{ Key: "", Name: "" }`

`newWebServiceCgi()`
```
Key: "", Name: "", Enable: true, CGIType: "php", Network: "tcp",
Address: "127.0.0.1:9000", MaxConns: 10, ConnectTimeout: 30,
ForbiddenPaths: "", DefaultDocRoot: "", DefaultIndexNames: "index.php\n",
FileExtensions: ".php"
```

## 4. Exported service functions

Every path below is passed to `luckyFetch`, so the nonce query param is appended
automatically. `enc()` = `encodeURIComponent`. Body column = literal JSON produced.

| # | Function (params with defaults) | Method + path | Body | Unwrap |
|---|---|---|---|---|
| 1 | `getWebServiceCorazaInstances({ signal }= {})` | `GET /api/coraza/instancelist` | — | `list(p, ["list", "instanceList", "instances"])` |
| 2 | `getWebServiceIpFilterRules({ signal }= {})` | `GET /api/ipfliter/list` (typo `ipfliter` is intentional/verbatim) | — | `list(p, ["list", "rules", "ruleList"])` |
| 3 | `getWebServiceRules(lite = false, signal?)` | `GET /api/webservice/rules_lite` when `lite`, else `GET /api/webservice/rules` | — | `{ items: list(p, ["rules", "ruleList", "list"]), raw: p }` |
| 4 | `getWebServiceRule(key)` | `GET /api/webservice/rule/${enc(key)}` | — | `record(p, ["rule", "data"])` |
| 5 | `createWebServiceRule(value)` | `POST /api/webservice/rules` | full `value` | raw envelope |
| 6 | `updateWebServiceRule(key, value)` | `PUT /api/webservice/rule/${enc(key)}` | full `value` | raw envelope |
| 7 | `deleteWebServiceRule(key)` | `DELETE /api/webservice/rule/${enc(key)}` | — | raw |
| 8 | `reorderWebServiceRules(keys: string[])` | `PUT /api/webservice/ruleorderadjustment` | bare JSON array `["k1","k2",…]` (not wrapped in an object) | raw |
| 9 | `getWebServiceSubRuleOption(ruleKey, subKey, option)` | `GET /api/webservice/rule/${enc(ruleKey)}/${enc(subKey)}/${enc(option)}` | — | raw |
| 10 | `setWebServiceSubRuleEnabled(ruleKey, subKey, enabled: boolean)` | `GET /api/webservice/rule/${enc(ruleKey)}/${enc(subKey)}/${"true"\|"false"}` (delegates to #9 with `String(enabled)`) | — | raw |
| 11 | `getWebServiceGroups({ signal, includeCounts = false }= {})` | `GET /api/webservice/groups` | — | `list(p, ["groups", "groupList", "list"])` → see §4.1 |
| 12 | `getWebServiceGroupOptions({ signal }= {})` | `GET /api/webservice/groups` | — | `list(p, ["list", "groups", "groupList"])` — note different key order from #11 |
| 13 | `createWebServiceGroup(value)` | `POST /api/webservice/groups` | `{"Name": value.Name}` **only** — all other fields dropped | raw |
| 14 | `updateWebServiceGroup(value)` | `PUT /api/webservice/groups` | full `value` (includes `Key`) | raw |
| 15 | `deleteWebServiceGroup(key)` | `DELETE /api/webservice/groups?key=${enc(key)}` | — | raw |
| 16 | `getWebServiceGroupSubRuleCount(groupKey, signal?)` | `GET /api/webservice/groups/subrulecount?groupKey=${enc(groupKey)}` | — | raw |
| 17 | `reorderWebServiceGroups(keys: string[])` | `PUT /api/webservice/groups/orderadjustment` | bare JSON array | raw |
| 18 | `getWebServiceCgiList({ signal }= {})` | `GET /api/webservice/cgi/list` | — | `{ items: list(p, ["list", "cgiList", "instances"]), raw: p }` |
| 19 | `createWebServiceCgi(value)` | `POST /api/webservice/cgi` | full `value` | raw |
| 20 | `updateWebServiceCgi(key, value)` | `PUT /api/webservice/cgi/${enc(key)}` | full `value` | raw |
| 21 | `deleteWebServiceCgi(key)` | `DELETE /api/webservice/cgi/${enc(key)}` | — | raw |
| 22 | `setWebServiceCgiEnabled(key, enabled: boolean)` | `PUT /api/webservice/cgi/${enc(key)}/enable` or `…/disable` | none | raw |
| 23 | `getWebServiceSettings({ signal }= {})` | `GET /api/webservice/modulesettings/frontend` | — | `record(p, ["settings", "data"])` |
| 24 | `updateWebServiceSettings(value)` | `PUT /api/webservice/modulesettings` | full `value` | raw |
| 25 | `getWebServiceLogs(pageSize = 100, page = 1, signal?)` | `GET /api/webservice/logs?pageSize=<n>&page=<n>` | — | raw |
| 26 | `getWebServiceLastLogs({ signal }= {})` | `GET /api/webservice/lastlogs` | — | raw |
| 27 | `getWebServiceRuleLogs(ruleKey, subKey, pageSize = 100, page = 1, signal?)` | `GET /api/webservice/${enc(ruleKey)}/${enc(subKey)}/logs?pageSize=&page=` | — | raw |
| 28 | `getWebServiceRuleLastLogs(ruleKey, subKey, signal?)` | `GET /api/webservice/${enc(ruleKey)}/${enc(subKey)}/lastlogs` | — | raw |
| 29 | `getWebServiceAccessDetails(ruleKey, subKey, pageSize = 100, page = 1, signal?)` | `GET /api/webservice/${enc(ruleKey)}/${enc(subKey)}/accessdetail?pageSize=&page=` | — | raw |
| 30 | `getWebServiceCorazaLogs(ruleKey, subKey, pageSize = 100, page = 1, signal?)` | `GET /api/webservice/${enc(ruleKey)}/${enc(subKey)}/corazalogs?pageSize=&page=` | — | raw |
| 31 | `getWebServiceHttpLogs(ruleKey, pageSize = 100, page = 1, signal?)` | `GET /api/webservice/${enc(ruleKey)}/httpserver/logs?pageSize=&page=` | — | raw |
| 32 | `disconnectWebServiceClient(ruleKey, clientKey)` | `DELETE /api/webservice/${enc(ruleKey)}/disconnect/${enc(clientKey)}` | — | raw |
| 33 | `flushWebServiceCache(ruleKey, subKey)` | `GET /api/webservice/${enc(ruleKey)}/${enc(subKey)}/flushcachedirspaceinfo` | — | raw |
| 34 | `uploadWebServiceFolder(ruleKey, subKey, mountIndex: number, file)` | `POST /api/webservice/${enc(ruleKey)}/${enc(subKey)}/updatefolder/upload` | multipart: `file` = blob (`file.file` when present, else the value itself), `mountIndex` = `String(mountIndex)`; `timeoutMs: 600000` | raw |
| 35 | `confirmWebServiceFolderUpdate(ruleKey, subKey, tempId)` | `POST /api/webservice/${enc(ruleKey)}/${enc(subKey)}/updatefolder/confirm` | `{"tempId": tempId}` | raw |
| 36 | `cancelWebServiceFolderUpdate(ruleKey, subKey, tempId)` | `DELETE /api/webservice/${enc(ruleKey)}/${enc(subKey)}/updatefolder/cancel/${enc(tempId)}` | — | raw |
| 37 | `getWebServiceTipInfo({ signal }= {})` | `GET /api/webservice/tipinfo` | — | raw |
| 38 | `markWebServiceTipRead(version: string)` | `PUT /api/webservice/tipread` | `{"version": version}` | raw |
| 39 | `getLightPanelConfigTemplate(value)` | `POST /api/webservice/lightpanel/configtemplate` | full `value` | raw (also stored in screen `output`) |

Also exported: `type WebServiceUploadFile = Blob | { uri: string; name: string; type?: string; file?: Blob }`.

Only validation/throw inside the service module: `uploadWebServiceFolder` throws
`当前运行环境不支持文件上传` when `FormData` is not available. Everything else relies
on `luckyFetch` for error surfacing.

### 4.1 `getWebServiceGroups` count enrichment (`includeCounts: true`)
1. `items = list(payload, ["groups", "groupList", "list"])`.
2. `enriched = items.map(item => { const c = webServiceGroupSubRuleCount(item);
   return c === undefined ? item : { ...item, subRuleCount: c } })`.
3. `missingIndexes` = indexes where the item has a non-empty key
   (`item.Key` if string, else `item.key` if string, else `""`) **and**
   `webServiceGroupSubRuleCount(item) === undefined`.
4. A shared cursor worker pool of `Math.min(4, missingIndexes.length)` workers calls
   `getWebServiceGroupSubRuleCount(key, signal)` per missing index and sets
   `subRuleCount` when the response yields a count.
5. A failed count request is swallowed (the group is still returned) **unless**
   `signal.aborted`, in which case the error is rethrown.
6. Returns `{ items: enriched, raw: payload }`.

## 5. Screen types, constants and helpers

```
type ViewKey    = "rules" | "groups" | "cgi" | "settings" | "logs" | "tools"
type EditorType = "rule" | "subrule" | "group" | "cgi" | "settings" | "template"
type EditorState = { type, title, value, key?, parentKey?, ruleMode?, tlsEnabled? }
type SelectOption = { label: string; value: string }
type WebLogKind = "module" | "subrule" | "access" | "coraza" | "http"
type WebLogMode = "page" | "recent"
type WebLogTarget = { kind, title, ruleKey?, subKey? }
type WebServiceToolsTarget = { ruleKey, ruleName, subKey?, subName?, fileService? }
```
`Action` union (mutation input):
`{save, editor, value}` | `{delete-rule|delete-group|delete-cgi, key}` |
`{delete-subrule, parentKey, key}` | `{toggle-rule|toggle-cgi, key, enabled}` |
`{toggle-subrule, parentKey, key, enabled}` | `{reorder-rules|reorder-groups, keys}` |
`{reorder-group-subrules, ruleKey, keys}` | `{disconnect-client, ruleKey, clientKey}` |
`{flush-cache, ruleKey, subKey}` | `{mark-tip, version}`

Constants:
- `WEB_LOG_PAGE_SIZE = 50`
- `defaultWebLogTarget = { kind: "module", title: "Web 服务日志" }`
- `tabs` (key, label, icon): `rules/规则/Route`, `groups/分组/FolderTree`,
  `cgi/CGI/Workflow`, `settings/设置/Settings2`, `logs/日志/ScrollText`,
  `tools/工具/Wrench`
- `webServiceTypeOptions`: `反向代理→reverseproxy`, `重定向→redirect`, `URL 跳转→url`
- `tlsOnlyWebServiceTypes = new Set(["SNIRouting", "oauth"])` — note neither value is
  present in `webServiceTypeOptions`, so the "available types" filters never actually
  remove an option; they only matter for values that arrive from the server.
- `webRuleDraftSequence` → `nextWebRuleDraftId()` yields `web-rule-draft-<n>` (1-based,
  monotonic per app run) — used only as a stable SwiftUI-style identity for proxy rows.

Value helpers (must be reproduced exactly — many list behaviours depend on them):
- `pick(item, keys, fallback = "")` — first key whose value is `string | number`
  → `String(value)`; otherwise `fallback`. Booleans/objects/arrays are ignored.
- `keyOf(item, index)` = `pick(item, ["RuleKey", "Key", "key", "ID", "id"], String(index))`
- `enabled(item)` = `asBoolean(item.Enable ?? item.enable, true)` (defaults to **true**)
- `asBoolean(value, fallback = false)`: `undefined`/`null`/blank-or-whitespace string →
  `fallback`; `false` or `0` → false; string matching `/^(?:false|0|off|no|disabled)$/i`
  (after trim) → false; **everything else → true**.
- `array(item, keys)` — first key holding an array, else `[]`.
- `object(value)` — value when record, else `{}`.
- `clone(value)` = `JSON.parse(JSON.stringify(value))`.
- `cleanLines(value)` — arrays: map `String`; otherwise `String(value ?? "")` split on
  `/\r?\n/`; then trim every entry and drop empties.
- `move(keys, index, offset)` — swap `index` with `index + offset`; out-of-range → copy
  unchanged.
- `isRecordValue(v)` — same as `isRecord`.
- `entriesFromCandidate(v)`: array → as-is; string → split `/\r?\n/`, `trimEnd()` each,
  drop empties; else `undefined`.

`webLogEntries(value)` — flatten a log payload into rows:
1. `entriesFromCandidate(value)` if it works.
2. Non-record (and not undefined/null) → `[value]`; undefined/null → `[]`.
3. Try these keys in order (verbatim array):
   `["accessDetails", "accessDetail", "clientList", "clients", "corazaLogs",
   "httpLogs", "logs", "lastLogs", "lastlogs", "rows", "items", "list", "text"]`
4. Then for `["data", "result"]`: try `entriesFromCandidate(value[key])`, and if that
   nested value is a record, retry the whole key list from step 3 inside it.
5. Fallback: copy of the object minus `ret` and `msg`; if it still has keys → `[visible]`,
   else `[]`.
`webLogTotal(value)` — scan `[value, value.data, value.result]` (records only) for keys
`["total", "Total", "totalCount", "TotalCount", "count", "Count"]`; first finite value
`>= 0` → `Math.trunc(...)`; else `undefined`.

`webServiceClientKey(value)` — non-record → `""`. Explicit candidates first:
`pick(value, ["ClientKey", "clientKey", "ConnectionKey", "connectionKey", "ConnKey", "connKey"])`.
If empty, the row is treated as a client only if any of
`["ClientIP", "clientIP", "RemoteAddr", "remoteAddr", "RemoteIP", "remoteIP"]` is
`!== undefined`; in that case fall back to `pick(value, ["Key", "key"])`, else `""`.

`getWebLogPage(target, page, mode, signal)` dispatch:
| kind | mode | call |
|---|---|---|
| `module` | `recent` | `getWebServiceLastLogs({ signal })` |
| `module` | `page` | `getWebServiceLogs(50, page, signal)` |
| `http` | any | `getWebServiceHttpLogs(ruleKey, 50, page, signal)` |
| `subrule` | `recent` | `getWebServiceRuleLastLogs(ruleKey, subKey, signal)` |
| `subrule` | `page` | `getWebServiceRuleLogs(ruleKey, subKey, 50, page, signal)` |
| `access` | any | `getWebServiceAccessDetails(ruleKey, subKey, 50, page, signal)` |
| `coraza` | any | `getWebServiceCorazaLogs(ruleKey, subKey, 50, page, signal)` |
Guards (thrown before dispatch): missing `ruleKey` on any non-module kind →
`缺少 Web 服务规则标识`; missing `subKey` on `subrule`/`access`/`coraza` →
`缺少 Web 服务子规则标识`.

### 5.1 `buildSubRuleUrl(rule, subRule)` — "复制网址" URL construction
1. `domain = cleanLines(subRule.Domains)[0]`; falsy → return `""` (caller then shows
   `该子规则没有前端地址`).
2. `scheme = asBoolean(rule.EnableTLS) ? "https" : "http"` — the rule's TLS flag wins;
   any scheme written in the domain is stripped, not honoured.
3. `schemeMatch = domain.match(/^([a-z][a-z\d+.-]*):\/\//i)`; if it matched and the
   captured scheme is not `http`/`https` → `throw new Error("前端地址格式不正确")`.
4. `address` = domain minus the matched scheme prefix, else minus a leading `//`, else
   the domain unchanged. Empty, or starting with `/`, `?`, `#` → same throw.
5. `candidate = ${scheme}://${address}`, parsed with `new URL(...)`. Protocol not
   http/https, or empty hostname → same throw.
6. Authority = text between `//` and the first `/?#`; `host` = after the last `@`.
   `explicitPort`: bracketed IPv6 host → `/^:(\d+)$/` applied after `]`; otherwise
   `/:(\d+)$/`.
7. `listenPort = Number(rule.ListenPort)`; `defaultPort = 443` for https else `80`.
8. When there is no explicit port and `listenPort` is an integer in `1…65535` and
   `!== defaultPort` → set `parsed.port = String(listenPort)`.
9. `url = parsed.toString()`; return it when there was no explicit port, or when
   `parsed.port` is still set.
10. Otherwise (explicit port equal to the default port, which `URL` normalises away)
    re-insert `:${explicitPort}` at the end of the normalised authority.

### 5.2 Semantic colour roles (light / dark)
`page #f5f5f7/#000000`, `card #ffffff/#1c1c1e`, `mutedCard #f2f2f7/#2c2c2e`,
`muted #e8e8ed/#3a3a3c`, `primary #007aff/#0a84ff`, `primarySoft #e5f1ff/#0b2f52`,
`text #1d1d1f/#f5f5f7`, `subtext #6e6e73/#a1a1a6`, `border #e1e1e6/#3a3a3c`,
`rowBorder #e5e5ea/#38383a`, `danger #ff3b30/#ff453a`, `dangerBg #fff0ef/#3d1412`,
`success #248a3d/#30d158`, `warning #c93400/#ff9f0a`, `warningBg #fff5e6/#3b290d`,
`cyan #0071a4/#64d2ff`, `disabled #aeaeb2/#636366`, `placeholder #8e8e93` (both).
## 6. Shared UI primitives used by this screen (`lucky-ui.tsx`)

`CARD_RADIUS = 18`, `CONTROL_RADIUS = 12`.
`surfaceShadow`: colour `#000000`, opacity 0.055 (iOS/web) else 0, radius 12,
offset `(0, 4)`, Android elevation 2.

- **`Page`** — `SafeAreaView` (`edges: []` here because `safeTop={false}`), background
  `page`. Content container: `width 100%`, `maxWidth 820`, centred, `paddingHorizontal 16`,
  `paddingTop 14`, `paddingBottom` = 110 when scrollable else 12, `gap 16`, and
  `flex: 1` when **not** scrollable. Scrollable → wrapped in a ScrollView.
- **`PageHeader`** — row, `minHeight 48`, `gap 12`. `IconTile` size 44 / icon 22 +
  title `fontSize 26 / lineHeight 32 / weight 800` and subtitle `13/18` in `subtext`.
  Refresh button 42×42, radius 13, `card` bg, 1px `border`, `RefreshCw` 19
  (strokeWidth 2.2) in `primary`, or an `ActivityIndicator` while refreshing;
  accessibilityLabel `刷新`; opacity 0.55 refreshing / 0.62 pressed, scale 0.96 pressed.
- **`ResponsiveTabBar`** — container `maxWidth 820`, `padding 4`, radius 16, 1px
  `border`, `mutedCard` bg, wrapping row, `gap 4`. `singleRow = width >= tabs.length*82 + 40`
  (= 532 for 6 tabs). Each tab: `flexGrow/Shrink 1`, `flexBasis` 0 (single row) or `30%`,
  `minHeight` 44/56, `paddingHorizontal 6`, `paddingVertical` 0/6, radius 12,
  bg `card` when selected else transparent (+ shadow when selected), layout row/column,
  gap 6/3; icon 16 (strokeWidth 2.4 selected / 2.1), label `11/14`, weight 700/600,
  colour `primary`/`subtext`, `numberOfLines 2`, centred.
- **`Panel`** — `card` bg, 1px `border`, radius 18, `padding 16`, `gap 12`, shadow.
- **`IconTile(icon, color?, background?, size = 36, iconSize = 18)`** — square, radius
  `max(9, round(size * 0.28))`, bg `background ?? primarySoft`, icon `color ?? primary`,
  strokeWidth 2.2.
- **`EmptyState(message, icon = Inbox, embedded = false)`** — centred column,
  `paddingVertical 20`, `gap 10`; `IconTile` size 42 / icon 21, colour `subtext`,
  bg `mutedCard`; message text in `subtext`, centred. Wrapped in a `Panel` unless embedded.
- **`ErrorState(message, retry?)`** — `padding 14`, radius 18, 1px `dangerBg` border,
  `dangerBg` bg, `gap 10`; row: `IconTile` `TriangleAlert` size 34 / icon 17, colour
  `danger`, bg `card`; message `danger`, `lineHeight 19`. Optional retry chip:
  `minHeight 36`, `paddingHorizontal 12`, radius 12, `card` bg, `RefreshCw` 14 +
  text `重试` weight 700 in `danger`.
- **`SectionHeader(icon, title, meta?)`** — row `minHeight 32`, `gap 9`; `IconTile`
  size 32 / icon 16; title `16/21` weight 700; meta badge `paddingHorizontal 9`,
  `paddingVertical 5`, radius 10, `mutedCard` bg, text `11` weight 600 `subtext`.
- **`FullScreenSafeArea`** — plain View plus safe-area insets as padding (used by the
  two full-screen modals).

`StructuredDataView(value, depth = 0)` (read-only JSON renderer):
- Record → entries excluding `ret`/`msg`; empty → text `暂无数据` (`12`, `subtext`).
  Each entry: label = `fieldLabel(key)` (`11` weight 700 `subtext`) then recursive value;
  nested depth adds `paddingLeft 10` + 1px left border in `border`. Caps at 200 entries,
  then `仅显示前 200 个字段，共 {n} 个`.
- Array → empty gives `暂无项目`; else per item a `mutedCard` block (`padding 10`,
  radius 12, `gap 5`) headed `第 {index+1} 项` (`10`, weight 700, `subtext`).
  Caps at 200, then `仅显示前 200 项，共 {n} 项`.
- Scalars → selectable text `12/18` in `text`; booleans render `是`/`否`;
  `null`/`undefined`/`""` render `--`.
- `fieldLabel(key)` = a fixed Chinese label map (see `structured-form.tsx`, keys such as
  `Enable → 启用`, `Domains → 域名`, `Remark → 备注名称`), otherwise the key with `_`
  replaced by spaces and camelCase split by a space.
`StructuredForm(value, onChange)` (used by the `settings` and `template` editors) is a
generic recursive JSON editor: booleans → switch row (`minHeight 44`, label `13`
weight 600, track `disabled`/`primary`); numbers → numeric input with draft/commit
semantics; strings → text input (`minHeight 44`, radius 12, 1px `border`, `card` bg,
`fontSize 12`), switching to a `minHeight 112` multiline box when the key matches
`/content|script|dockerfile|forbidden|indexnames|paths|command/i` (monospace when it
also matches `/content|script|dockerfile|command/i`). Arrays get per-item delete
(38×38, radius 12, `dangerBg`) plus five append buttons `文本项 / 数字项 / 开关项 /
对象项 / 列表项`. Each object level ends with `添加字段`, which opens a key input
(placeholder `字段名称`), a duplicate warning `该字段已存在`, a type row
`文本 / 数字 / 开关 / 对象 / 列表` (initial values `"" / 0 / false / {} / []`), and
`取消` / `添加` buttons. Per-field delete buttons use accessibility label
`删除{fieldLabel(key)}`; list rows use `删除列表项`.

## 7. Components defined inside `webservice.tsx`

### 7.1 `IconButton({ icon, label, color, onPress, disabled, visibleLabel })`
Pressable: `minWidth 58`, `height 36`, `paddingHorizontal 8`, radius 8, row, centred,
`gap 4`, bg `mutedCard`, opacity `disabled ? 0.4 : 1`. Icon size 16 in `color`; label
`fontSize 11`, weight 700, same `color`, `numberOfLines 1`. `label` is the accessibility
label, `visibleLabel` is the rendered text (they differ on most rows).

### 7.2 `WebServiceLoadingState({ message = "正在加载" })`
`flex 1`, `minHeight 160`, centred, `gap 9`; `ActivityIndicator` in `primary`;
message text `fontSize 12` in `subtext`.

### 7.3 `WebLogRow({ value, index, accessDetails, disconnecting, onDisconnect })`
Card: radius 12, 1px `border`, `card` bg, `padding 12`, `gap 10`.
- Header row (`gap 8`): `第 {index + 1} 项` — `flex 1`, `fontSize 10`, weight 700,
  `subtext`. `index` is already absolute (`(logPage - 1) * 50 + rowIndex`).
- `clientKey = accessDetails ? webServiceClientKey(value) : ""`. When non-empty a
  destructive chip is shown: `minHeight 38`, `paddingHorizontal 11`, radius 10,
  `dangerBg` bg, `Ban` icon 15 + text `断开客户端` (`11`, weight 700) in `danger`,
  opacity 0.5 while `disconnecting`, accessibility label `断开客户端`.
- Body: string value → selectable monospace text `fontSize 10`, `lineHeight 17`, colour
  `text`; anything else → `StructuredDataView`.

### 7.4 `WebServiceToolsModal({ target, busy, onClose, onOpenLog, onFlushCache, onUpdateFolder })`
Transparent fade modal, `overFullScreen`. Backdrop `rgba(0,0,0,0.42)`, centred,
`padding 22`. Card: `maxWidth 520`, radius 18, 1px `border`, `card` bg, `padding 16`,
`gap 10`. `subTitle = target.subName || target.subKey || "子规则"`.
Header (`gap 9`): `IconTile` `MoreHorizontal` size 36 / icon 18; title
`target.subKey ? subTitle : target.ruleName` (`17`, weight 800, 1 line) with secondary
line `更多操作` (`11`, `subtext`, `marginTop 2`); close button 38×38, radius 11,
`mutedCard`, `X` 18 in `subtext`, accessibility label `关闭更多操作`.
Action rows (`minHeight 46`, radius 12, 1px `border`, `mutedCard` bg,
`paddingHorizontal 12`, `gap 10`, icon 18, label `13` weight 700 in `text`,
opacity 0.5 when `busy`), in this order:

| key | label | icon / colour | opens |
|---|---|---|---|
| `http` | `HTTP 服务日志` | `Server` / `cyan` | `{kind:"http", title:"${ruleName} · HTTP 日志", ruleKey}` |
| `subrule` | `子规则日志` | `ScrollText` / `cyan` | `{kind:"subrule", title:"${subTitle} · 日志", ruleKey, subKey}` |
| `access` | `访问详情与客户端` | `Users` / `primary` | `{kind:"access", title:"${subTitle} · 访问详情", ruleKey, subKey}` |
| `coraza` | `Coraza WAF 日志` | `ShieldAlert` / `warning` | `{kind:"coraza", title:"${subTitle} · WAF 日志", ruleKey, subKey}` |
| `flush` | `刷新目录缓存` | `ListTree` / `success` | `onFlushCache` |
| `folder` | `更新文件服务目录` | `FolderUp` / `warning` | `onUpdateFolder` |

Rows 2–4 appear only when `target.subKey` is set; rows 5–6 additionally require
`target.fileService`. Row 1 (`http`) is always present.
### 7.5 `GroupOrderEditor({ groupName, groupKey, initialKeys, busy, onClose, onSave })`
Full-screen slide modal (`statusBarTranslucent`, `navigationBarTranslucent`;
`onRequestClose` closes only when `!busy`). `FullScreenSafeArea` with `page` bg,
`KeyboardAvoidingView` (`padding` on iOS, `height` elsewhere), inner container
`padding 18`, `gap 13`.
- Header (`gap 10`): `IconTile` `ListOrdered` size 38 / icon 19; title `子规则排序`
  (`18`, weight 800, 1 line); subtitle `groupName || groupKey` (`12`, `subtext`,
  `marginTop 2`, 1 line); close button 40×40, radius 12, `mutedCard`, `X` 18 `subtext`,
  accessibility label `关闭`, opacity 0.45 when busy.
- `Panel` with hint text (`12`, `lineHeight 18`, `subtext`):
  `调整顺序后保存，应用顺序与此列表一致。`
- One row per key (local state, initialised from `initialKeys.slice()`), rows after the
  first get `borderTopWidth 1` in `rowBorder` + `paddingTop 10`, `gap 8`:
  1-based index text (`width 24`, `12`, centred, `subtext`); key box `flex 1`,
  `minHeight 42`, radius 11, 1px `border`, `mutedCard` bg, `paddingHorizontal 10`,
  selectable text `12`, 1 line; up button 36×36 radius 10 (bg `muted` + icon `disabled`
  when `index === 0`, else `primarySoft` + `primary`), `ArrowUp` 16, accessibility label
  `上移子规则`; identical down button (`ArrowDown`, disabled on the last row,
  accessibility label `下移子规则`). Swaps happen locally only.
- Footer button: `height 48`, radius 13, bg `busy ? disabled : primary`, `Save` 17 white,
  label `保存排序`, or `保存中...` while busy.

### 7.6 `WebServiceEditor` chrome
Full-screen slide modal, `FullScreenSafeArea` + `card` bg, `KeyboardAvoidingView`
(`padding` iOS / `height` other), container `padding 18`, `gap 13`, `card` bg.
- Header (`gap 9`): `IconTile` `FileCog` size 36 / icon 18; `editor.title` (`18`,
  weight 800, `flex 1`); close 36×36 radius 12 `mutedCard` with `X` 18 `subtext`,
  accessibility label `关闭`, opacity 0.45 when busy, disabled when busy.
- `ScrollView` with `gap 13`, `paddingBottom 4`, `keyboardShouldPersistTaps: handled`,
  `automaticallyAdjustKeyboardInsets`, dismiss mode `interactive` (iOS) / `on-drag`.
- Below the scroll view: `ErrorState(formError)` if set; otherwise
  `ErrorState(serverError)` if set (mutually exclusive, form error wins).
- Footer row (`gap 8`): cancel `flex 1`, `minHeight 48`, radius 12, 1px `border`,
  text `取消` (`subtext`, weight 700); save `flex 1.4`, `minHeight 48`, radius 12,
  bg `busy ? disabled : primary`, `Save` 17 white and label:
  `busy → 保存中`; else `subrule → editor.key ? 保存子规则 : 添加子规则`;
  everything else → `保存配置`.
- The editor is remounted whenever identity changes: React `key` is
  `` `${editor.type}-${editor.key ?? "new"}` ``.
- `serverError` is only forwarded when `mutation.variables?.type === "save"` **and**
  `mutation.variables.editor === editor` (identity comparison).
- Closing calls `mutation.reset()` then clears the editor.

### 7.7 Editor field controls
`Field({ label, field, data?, onUpdate?, multiline = false, numeric = false,
readOnly = false, secret = false, hint?, placeholder? })`
- `source = data ?? value`; `write = onUpdate ?? update` (root setter).
- Displayed text: array value → joined with `"\n"`; otherwise `String(source[field] ?? "")`.
- Label `fontSize 12`, weight 700, colour `text`; container `gap 6`.
- `numeric && !readOnly` → `StableNumberInput`; otherwise a `TextInput`:
  `minHeight` 92 (multiline) / 44, radius 12, 1px `border`, bg `readOnly ? mutedCard : card`,
  colour `readOnly ? subtext : text`, `paddingHorizontal 12`,
  `paddingVertical` 10 (multiline) / 8, `secureTextEntry = secret`, `autoCapitalize none`,
  `autoCorrect false`, `textAlignVertical` `top` (multiline) / `center`.
- Write-back: if the current value is an array, the text is split on `/\r?\n/` and stored
  as an array (empty lines preserved at edit time; `cleanLines` prunes them on save);
  otherwise the raw string is stored.
- Optional `hint` below: `fontSize 10`, `subtext`.
- `secret` is never used with `true` anywhere in this screen (no password masking).
`StableNumberInput({ value, onChange })` — local `draft` string synced from the model
only while unfocused. `onChangeText`: always update the draft, and commit immediately
when the text matches `/^-?\d+(?:\.\d+)?$/`. On blur: `Number(draft)` finite and
non-blank → commit, otherwise revert the draft. Style: `minHeight 44`, radius 12, 1px
`border`, `card` bg, `paddingHorizontal 12`, `paddingVertical 8`, numeric keyboard.

`Toggle({ label, field, data?, onUpdate? })` — row `minHeight 44`, `gap 12`; label
`flex 1`, `fontSize 13`, weight 600, colour `text`; switch value `asBoolean(source[field])`,
track `{false: disabled, true: primary}`.

`Choices({ label, field, options, data?, onUpdate? })` — label `12`/700; wrapping row
`gap 7`; each pill `minWidth 76`, `height 38`, `paddingHorizontal 12`, radius 12, 1px
border (`primary` when selected else `border`), bg `primarySoft`/`card`, text `12`/700 in
`primary`/`text`. Selection test is `String(source[field] ?? "") === option.value`, so
numeric model values match their string option values; **writing stores the string**.
`options` accepts plain strings (label = value).

`SelectField({ label, field, options, data?, onUpdate?, scope = "root" })` — accordion
select; only one is open at a time via the shared `openSelect` state keyed
`` `${scope}.${field}` ``. Trigger: `height 44`, radius 12, 1px border (`primary` when
open), `card` bg, `paddingHorizontal 12`, `gap 8`; text `13`, 1 line, colour `text` when
a value exists else `placeholder`, showing the matched option label, or the raw value,
or `请选择`; `ChevronDown` 17 (`primary` when open else `subtext`).
Dropdown: radius 12, 1px `border`, `card` bg, clipped; each option `minHeight 42`,
`paddingHorizontal 12`, `gap 9`, `borderTopWidth 1` in `rowBorder` except the first,
bg `primarySoft` when active, text `13` weight 700/500 in `primary`/`text`,
`Check` 16 in `primary` when active. Picking writes and closes the dropdown.

`ListenTypeSelector()` — label `监听类型`; two equal pills (`flex 1`, `height 42`,
radius 12, 1px border `primary`/`border`, bg `primarySoft`/`card`, `gap 7`), each with an
18×18 checkbox (radius 6, 1px border, filled `primary` + white `Check` 12 strokeWidth 3
when on) and label `IPv4` (value `tcp4`) / `IPv6` (value `tcp6`) at `13`/700.
Selected when `Network === "tcp"` or `Network === option.value` (`Network` defaults to
`"tcp6"` when unset). `toggleListenType` flips the tapped family; if both would become
off the tap is a no-op; result is `"tcp"` (both), `"tcp4"`, or `"tcp6"`.

`PortStepper()` — label `监听端口`; minus button 42×42 radius 12 1px `border` `card` bg
with `Minus` 18 `primary` (accessibility label `减少端口`); text field `flex 1`,
`height 42`, radius 12, 1px `border`, `card` bg, centred, `fontSize 14`, weight 700,
number pad, `maxLength 5`, `selectTextOnFocus`, and `onChangeText` strips every
non-digit (`next.replace(/\D/g, "")` — the field can therefore hold `""`); plus button
identical with `Plus` (accessibility label `增加端口`). Stepping base =
`Number.parseInt(raw, 10)` when an integer `> 0`, else **16666**; result clamped to
`[1, 65535]`.

`FormSection({ title, icon?, meta?, children })` — `padding 14`, radius 14, 1px `border`,
`mutedCard` bg, `gap 10`; header row `minHeight 26`, `gap 8`: optional icon 17 in
`primary`, title `14`/800, optional meta `11`/600 in `subtext`.

## 8. Screen state and queries

State: `view` (`"rules"`), `expanded` (`""` — the single expanded rule key),
`editor` (undefined), `output` (`""`), `localError` (`""`),
`logTarget` (`defaultWebLogTarget`), `logPage` (1), `logMode` (`"page"`),
`toolsTarget`, `groupOrderEditor` (`{key, name, keys}`),
`folderTarget` (`{parentKey, subKey}`), `mountIndex` (`"0"`), `uploadBusy` (false).
`isFocused` comes from `useIsFocused()`.
Global query defaults (`query-client.ts`): `retry: 1`, `staleTime: 30_000`,
`gcTime: 120_000`, `refetchOnWindowFocus: false`, `refetchOnReconnect: true`.
No query in this screen overrides `staleTime`.

| query | queryKey | fn | enabled | refetch |
|---|---|---|---|---|
| `rules` | `["webservice","rules"]` | `getWebServiceRules(false, signal)` | `view === "rules"` | — |
| `groups` | `["webservice","groups"]` | `getWebServiceGroups({signal, includeCounts:true})` | `view === "groups"` | — |
| `subRuleGroups` | `["webservice","subrule-group-options"]` | `getWebServiceGroupOptions({signal})` | `editor?.type === "subrule" \|\| editor?.type === "rule"` | — |
| `wafInstances` | `["webservice","coraza-instances"]` | `getWebServiceCorazaInstances({signal})` | same as above | — |
| `ipFilterRules` | `["webservice","ip-filter-rules"]` | `getWebServiceIpFilterRules({signal})` | same as above | — |
| `cgi` | `["webservice","cgi"]` | `getWebServiceCgiList({signal})` | `view === "cgi"` | — |
| `settings` | `["webservice","settings"]` | `getWebServiceSettings({signal})` | `view === "settings"` | — |
| `logs` | `["webservice","log-view", kind, ruleKey ?? "", subKey ?? "", logPage, logMode]` | `getWebLogPage(logTarget, logPage, logMode, signal)` | `view === "logs" && isFocused` | `refetchInterval: 15000` when `view === "logs" && isFocused && (logMode === "recent" \|\| logPage === 1)`, else `false`; `refetchIntervalInBackground: false` |
| `tips` | `["webservice","tips"]` | `getWebServiceTipInfo({signal})` | `view === "tools"` | — |

Derived:
- `logEntries = webLogEntries(logs.data)` (memoised), `logTotal = webLogTotal(logs.data)`.
- `supportsRecentLogs = logTarget.kind === "module" || logTarget.kind === "subrule"`.
- `logHasNext` = in page mode with a known total → `logPage * 50 < logTotal`;
  in page mode without a total → `logEntries.length >= 50`; in recent mode → false.
- `activeQuery` = rules / groups / cgi / settings / logs / tips by `view` (tools → tips).
  It drives the page header spinner (`refreshing = activeQuery.isFetching`) and the
  pull-to-refresh / refresh-button action (`activeQuery.refetch()`).
- `ruleKeys = rules.data?.items.map(keyOf) ?? []`,
  `groupKeys = groups.data?.items.map(keyOf) ?? []` — used to build reorder payloads.

Option lists built in the screen body:
- `ipFilterNames` = `{ disable: "停用", blacklist: "黑名单", whitelist: "白名单",
  globalblacklist: "全局黑名单" }`.
- `ipFilterOptions`: a Map seeded with `{ value: "disable", label: "停用" }`, then for
  each `ipFilterRules` item `value = pick(item, ["Key","key"])` (skipped when empty) and
  `label = ipFilterNames[value] ?? pick(item, ["Name","RuleName","Remark"], "IP 规则 " + (index+1))`.
  Later entries with the same key overwrite earlier ones. Order = insertion order.
- `groupOptions` = `[{ label: "未分组", value: "" }]` + `subRuleGroups.data` mapped to
  `{ label: pick(item, ["Name","GroupName","Remark"], "分组 " + (index+1)),
  value: keyOf(item, index) }`.
- `wafOptions` = `[{ label: "无", value: "" }]` + `wafInstances.data` mapped to
  `{ label: pick(item, ["Name","Remark"], "WAF " + (index+1)), value: keyOf(item, index) }`.
- Sub-rule / default-proxy WAF selects use
  `[{ label: "跟随主规则", value: "main" }, ...wafOptions.filter(o => o.value !== "main")]`
  — i.e. `跟随主规则`, then `无` (empty value), then the instances.

## 9. Page shell

`Page`: `title="Web 服务"`, `subtitle="规则、分组、CGI 与运行设置"`, `icon=Globe2`,
`safeTop={false}`, `scrollable` = `view` is **not** one of `rules`/`groups`/`cgi`/`logs`
(those four views own a `FlatList` and must fill the remaining height instead).

Then, always: `ResponsiveTabBar` with the 6 tabs. `onChange(key)` sets the view and,
when switching to `logs`, resets `output → ""`, `logTarget → defaultWebLogTarget`,
`logPage → 1`, `logMode → "page"`; in every case it clears `localError`.

Then `ErrorState(localError)` when non-empty, and `ErrorState(activeQuery.error.message,
retry = activeQuery.refetch)` when the active query failed. Both can show at once.

There is **no search field, no text filter and no sort control** in this screen. The only
segmented control is the 6-tab bar plus the log-mode toggle; the only pagination is the
log pager.
## 10. The single mutation (`useMutation`) — one action per row

`mutationFn` switches on `action.type`. Unknown type → `throw new Error("不支持的 Web 服务操作")`.

| action | work performed |
|---|---|
| `save` + editor `rule` | `key` present → `updateWebServiceRule(key, value)`, else `createWebServiceRule(value)` |
| `save` + editor `subrule` | `GET` the parent via `getWebServiceRule(parentKey ?? "")`, take `items = array(rule,["ProxyList"])`; if `key` → find `index` where `keyOf(item,i) === key`, `index < 0` → `throw new Error("子规则不存在")`, else `items[index] = value`; if no `key` → `items.push(value)`; set `rule.ProxyList = items`; `updateWebServiceRule(parentKey ?? "", rule)` |
| `save` + editor `group` | `key` → `updateWebServiceGroup(value)` (full object), else `createWebServiceGroup(value)` (sends only `Name`) |
| `save` + editor `cgi` | `key` → `updateWebServiceCgi(key, value)`, else `createWebServiceCgi(value)` |
| `save` + editor `settings` | `updateWebServiceSettings(value)` |
| `save` + editor `template` | `getLightPanelConfigTemplate(value)`, then `setOutput(result)` |
| `delete-rule` | `deleteWebServiceRule(key)` |
| `delete-group` | `deleteWebServiceGroup(key)` |
| `delete-cgi` | `deleteWebServiceCgi(key)` |
| `delete-subrule` | read parent, `rule.ProxyList = items.filter((entry,index) => keyOf(entry,index) !== key)`, `updateWebServiceRule(parentKey, rule)` |
| `toggle-cgi` | `setWebServiceCgiEnabled(key, enabled)` |
| `toggle-rule` | read rule, set `rule.Enable = enabled`, `updateWebServiceRule(key, rule)` |
| `toggle-subrule` | `setWebServiceSubRuleEnabled(parentKey, key, enabled)` (GET `.../{parentKey}/{key}/{true\|false}`) |
| `reorder-rules` | `reorderWebServiceRules(keys)` |
| `reorder-groups` | `reorderWebServiceGroups(keys)` |
| `reorder-group-subrules` | read `getWebServiceRule(ruleKey)`; `items = array(rule,["ProxyList"])`; empty → `throw new Error("当前规则没有可排序的子规则")`; build `Map(keyOf → item)`, walk `action.keys` skipping unknown/duplicate keys into `ordered`; if `ordered.length !== items.length` → `throw new Error("排序列表已过期，请刷新规则后重试")`; set `rule.ProxyList = ordered`; `updateWebServiceRule(ruleKey, rule)` |
| `disconnect-client` | `disconnectWebServiceClient(ruleKey, clientKey)` |
| `flush-cache` | `flushWebServiceCache(ruleKey, subKey)` |
| `mark-tip` | `markWebServiceTipRead(version)` |

`onSuccess(result, action)`, in order: `save` → `setEditor(undefined)`;
`reorder-group-subrules` → `setGroupOrderEditor(undefined)`; `disconnect-client` →
`Alert.alert("客户端已断开", "访问详情正在刷新")`; `flush-cache` → `setOutput(result)`,
`setToolsTarget(undefined)`, `Alert.alert("缓存已刷新")` (title only, no message);
then always `setLocalError("")` and `await invalidateWebService(action)`.

`onError(error, action)`: `setLocalError(error.message)`; additionally for
`disconnect-client` and `flush-cache` → `Alert.alert("操作失败", error.message)`.

### 10.1 `invalidateWebService(action)` — invalidated query keys

| action | invalidated keys |
|---|---|
| `save` editor `rule` / `subrule` | `["webservice","rules"]`, `["webservice","groups"]` |
| `save` editor `group` | `["webservice","groups"]`, `["webservice","subrule-group-options"]` |
| `save` editor `cgi` | `["webservice","cgi"]` |
| `save` editor `settings` | `["webservice","settings"]` |
| `save` editor `template` | none |
| `delete-rule`, `delete-subrule`, `toggle-rule`, `toggle-subrule`, `reorder-rules` | `["webservice","rules"]`, `["webservice","groups"]` |
| `delete-group`, `reorder-groups` | `["webservice","groups"]`, `["webservice","subrule-group-options"]` |
| `reorder-group-subrules` | `["webservice","groups"]`, `["webservice","rules"]` |
| `delete-cgi`, `toggle-cgi` | `["webservice","cgi"]` |
| `mark-tip` | `["webservice","tips"]` |
| `disconnect-client` | `["webservice","log-view"]` |
| `flush-cache` | `["webservice","rules"]`, `["webservice","log-view"]` |

All invalidations run concurrently via `Promise.all`.
## 11. Screen-level helper actions

`editRule(key, copyRule = false)`: `value = await getWebServiceRule(key)`. When
`copyRule`: `value.RuleKey = ""`, `value.RuleName = `${pick(value,["RuleName"],"规则")} - 副本``,
and every item of `array(value,["ProxyList"])` gets `item.Key = ""`. Then
`setEditor({ type:"rule", title: copyRule ? "复制 Web 规则" : "编辑 Web 规则", value,
key: copyRule ? undefined : key })`. On throw → `setLocalError(message ?? "读取规则失败")`.

`editSubRule(parentKey, key?)`: read the parent rule; `value` = the ProxyList entry whose
`keyOf(item,i) === key`, or `newWebServiceSubRule()` when no `key`; missing →
`throw new Error("子规则不存在")`. Deep-clone into `draft`, then
`setEditor({ type:"subrule", title: key ? "编辑子规则" : "添加子规则", value: draft, key,
parentKey, ruleMode: rule.DiaglogShowMode === "full" ? "diy" : String(rule.DiaglogShowMode ?? "simple"),
tlsEnabled: asBoolean(rule.EnableTLS) })`. On throw → `setLocalError(message ?? "读取子规则失败")`.

`copySubRuleUrl(rule, subRule)`:
1. `buildSubRuleUrl` throws → `Alert.alert("无法复制", "该子规则的前端地址格式不正确")`, return.
2. Empty url → `Alert.alert("无法复制", "该子规则没有前端地址")`, return.
3. `Clipboard.setStringAsync(url)` returns falsy →
   `Alert.alert("复制失败", "无法写入系统剪贴板，请检查权限后重试")`, return.
4. Success → `Alert.alert("网址已复制", url)` (the URL is the alert message).
5. Throw → `Alert.alert("复制失败", "无法写入系统剪贴板，请重试")`.

`confirmDelete(type, key, name)` where `type ∈ {"rule","group","cgi"}`:
`Alert.alert("确认删除", `确定删除“${name || key}”吗？`, [{text:"取消", style:"cancel"},
{text:"删除", style:"destructive", onPress: mutate({type:`delete-${type}`, key})}])`.

`confirmDeleteSubRule(parentKey, key, name)`:
title `确认删除`, message `` `确定删除子规则“${name || key}”吗？` ``, buttons `取消` (cancel) /
`删除` (destructive → `{type:"delete-subrule", parentKey, key}`).

`openWebLog(target)`: `setLogTarget(target)`, `setLogPage(1)`, `setLogMode("page")`,
`setOutput("")`, `setLocalError("")`, `setToolsTarget(undefined)`, `setView("logs")`.

`confirmDisconnectClient(ruleKey, clientKey)`: `Alert.alert("断开客户端",
"确定断开此客户端连接吗？", [取消 cancel, 断开 destructive →
{type:"disconnect-client", ruleKey, clientKey}])`.

`confirmFlushCache(target)`: no-op when `!target.subKey`. Otherwise
`Alert.alert("刷新目录缓存", "确定重新读取此子规则的目录占用信息吗？",
[取消 cancel, 刷新 (default style) → {type:"flush-cache", ruleKey, subKey: target.subKey ?? ""}])`.

`uploadFolderUpdate()` (no-op without `folderTarget`): `setUploadBusy(true)`,
`setLocalError("")`, then `DocumentPicker.getDocumentAsync({ type:
["application/zip","application/gzip","application/x-tar"], copyToCacheDirectory: true })`.
Cancelled → return. Else upload asset 0 via `uploadWebServiceFolder(parentKey, subKey,
Math.max(0, Number.parseInt(mountIndex,10) || 0), { uri, name, type: mimeType ?? undefined, file })`.
`setOutput(result)`; `tempId = String(result.tempId ?? result.data?.tempId ?? "")`; empty
tempId → `setFolderTarget(undefined)` and stop. Otherwise a non-cancelable alert:
`Alert.alert("确认更新目录", "压缩包已上传并完成预检，是否应用目录更新？",
[{text:"取消更新", style:"destructive"} → resolve(false), {text:"应用更新"} → resolve(true)],
{ cancelable: false })`. Any throw → `setLocalError(message ?? "目录更新失败")`.
`finally` → `setUploadBusy(false)`.

`resolveFolderUpdate(target, tempId, applyUpdate)`: `title = applyUpdate ?
"应用目录更新失败" : "取消目录更新失败"`. Sets `uploadBusy` true, clears `localError`, calls
`confirmWebServiceFolderUpdate` or `cancelWebServiceFolderUpdate`, then `setOutput(result)`,
`setFolderTarget(undefined)`, and when applying also invalidates `["webservice","rules"]`.
On error: `setLocalError(message)` and `Alert.alert(title, message)`.
`finally` → `setUploadBusy(false)`.
## 12. View: `rules` ("规则")

Order: `SectionHeader(icon = Route, title = "反向代理规则", meta = `${rules.data?.items.length ?? 0} 项`)`,
then the add button, then the `FlatList`.

Add button: `Pressable`, height **46**, radius **12**, background `colors.primary`,
row, centred, gap **7**; `Plus` `#fff` size **17**; text `添加规则`, `#fff`, `fontWeight "800"`
(default size). Opens `{ type:"rule", title:"添加 Web 规则", value: newWebServiceRule() }`.

`FlatList`: `data = rules.data?.items ?? []`, `keyExtractor = keyOf(item,index)`,
`extraData = `${expanded}:${mutation.isPending}``, `keyboardShouldPersistTaps="handled"`,
`removeClippedSubviews = Platform.OS === "android"`, `initialNumToRender 6`,
`maxToRenderPerBatch 6`, `windowSize 7`, `style { flex:1, width:"100%" }`,
`contentContainerStyle { paddingBottom: 98, flexGrow: items.length ? 0 : 1 }`,
separator = 12 pt spacer.
`ListEmptyComponent`: `rules.isLoading` → `WebServiceLoadingState("正在读取 Web 服务规则")`;
else if no error → `EmptyState(message = "暂无 Web 服务规则", icon = Route)`; else `null`
(the `ErrorState` above already shows).

### 12.1 Rule row (inside a `Panel`; `Panel` = card radius 18, padding 14, gap 11)

Header `Pressable` (toggles `expanded` between `key` and `""`): row, centre, gap **10**.
- Icon tile: **36×36**, radius **8**, background `colors.primarySoft`, centred,
  `Network` glyph `colors.primary` size **18**. Always this icon — it never varies.
- Title: `pick(item, ["RuleName", "Name"], "未命名规则")`, `colors.text`, weight `"800"`.
- Subtitle (`colors.subtext`, size **11**, `marginTop 3`), literally:
  `` `${pick(item,["Network"],"tcp")} · ${pick(item,["ListenIP"],"*")}:${pick(item,["ListenPort"],"--")} · ${subs.length} 个子规则` ``
  — the separators are a space-middot-space, and the IP/port are joined by a bare `:`.
  **The port is printed in full; there is no masking or redaction anywhere.**
- Trailing chevron: `ChevronUp` when open else `ChevronDown`, `colors.subtext`, size **18**.

`subs = array(item, ["ProxyList"])`; `key = keyOf(item, index)`; `name` = the title above.

Status block (`gap 8`), row 1 (row, centre, gap **8**):
- `Switch` `value = enabled(item)`, `disabled = mutation.isPending`,
  `trackColor { false: colors.disabled, true: colors.primary }`; change →
  `{ type:"toggle-rule", key, enabled: value }`.
- Label `colors.subtext`, size **11**, weight `"700"`: `规则已启用` when `enabled(item)`
  else `规则已停用`. **This text plus the switch is the entire status derivation — there is
  no separate status pill, no TLS badge and no protocol badge in the row.**

Row 2: `row`, `flexWrap "wrap"`, `justifyContent "space-between"`, `gap 7`; a left cluster
(gap 7) and a right cluster (gap 7) of `IconButton`s:

| cluster | icon | `label` (a11y) | `visibleLabel` | colour | disabled when | action |
|---|---|---|---|---|---|---|
| left | `ArrowUp` | `上移` | `上移` | `colors.text` | `mutation.isPending \|\| index === 0` | `{type:"reorder-rules", keys: move(ruleKeys, index, -1)}` |
| left | `ArrowDown` | `下移` | `下移` | `colors.text` | `mutation.isPending \|\| index === ruleKeys.length - 1` | `{type:"reorder-rules", keys: move(ruleKeys, index, 1)}` |
| right | `ListOrdered` | `子规则排序` | `排序` | `colors.text` | `mutation.isPending \|\| subs.length < 2` | `setGroupOrderEditor({ key, name, keys: subs.map(keyOf) })` |
| right | `MoreHorizontal` | `规则更多操作` | `更多` | `colors.text` | — | `setToolsTarget({ ruleKey: key, ruleName: name })` |
| right | `Copy` | `复制规则` | `复制规则` | `colors.primary` | — | `editRule(key, true)` |
| right | `Pencil` | `编辑` | `编辑` | `colors.primary` | — | `editRule(key)` |
| right | `Trash2` | `删除` | `删除` | `colors.danger` | `mutation.isPending` | `confirmDelete("rule", key, name)` |
### 12.2 Expanded rule body (only when `expanded === key`)

Container: `borderTopWidth 1`, `borderTopColor colors.rowBorder`, `paddingTop 10`, `gap 9`.

"Add sub-rule" button: height **38**, radius **8**, `borderWidth 1` in `colors.primary`,
transparent fill, row, centred, gap **6**; `Plus` `colors.primary` size **15**; text
`添加子规则`, `colors.primary`, weight `"700"`, size **12**. Calls `editSubRule(key)`.

Then either the sub-rule cards or, when `subs.length === 0`, a single centred `Text`
`暂无子规则` (`colors.subtext`, `textAlign "center"`, `paddingVertical 14`, size **12**).

### 12.3 Sub-rule card — extraction rules

```
subKey    = keyOf(sub, subIndex)                       // ["RuleKey","Key","key","ID","id"] then String(index)
domains   = Array.isArray(sub.Domains) ? sub.Domains.join(", ") : ""
subName   = pick(sub, ["Remark"], domains || `子规则 ${subIndex + 1}`)
fileService = pick(sub, ["WebServiceType"]).toLowerCase().includes("file")
```

Card: `padding 10`, radius **8**, background `colors.mutedCard`, `gap 7`.

Header row (row, centre, gap **8**):
- `ShieldCheck` size **16**, colour `enabled(sub) ? colors.success : colors.disabled`
  — this glyph tint is the only visual enabled/disabled indicator on the sub-rule.
- Title `subName`: `colors.text`, weight `"700"`, size **12**.
- Second line, `numberOfLines 2`, `colors.subtext`, size **10**, `marginTop 3`:
  `` `${pick(sub,["WebServiceType"],"reverseproxy")} · ${domains || "--"}` ``.
- `Switch` `value = enabled(sub)`, `disabled = mutation.isPending`, **no `trackColor`
  override** (unlike the rule switch); change →
  `{ type:"toggle-subrule", parentKey: key, key: subKey, enabled: value }`.

Action row: `row`, `flexWrap "wrap"`, `justifyContent "space-between"`, `gap 7`.
Left cluster (`flexWrap "wrap"`, gap 7) then right cluster (gap 7):

| cluster | icon | `label` | `visibleLabel` | colour | disabled | action |
|---|---|---|---|---|---|---|
| left | `Copy` | `复制完整网址` | `复制网址` | `colors.primary` | — | `copySubRuleUrl(item, sub)` |
| left | `MoreHorizontal` | `子规则更多操作` | `更多` | `colors.text` | — | `setToolsTarget({ ruleKey: key, ruleName: name, subKey, subName, fileService })` |
| right | `Pencil` | `编辑子规则` | `编辑` | `colors.primary` | — | `editSubRule(key, subKey)` |
| right | `Trash2` | `删除子规则` | `删除` | `colors.danger` | `mutation.isPending` | `confirmDeleteSubRule(key, subKey, subName)` |

`move(keys, index, offset)` (used by both reorder buttons): returns `keys` unchanged when
`index + offset` falls outside `[0, keys.length)`; otherwise a copy with the two entries
swapped.

**Explicit non-features of the rule list** (do not invent them in the port):
- No TLS badge, lock glyph or `https` marker. `EnableTLS` only affects the scheme chosen by
  `buildSubRuleUrl`, the editor's TLS section and its validation messages.
- No port masking, truncation or obfuscation.
- No search box, text filter, tag filter or sort menu.
- No group name shown on a rule or sub-rule row.
- No per-row traffic, uptime or connection counters.
## 13. View: `groups` ("分组")

`SectionHeader(icon = FolderTree, title = "子规则分组", meta = `${groups.data?.items.length ?? 0} 项`)`.

Add button: height **44**, radius **8**, `colors.primary`, row, centred, gap 7,
`Plus` `#fff` size 17, text `添加分组` (`#fff`, weight `"800"`). Opens
`{ type:"group", title:"添加分组", value: newWebServiceGroup() }`.

`FlatList`: `extraData = mutation.isPending`, `initialNumToRender 8`,
`maxToRenderPerBatch 8`, `windowSize 7`, `paddingBottom 98`, separator 12,
`flexGrow` 0/1 as before. Empty: loading → `WebServiceLoadingState("正在读取分组")`;
else no error → `EmptyState("暂无分组", icon = FolderTree)`.

Row (`Panel`): header row (row, centre, gap **10**) with a bare `FolderTree` glyph
(`colors.primary`, size **18** — no tile), then
- title `pick(item, ["Name", "GroupName"], key)`, `colors.text`, weight `"800"`;
- subtitle `colors.subtext`, size **11**, **no `marginTop`**:
  `` `${key} · ${item.subRuleCount === undefined ? "接口未返回子规则数量" : `${item.subRuleCount} 个子规则`}` ``.
  `subRuleCount` is the field injected by `getWebServiceGroups({includeCounts:true})`.

Action row: `row`, `flexWrap "wrap"`, `justifyContent "flex-end"`, `gap 7`:
`ArrowUp` `上移`/`上移` `colors.text` disabled `isPending || index === 0` →
`{type:"reorder-groups", keys: move(groupKeys, index, -1)}`;
`ArrowDown` `下移`/`下移` disabled `isPending || index === groupKeys.length - 1` →
`move(groupKeys, index, 1)`;
`Pencil` `编辑`/`编辑` `colors.primary` → `setEditor({type:"group", title:"编辑分组",
value: clone(item), key})`;
`Trash2` `删除`/`删除` `colors.danger` disabled `isPending` → `confirmDelete("group", key, name)`.

There is **no enable switch** on a group row.

## 14. View: `cgi` ("CGI")

`SectionHeader(icon = Workflow, title = "CGI 实例", meta = `${cgi.data?.items.length ?? 0} 项`)`.
Add button identical to groups' but label `添加 CGI`; opens
`{ type:"cgi", title:"添加 CGI 实例", value: newWebServiceCgi() }`.
`FlatList` params identical to groups. Empty: loading →
`WebServiceLoadingState("正在读取 CGI 实例")`; else no error →
`EmptyState("暂无 CGI 实例", icon = Workflow)`.

Row (`Panel`): header row (gap 10) with bare `Workflow` glyph in **`colors.cyan`** size 18;
title `pick(item, ["Name"], key)` (`colors.text`, `"800"`); subtitle `colors.subtext`
size **11** `marginTop 3`:
`` `${pick(item,["CGIType"])} · ${pick(item,["Network"])} · ${pick(item,["Address"])}` ``
(each falls back to the empty string, so an unknown field renders as nothing around the
middots). Trailing `Switch` `value = enabled(item)`, `disabled = mutation.isPending`, no
`trackColor` override → `{type:"toggle-cgi", key, enabled: value}`.

Action row (`justifyContent "flex-end"`, gap 7): `Pencil` `编辑`/`编辑` `colors.primary` →
`setEditor({type:"cgi", title:"编辑 CGI 实例", value: clone(item), key})`;
`Trash2` `删除`/`删除` `colors.danger` disabled `isPending` → `confirmDelete("cgi", key, name)`.

## 15. View: `settings` ("设置")

`SectionHeader(icon = Settings2, title = "模块设置")` (no `meta`). Then:
- `settings.isLoading` → `WebServiceLoadingState("正在读取模块设置")`.
- `settings.data` → a `Panel` containing a `colors.subtext` size **12** `lineHeight 19`
  sentence rendered as three text chunks: `当前设置包含 `, the count, ` 个字段。` where the
  count is `Object.keys(settings.data).filter(key => !["ret","msg"].includes(key)).length`.
  Below it a `Pressable`: height **42**, radius **8**, `colors.primary`, row, centred,
  gap 7, `FileCog` `#fff` size **17**, text `编辑全部设置` (`#fff`, `"800"`) →
  `setEditor({type:"settings", title:"编辑模块设置", value: clone(settings.data)})`.
- else, when there is no error → `EmptyState("暂无模块设置", icon = Settings2)`.

This view is inside the scrollable `Page` (no `FlatList`).
## 16. View: `logs` ("日志")

`SectionHeader`:
- `icon` = `Users` when `logTarget.kind === "access"`, `ShieldAlert` when `"coraza"`,
  otherwise `ScrollText`.
- `title` = `logTarget.title` (set by whoever opened the log; module default `模块日志`).
- `meta` = `最近日志` when `logMode === "recent"`; else `` `第 ${logPage} 页` `` when
  `logTotal === undefined`; else `` `共 ${logTotal} 项` ``.

### 16.1 Toolbar

Container: `minHeight 46`, radius **12**, `borderWidth 1` `colors.border`, background
`colors.card`, `padding 6`, row, centre, `gap 7`.

1. When `logTarget.kind !== "module"`: a `Pressable` `minHeight 36`,
   `paddingHorizontal 11`, radius **9**, background `colors.primarySoft`, text `模块日志`
   (`colors.primary`, size **11**, weight `"700"`) → `openWebLog(defaultWebLogTarget)`.
2. When `supportsRecentLogs` (kind is `module` or `subrule`): a mode toggle, same metrics;
   background `logMode === "recent" ? colors.primarySoft : colors.mutedCard`; label
   `最近日志` when in recent mode else `分页日志`, colour `colors.primary` / `colors.subtext`.
   Press → flips `logMode` between `"page"` and `"recent"` and resets `logPage` to 1.
3. A flexible spacer (`flex: 1`).
4. Only when `logMode === "page"`, the pager:
   - Prev: `accessibilityLabel "上一页"`, **38×36**, radius **9**, `colors.mutedCard`,
     `ChevronUp` `colors.text` size **17**; `disabled` and `opacity 0.4` when
     `logPage <= 1 || logs.isFetching`; press → `setLogPage(max(1, page - 1))`.
   - Counter: `minWidth 54`, centred, `colors.text`, size **11**, weight `"700"`, text
     `` `${logPage} / ${logTotal === undefined ? "--" : Math.max(1, Math.ceil(logTotal / 50))}` ``.
   - Next: `accessibilityLabel "下一页"`, same box, `ChevronDown`; disabled/dimmed when
     `!logHasNext || logs.isFetching`; press → `setLogPage(page + 1)`.

### 16.2 Log list

`FlatList data = logEntries`.
`keyExtractor`: `itemKey = isRecordValue(item) ? pick(item, ["ClientKey", "clientKey",
"ID", "id", "Key", "key", "Time", "time"]) : ""`, then
`` `${logMode}-${logPage}-${itemKey || "row"}-${index}` ``.
`extraData = mutation.isPending`; `refreshing = logs.isRefetching && !logs.isLoading`;
`onRefresh → logs.refetch()`; `initialNumToRender 12`, `maxToRenderPerBatch 12`,
`windowSize 7`, `removeClippedSubviews` on Android; `paddingBottom 98`; separator **10**.
Empty: `logs.isLoading` → a centred `ActivityIndicator` (`colors.primary`) in a
`minHeight 180` box; else when no error → `EmptyState(message = `暂无${logTarget.title}`,
icon = ScrollText)`.
`renderItem` → `WebLogRow value={item} index={(logPage - 1) * 50 + index}
accessDetails={logTarget.kind === "access"}
disconnecting={mutation.isPending && mutation.variables?.type === "disconnect-client"}
onDisconnect={(clientKey) => { if (logTarget.ruleKey) confirmDisconnectClient(logTarget.ruleKey, clientKey); }}`.

## 17. View: `tools` ("工具")

`SectionHeader(icon = Wrench, title = "辅助接口")`.

Panel 1, heading `规则轻量列表与提示` (`colors.text`, weight `"700"`), then a row (gap **8**)
of two equal outline buttons (`flex 1`, height **40**, radius **8**, `borderWidth 1`
`colors.primary`, label `colors.primary` weight `"700"` size **12**):
- `读取轻量列表` → `await getWebServiceRules(true)` then `setOutput(result.raw)`;
  on error `setLocalError(message ?? "请求失败")`.
- `查看提示信息` → `setOutput(tips.data ?? {})`.

Then, only when `typeof tips.data?.version === "string"`, a bare text button
`标记当前提示为已读` (`colors.primary`, weight `"700"`, centred) →
`{ type:"mark-tip", version: String(tips.data?.version) }`.

Panel 2, heading `轻面板配置模板`, then a filled button height **40**, radius **8**,
`colors.primary`, label `填写请求参数` (`#fff`, `"800"`) →
`setEditor({ type:"template", title:"请求轻面板配置模板", value: {} })`.

Finally, when `output` is truthy: `<Panel><StructuredDataView value={output} /></Panel>`.
`output` is set by the tools buttons, by a successful `flush-cache`, by the template save,
and by the folder upload/confirm/cancel calls.
## 18. Overlays mounted at the end of the page

Order in the tree: tools modal, editor, group-order editor, folder-update modal.

`WebServiceToolsModal` (when `toolsTarget`): `target`, `busy = mutation.isPending`,
`onClose` ignores the tap while `mutation.isPending`, `onOpenLog = openWebLog`,
`onFlushCache = () => confirmFlushCache(toolsTarget)`, `onUpdateFolder` returns early
without a `subKey`, else `setMountIndex("0")`,
`setFolderTarget({ parentKey: toolsTarget.ruleKey, subKey: toolsTarget.subKey })`,
`setToolsTarget(undefined)`.

`WebServiceEditor` (when `editor`): remounted whenever the identity changes via
`key={`${editor.type}-${editor.key ?? "new"}`}`. Props: `editor`,
`busy = mutation.isPending`, `serverError` = `mutation.error?.message` **only** when
`mutation.variables?.type === "save" && mutation.variables.editor === editor`
(reference equality), `ipFilterOptions`, `groupOptions`, `wafOptions` (see §8),
`onClose = () => { mutation.reset(); setEditor(undefined); }`,
`onSave = (value) => mutation.mutate({ type:"save", editor, value })`.

`GroupOrderEditor` (when `groupOrderEditor`): `groupName`, `groupKey`,
`initialKeys`, `busy = mutation.isPending`, `onClose` clears the state,
`onSave(keys)` → empty list sets `localError` to `至少填写一个子规则 Key` and returns,
otherwise `{ type:"reorder-group-subrules", ruleKey: groupOrderEditor.key, keys }`.

### 18.1 Folder-update modal (when `folderTarget`)

`Modal transparent animationType="fade" presentationStyle="overFullScreen"`;
`onRequestClose` clears `folderTarget` **only** when `!uploadBusy`.
Backdrop: `SafeAreaView flex 1`, `rgba(0,0,0,0.42)`, `justifyContent "center"`,
`padding 22`.
Card: `width "100%"`, `maxWidth 520`, `alignSelf "center"`, `colors.card`, radius **20**,
`borderWidth 1` `colors.border`, `padding 18`, `gap 14`.

- Header row (gap **9**): `IconTile icon={FolderUp} color={colors.warning}
  background={colors.warningBg} size={36} iconSize={18}`, then title
  `更新文件服务目录` (`flex 1`, `colors.text`, size **17**, weight `"800"`).
- Field group (gap **7**): label `挂载项索引` (`colors.text`, size **12**, weight `"700"`)
  and a `TextInput` bound to `mountIndex`, `keyboardType "number-pad"`, height **44**,
  radius **12**, background `colors.mutedCard`, `color colors.text`,
  `paddingHorizontal 12`. No placeholder; the raw string is kept as typed and parsed only
  at upload time (`Math.max(0, Number.parseInt(mountIndex, 10) || 0)`).
- Notice (`colors.subtext`, size **11**, `lineHeight 17`), verbatim:
  `选择包含单个根目录的 ZIP、TAR 或 TAR.GZ 文件。上传后会再次确认才应用更新。`
- Button row (gap **8**), both `flex 1`, height **44**, radius **12**:
  - `取消` — outline (`borderWidth 1` `colors.border`), label `colors.text` weight `"700"`,
    `disabled = uploadBusy`, press → `setFolderTarget(undefined)`.
  - Primary — background `uploadBusy ? colors.disabled : colors.primary`, label `#fff`
    weight `"800"`, text `处理中` while `uploadBusy` else `选择文件`,
    `disabled = uploadBusy`, press → `uploadFolderUpdate()`.

## 19. Every alert in the screen, verbatim

| trigger | title | message | buttons |
|---|---|---|---|
| delete rule/group/cgi | `确认删除` | `` 确定删除“{name \|\| key}”吗？ `` | `取消` (cancel) / `删除` (destructive) |
| delete sub-rule | `确认删除` | `` 确定删除子规则“{name \|\| key}”吗？ `` | `取消` / `删除` (destructive) |
| disconnect client | `断开客户端` | `确定断开此客户端连接吗？` | `取消` / `断开` (destructive) |
| flush dir cache | `刷新目录缓存` | `确定重新读取此子规则的目录占用信息吗？` | `取消` / `刷新` |
| flush cache success | `缓存已刷新` | — | default OK |
| disconnect success | `客户端已断开` | `访问详情正在刷新` | default OK |
| mutation error (disconnect / flush only) | `操作失败` | `error.message` | default OK |
| upload pre-checked | `确认更新目录` | `压缩包已上传并完成预检，是否应用目录更新？` | `取消更新` (destructive) / `应用更新`; `cancelable: false` |
| apply confirm failed | `应用目录更新失败` | `error.message` | default OK |
| cancel confirm failed | `取消目录更新失败` | `error.message` | default OK |
| copy URL, malformed | `无法复制` | `该子规则的前端地址格式不正确` | default OK |
| copy URL, empty | `无法复制` | `该子规则没有前端地址` | default OK |
| clipboard returned false | `复制失败` | `无法写入系统剪贴板，请检查权限后重试` | default OK |
| clipboard threw | `复制失败` | `无法写入系统剪贴板，请重试` | default OK |
| copy URL success | `网址已复制` | the URL | default OK |
## 20. `WebServiceEditor` — initial state, chrome and save button

`value` initial state, by `editor.type`:
- `subrule` → `normalizeWebProxy(clone(editor.value), newWebServiceSubRule())`.
- `rule` → `{ ...newWebServiceRule(), ...clone(editor.value) }` with these overrides:
  `DiaglogShowMode` = `"diy"` when the incoming value was `"full"`, else the incoming value,
  else the default `"simple"`;
  `CorazaWAFInstance` = `String(initial.CorazaWAFInstance || initial.CorazaWAFKey ||
  defaults.CorazaWAFInstance || "")`;
  `DefaultProxy` = `normalizeWebProxy(initial.DefaultProxy, object(defaults.DefaultProxy))`;
  `ProxyList` = `array(initial, ["ProxyList"]).map(item => normalizeWebProxy(item,
  newWebServiceSubRule()))`. Then `delete next.CorazaWAFKey`.
- everything else (`group`, `cgi`, `settings`, `template`) → `clone(editor.value)` as-is.

Other state: `proxyDraftIds` (one generated id per initial ProxyList entry — draft ids are
what the accordion tracks, so reordering/removing never mixes up open cards),
`expandedProxyId` (`""`), `openSelect` (`""` — at most one dropdown open at a time),
`formError` (`""`).

Writers: `update(key, next)` on the root; `updateDefaultProxy(key, next)` rebuilds
`DefaultProxy` as `{ ...newWebServiceDefaultProxy(), ...object(current.DefaultProxy),
[key]: next }`; `updateProxy(index, key, next)` maps over `ProxyList`.
`addProxy()` appends `newWebServiceSubRule()`, pushes a new draft id and expands it.
`applyWafToAllProxies()` copies the root `CorazaWAFInstance` into `DefaultProxy` and every
`ProxyList` entry.
`toggleListenType(type)` reads `Network` (default `"tcp6"`), derives
`ipv4 = network === "tcp" || network === "tcp4"` and `ipv6 = network === "tcp" || network === "tcp6"`,
flips the requested one, **refuses to write when both would be off**, and stores
`"tcp"` (both) / `"tcp4"` / `"tcp6"`.
`removeProxy(index, draftId)` alerts `移除子规则` /
`` `确定从当前规则中移除“${pick(item ?? {}, ["Remark"], `子规则 ${index+1}`)}”吗？` ``
with `取消` (cancel) and `移除` (destructive); confirming drops the entry, drops its draft
id, and collapses the accordion when that card was open.

Chrome: full-screen `Modal animationType="slide" presentationStyle="fullScreen"
statusBarTranslucent navigationBarTranslucent`; `onRequestClose` calls `onClose()` only
when `!busy`. Inside: `FullScreenSafeArea` on `colors.card`, a `KeyboardAvoidingView`
(`padding` on iOS, `height` elsewhere), then a `flex 1` container `padding 18`, `gap 13`.
- Header row (gap **9**): `IconTile icon={FileCog} size={36} iconSize={18}` (default
  primary colours), title `editor.title` (`flex 1`, `colors.text`, size **18**, weight
  `"800"`), and a close button `accessibilityLabel "关闭"`, **36×36**, radius **12**,
  `colors.mutedCard`, `X` `colors.subtext` size **18**, `disabled = busy`,
  `opacity busy ? 0.45 : 1`.
- `ScrollView automaticallyAdjustKeyboardInsets`, `keyboardDismissMode` `interactive` on
  iOS else `on-drag`, `keyboardShouldPersistTaps "handled"`,
  `contentContainerStyle { gap: 13, paddingBottom: 4 }` — contains `form()`.
- `ErrorState(formError)` when set; otherwise `ErrorState(serverError)` when set. Never both.
- Footer row (gap **8**): cancel `Pressable` `flex 1`, `minHeight 48`, radius **12**,
  outline `colors.border`, label `取消` (`colors.subtext`, `"700"`), `disabled = busy`;
  save `Pressable` **`flex 1.4`**, `minHeight 48`, radius **12**, background
  `busy ? colors.disabled : colors.primary`, `Save` `#fff` size **17**, label
  `busy ? "保存中" : editor.type === "subrule" ? (editor.key ? "保存子规则" : "添加子规则") : "保存配置"`
  (`#fff`, `"800"`), `disabled = busy`, press → `save()`.

Static option lists:
`webServiceTypeOptions` = `[{label:"反向代理", value:"reverseproxy"},
{label:"重定向", value:"redirect"}, {label:"URL 跳转", value:"url"}]`.
`tlsOnlyWebServiceTypes` = `new Set(["SNIRouting", "oauth"])` — never present in
`webServiceTypeOptions`, so the TLS filter only preserves a server-supplied current value.
`availableServiceTypes` = `webServiceTypeOptions.filter(o => tlsEnabled ||
!tlsOnlyWebServiceTypes.has(o.value) || o.value === data.WebServiceType)`.
## 21. Editor field schema

Notation: label → payload key → control → default (from the factory in §3) → notes.
`Field` renders a multiline `TextInput` at `minHeight 92` when `multiline`, otherwise a
44 pt single line; array values are joined with `"\n"` for display and split back by
`cleanLines` only at save time for `Domains`/`Locations`.

### 21.1 `rule` editor — section `规则设置` (icon `Settings2`)

| label | key | control | default | notes |
|---|---|---|---|---|
| `Web 服务规则名称` | `RuleName` | text, placeholder `可留空` | `""` | |
| `规则开关` | `Enable` | toggle | `true` | |
| `操作模式` | `DiaglogShowMode` | choices `简易模式`=`simple`, `定制模式`=`diy` | `"simple"` | `diyMode = value.DiaglogShowMode === "diy"`; written as a string, re-coerced by `Number` never (stays a string) |
| `监听类型` | `Network` | `ListenTypeSelector` — two toggles `IPv4`/`IPv6` | `"tcp6"` | see `toggleListenType`; cannot clear both |
| `监听地址` | `ListenIP` | text, hint `没有特殊需求可留空` | `""` | **only when `diyMode`** |
| `监听端口` | `ListenPort` | `PortStepper` (−/+ and a centred `number-pad` input, `maxLength 5`) | `16666` | non-digits stripped; step base 16666, clamped to 1…65535 |
| `IP 过滤规则` | `IPFilterRule` | select, `ipFilterOptions` | `"disable"` | |
| `自动放行防火墙` | `AutoOptionsFirewall` | toggle | `true` | |
| `TLS` | `EnableTLS` | toggle | `false` | gates the next two rows |
| `TLS 最低版本` | `TLSMinVersion` | choices `TLS 1.0`=`"0"`, `TLS 1.1`=`"1"`, `TLS 1.2`=`"2"`, `TLS 1.3`=`"3"` | `2` | only when TLS on; stored as the option **string**, re-coerced with `Number` in `save()` |
| `启用 HTTP/3` | `Http3` | toggle | `false` | only when TLS on **and** `diyMode` |
| `最大请求头 (KB)` | `MaxHeaderKBytes` | numeric (`StableNumberInput`) | `32` | only when `diyMode` |
| `CorazaWAF` | `CorazaWAFInstance` | select, `wafOptions` (`无` = `""` first) | `""` | |
| — | — | button `应用到所有子规则` (height 42, radius 12, outline `colors.primary`, `ShieldCheck` 17, label size 12 `"700"`) | — | `applyWafToAllProxies()` |

### 21.2 `rule` editor — section `默认规则` (icon `Globe2`), writes into `DefaultProxy`

| label | key | control | default | notes |
|---|---|---|---|---|
| `分组` | `GroupKey` | select, `groupOptions` (`未分组` = `""`) | `""` | scope `"default"` |
| `服务类型` | `WebServiceType` | select, `availableServiceTypes` | `"reverseproxy"` | |
| `默认目标地址` / `跳转目标地址` | `Locations` | multiline | `[]` | label is `默认目标地址` when type is `reverseproxy` else `跳转目标地址`; placeholder `没有特殊需求可留空` vs `请填写跳转目标地址`; hint `每行填写一个地址，多行时依次负载均衡` only for `reverseproxy` |
| `CorazaWAF` | `CorazaWAFInstance` | select, `跟随主规则`=`main` + `wafOptions` minus any `main` | `""` | |
| `万事大吉` | `EasyLucky` | toggle | `false` | |
| `忽略后端 TLS 证书验证` | `LocationInsecureSkipVerify` | toggle | `true` | |
| `使用目标地址 Host 请求头` | `UseTargetHost` | toggle | `false` | |
| `自动反代重定向` | `AutoProxyLocation` | toggle | `false` | |
| `不同 Host 也自动改写重定向` | `AutoProxyLocationWithoutSameHost` | toggle | `false` | only when `diyMode && AutoProxyLocation` |
| `记录访问日志` | `EnableAccessLog` | toggle | `true` | |

Then a 1 pt `colors.rowBorder` divider (`marginVertical 2`), a sub-heading row
(`ShieldCheck` `colors.primary` 16 + `安全设置`, `colors.text`, size **13**, `"800"`), and
`SecurityFields` with `scope "default-security"` and
`showIpFilter = diyMode || defaultProxy.WebServiceType === "SNIRouting"`.

### 21.3 `SecurityFields` (shared by default proxy, inline sub-rules and the sub-rule editor)

| label | key | control | default | notes |
|---|---|---|---|---|
| `使用规则全局认证设置` | `UseRuleGlobalAuthSettings` | toggle | `false` | when on, the next three rows are hidden |
| `Basic 认证` | `EnableBasicAuth` | toggle | `false` | |
| `Basic 认证用户` | `BasicAuthUserList` | multiline, hint `每行填写一组 用户名:密码` | `""` | only when `EnableBasicAuth` |
| `网页认证` | `OtherParams.WebAuth` | toggle written through `onUpdate("OtherParams", {...otherParams, WebAuth: next})` | `false` | |
| `IP 过滤规则` | `SafeIPMode` | select, `ipFilterOptions` | `"blacklist"` | only when `showIpFilter` |
### 21.4 `SubRuleFields` (the sub-rule editor's `基础设置`, and each inline sub-rule card)

| label | key | control | default | notes |
|---|---|---|---|---|
| `子规则名称` | `Remark` | text, placeholder `可留空` | `""` | |
| `子规则开关` | `Enable` | toggle | `true` | |
| `分组` | `GroupKey` | select, `groupOptions` | `""` | |
| `服务类型` | `WebServiceType` | select, `availableServiceTypes` | `"reverseproxy"` | filter uses the parent's `tlsEnabled` |
| `前端地址` | `Domains` | multiline, hint `每行填写一个域名或访问地址` | `[""]` | |
| `后端地址` / `目标地址` | `Locations` | multiline, hint `每行填写一个地址` | `[""]` | label is `后端地址` when `WebServiceType === "reverseproxy"`, else `目标地址` |
| `CorazaWAF` | `CorazaWAFInstance` | select, `跟随主规则`=`main` + `wafOptions` minus `main` | `""` | |
| `万事大吉` | `EasyLucky` | toggle | `true` | |
| `忽略后端 TLS 证书验证` | `LocationInsecureSkipVerify` | toggle | `true` | |
| `使用目标地址 Host 请求头` | `UseTargetHost` | toggle | `false` | |
| `自动反代重定向` | `AutoProxyLocation` | toggle | `false` | |
| `不同 Host 也自动改写重定向` | `AutoProxyLocationWithoutSameHost` | toggle | `false` | only when `ruleMode === "diy" && AutoProxyLocation` |
| `记录访问日志` | `EnableAccessLog` | toggle | `true` | |

### 21.5 `rule` editor — inline sub-rule accordion (`子规则`)

Header row (`minHeight 30`, gap 8): `Route` `colors.primary` size **18**, title `子规则`
(`flex 1`, size **15**, `"800"`), meta `` `${proxies.length} 项` `` (`colors.subtext`,
size 11, `"600"`).

Each card: radius **14**, `borderWidth 1` in `open ? colors.primary : colors.border`,
background `colors.card`, `padding 12`, `gap 12`. `draftId = proxyDraftIds[index] ??
`proxy-${index}``.
Head `Pressable` (gap **9**) toggles `expandedProxyId`: a **34×34** radius **10**
`colors.primarySoft` tile with `Network` `colors.primary` size **17**;
`title = pick(proxy, ["Remark"], `子规则 ${index+1}`) || `子规则 ${index+1}`` (`numberOfLines 1`,
size **13**, `"800"`); second line `cleanLines(proxy.Domains)[0] ?? "未填写前端地址"`
(`numberOfLines 1`, `colors.subtext`, size **10**, `marginTop 2`); trailing
`ChevronUp`/`ChevronDown` `colors.subtext` size **17**.
Action row (`flex-end`, gap 7): `IconButton Pencil` a11y `` `编辑${title}` `` / visible
`编辑` / `colors.primary` → expands the card; `IconButton Trash2` a11y `` `移除${title}` `` /
visible `移除` / `colors.danger` → `removeProxy(index, draftId)`.
Open body: `borderTopWidth 1` `colors.rowBorder`, `paddingTop 12`, `gap 10` — then
`SubRuleFields` (scope `draftId`, `ruleMode = String(value.DiaglogShowMode ?? "simple")`,
`tlsEnabled = asBoolean(value.EnableTLS)`), a divider, the `安全设置` sub-heading, and
`SecurityFields` (scope `` `${draftId}-security` ``,
`showIpFilter = diyMode || proxy.WebServiceType === "SNIRouting"`).

Footer button `添加子规则`: height **44**, radius **12**, `borderWidth 1` `colors.primary`,
background `colors.primarySoft`, `Plus` `colors.primary` 17, label `colors.primary` size
**13** `"800"` → `addProxy()`.

### 21.6 `subrule` editor

Two sections only: `FormSection("基础设置", icon Network)` wrapping `SubRuleFields`
(scope `"subrule"`, `ruleMode = editor.ruleMode ?? "simple"`,
`tlsEnabled = asBoolean(editor.tlsEnabled)`), and
`FormSection("安全设置", icon ShieldCheck)` wrapping `SecurityFields`
(scope `"subrule-security"`,
`showIpFilter = editor.ruleMode === "diy" || value.WebServiceType === "SNIRouting"`).

### 21.7 `group` editor

| label | key | control | default | notes |
|---|---|---|---|---|
| `分组名称` | `Name` | text | `""` | |
| `分组 Key` | `Key` | text, `readOnly` | `""` | rendered **only when editing** (`editor.key` set) |

No `FormSection` wrapper. Note `createWebServiceGroup` transmits only `Name`; the update
call sends the whole object.

### 21.8 `cgi` editor (no `FormSection` wrapper)

| label | key | control | default |
|---|---|---|---|
| `实例名称` | `Name` | text | `""` |
| `启用 CGI` | `Enable` | toggle | `true` |
| `CGI 类型` | `CGIType` | choices from the bare strings `["php","fastcgi"]` (label = value) | `"php"` |
| `网络协议` | `Network` | choices `["tcp","tcp4","tcp6","unix"]` | `"tcp"` |
| `服务地址` | `Address` | text, hint `例如 127.0.0.1:9000` | `"127.0.0.1:9000"` |
| `最大连接数` | `MaxConns` | numeric | `10` |
| `连接超时（秒）` | `ConnectTimeout` | numeric | `30` |
| `默认文档根目录` | `DefaultDocRoot` | text | `""` |
| `默认首页` | `DefaultIndexNames` | multiline, hint `每行一个文件名` | `"index.php\n"` |
| `文件扩展名` | `FileExtensions` | text | `".php"` |
| `禁止访问路径` | `ForbiddenPaths` | multiline (no hint) | `""` |

### 21.9 `settings` and `template` editors

Both fall through to `<StructuredForm value={value} onChange={setValue} />` — the generic
recursive JSON form (§6). `settings` starts from `clone(settings.data)`; `template` starts
from `{}`, so the user adds keys by hand. Neither runs any validation in `save()`.
## 22. `save()` validation, in exact evaluation order

All messages go to `formError` (rendered by `ErrorState` above the footer) and abort the
save. `formError` is cleared to `""` only immediately before `onSave(nextValue)`.

`normalizeProxy(item, label)` — used for every proxy. It first canonicalises with
`normalizeWebProxy(item, newWebServiceSubRule())`, then
`domains = cleanLines(canonical.Domains)`, `locations = cleanLines(canonical.Locations)`:

| condition | message |
|---|---|
| `!domains.length` | `` `${label}至少需要一个前端地址` `` |
| `["reverseproxy","redirect","url"].includes(WebServiceType) && !locations.length` | `` `${label}必须填写目标地址` `` |
| `!UseRuleGlobalAuthSettings && EnableBasicAuth && !String(BasicAuthUserList ?? "").trim()` | `` `${label}启用 Basic 认证后必须填写认证用户` `` |

On success it returns `{ ...canonical, Domains: domains, Locations: locations }`.

**`editor.type === "subrule"`**
1. `normalizeProxy(value, "子规则")` → messages `子规则至少需要一个前端地址`,
   `子规则必须填写目标地址`, `子规则启用 Basic 认证后必须填写认证用户`.
2. `!editor.tlsEnabled && tlsOnlyWebServiceTypes.has(WebServiceType)` →
   `当前服务类型需要先在主规则中启用 TLS`.
3. `nextValue` = the normalised proxy.

**`editor.type === "rule"`** — with `network = String(value.Network ?? "")`,
`port = Number(value.ListenPort)`, `tlsMinVersion = Number(value.TLSMinVersion)`:

| order | condition | message |
|---|---|---|
| 1 | `!["tcp","tcp4","tcp6"].includes(network)` | `请选择至少一种监听类型` |
| 2 | `!Number.isInteger(port) \|\| port < 1 \|\| port > 65535` | `监听端口必须在 1 到 65535 之间` |
| 3 | `asBoolean(EnableTLS) && (!Number.isInteger(tlsMinVersion) \|\| tlsMinVersion < 0 \|\| tlsMinVersion > 3)` | `请选择有效的 TLS 最低版本` |
| 4 | `!asBoolean(EnableTLS) && tlsOnlyWebServiceTypes.has(defaultProxy.WebServiceType)` | `默认规则的当前服务类型需要启用 TLS` |
| 5 | `["redirect","url"].includes(defaultProxy.WebServiceType) && !cleanLines(defaultProxy.Locations).length` | `默认规则使用跳转服务时必须填写目标地址` |
| 6 | `!defaultProxy.UseRuleGlobalAuthSettings && defaultProxy.EnableBasicAuth && !String(defaultProxy.BasicAuthUserList ?? "").trim()` | `默认规则启用 Basic 认证后必须填写认证用户` |
| 7 | per `ProxyList` entry, `normalizeProxy(item, `子规则 ${index + 1} `)` | `` `子规则 N 至少需要一个前端地址` `` / `` `子规则 N 必须填写目标地址` `` / `` `子规则 N 启用 Basic 认证后必须填写认证用户` `` — **note the trailing space inside the label template**, so the message reads `子规则 1 至少需要一个前端地址` |
| 8 | per entry, `!asBoolean(EnableTLS) && tlsOnlyWebServiceTypes.has(WebServiceType)` | `` `子规则 ${index + 1} 的当前服务类型需要启用 TLS` `` |

Step 4's `defaultProxy` is `normalizeWebProxy(value.DefaultProxy, newWebServiceDefaultProxy())`.
The saved payload is
`{ ...value, Network: network, ListenPort: port, TLSMinVersion: tlsMinVersion,
DefaultProxy: { ...defaultProxy, Locations: cleanLines(defaultProxy.Locations) },
ProxyList: proxies }` — i.e. the string-valued `TLSMinVersion` written by `Choices` is
converted back to a number, and the default proxy's `Locations` become a clean array.
`DiaglogShowMode` is **not** converted; `"diy"` is sent as-is even though the server's own
term is `"full"`.

Other editor types run no validation at all; `nextValue === value`.

## 23. Numeric constants (complete)

| constant | value |
|---|---|
| `WEB_LOG_PAGE_SIZE` | `50` |
| `WEB_SERVICE_GROUP_COUNT_CONCURRENCY` | `4` |
| `DEFAULT_REQUEST_TIMEOUT_MS` (`lucky-fetch`) | `12000` |
| upload `timeoutMs` | `600000` |
| log auto-refresh `refetchInterval` | `15000` |
| global `staleTime` / `gcTime` / `retry` | `30000` / `120000` / `1` |
| `CARD_RADIUS` / `CONTROL_RADIUS` | `18` / `12` |
| `Page` `maxWidth` / paddings / `gap` | `820` / h 16, top 14, bottom 110 (12 when non-scrollable) / 16 |
| `ResponsiveTabBar` single-row threshold | `width >= tabs.length * 82 + 40` → **532** for 6 tabs |
| `FlatList` `paddingBottom` | `98` (all four lists) |
| separators | rules/groups/cgi `12`, logs `10` |
| `initialNumToRender` / `maxToRenderPerBatch` / `windowSize` | rules `6/6/7`; groups & cgi `8/8/7`; logs `12/12/7` |
| add-rule button height | `46` (rules) vs `44` (groups, cgi) vs `42` (settings, tools template) vs `40` (tools outline) |
| rule icon tile | `36×36`, radius `8` |
| editor proxy tile | `34×34`, radius `10` |
| `Field` heights | single line `44`, multiline `minHeight 92` |
| `PortStepper` | buttons `42×42` radius `12`; input height `42`, `maxLength 5`; base `16666`; clamp `1…65535` |
| `FormSection` | `padding 14`, radius `14`, `gap 10`, header `minHeight 26` |
| footer buttons | `minHeight 48`, radius `12`, `flex 1` vs `flex 1.4` |
| folder modal | backdrop `rgba(0,0,0,0.42)`, `padding 22`; card `maxWidth 520`, radius `20`, `padding 18`, `gap 14`; input `44`/radius `12`; buttons `44`/radius `12` |
| log toolbar | container `minHeight 46` radius `12` `padding 6` `gap 7`; chips `minHeight 36` radius `9` `paddingHorizontal 11`; pager `38×36` radius `9`; counter `minWidth 54`; disabled `opacity 0.4` |
| empty-log indicator box | `minHeight 180` |
| `StructuredDataView` caps | 200 object entries / 200 array items |
| editor close button | `36×36`, radius `12`, disabled `opacity 0.45` |

## 24. Fidelity checklist — behaviours easy to lose in the port

- `enabled(item)` defaults to **`true`** when neither `Enable` nor `enable` exists.
- `asBoolean(value, fallback = false)`: `undefined`, `null` and blank/whitespace strings →
  `fallback`; `false` and `0` → false; a string matching `/^(?:false|0|off|no|disabled)$/i`
  (after trimming) → false; **everything else → true**.
- Sub-rule enable/disable is a **GET** with the boolean in the path, not a PUT body.
- `getWebServiceIpFilterRules` calls the misspelled path `/api/ipfliter/list` — keep it.
- `GroupOrderEditor`'s busy label is `保存中...`; the editor's is `保存中`.
- Reorder endpoints receive a bare JSON array, not an object.
- The rules list is the only view with an accordion; expanding one rule collapses the other
  (`expanded` holds a single key).
- `mutation.reset()` runs when the editor closes, so a stale `serverError` never reappears.
- Log auto-refresh stops on page 2+ in page mode and whenever the screen is unfocused.
