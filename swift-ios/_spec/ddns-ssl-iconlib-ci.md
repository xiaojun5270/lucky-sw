# Lucky Mobile → Swift: `ddns` / `ssl` / `iconlib` service spec + iOS CI

Transcribed verbatim from the TypeScript sources. Every signature, path, query key,
JSON key and Chinese string below is copied exactly; nothing is normalised.

Sources read in full:

| # | File | Size |
|---|---|---|
| 1 | `C:\Users\xiaoj\Desktop\lucky\src\services\ddns.ts` | 88 lines |
| 2 | `C:\Users\xiaoj\Desktop\lucky\src\services\ssl.ts` | 98 lines |
| 3 | `C:\Users\xiaoj\Desktop\lucky\src\services\iconlib.ts` | 15 lines |
| 4 | `C:\Users\xiaoj\Desktop\lucky\package.json` | 95 lines |
| 5 | `C:\Users\xiaoj\Desktop\lucky\.github\workflows\ios-unsigned-ipa.yml` | 153 lines |

Supporting files consulted (transport, types, and the only icon-URL construction site):
`C:\Users\xiaoj\Desktop\lucky\src\lib\lucky-fetch.ts`,
`C:\Users\xiaoj\Desktop\lucky\src\types\lucky.ts`,
`C:\Users\xiaoj\Desktop\lucky\app\docker.tsx`.

---

## 1. Distinct API paths across the three modules

37 exported functions resolve to 36 distinct `luckyFetch` path templates, plus one
non-fetch image URL template (row 37). Conventions in the table:

- `{x}` = `encodeURIComponent(x)` interpolated into the path.
- `?a={a}` = query key emitted by the shared `query()` helper (§3.3); the pair is
  **omitted entirely** when the value is `undefined`, `null` or `""`, and the key
  order shown is the emission order.
- Every `luckyFetch` row (1–36) additionally receives a cache-buster `_=<nonce>`
  appended by the transport (§3.2): `?` when the path has no query yet, else `&`.
- Row 37 is built by hand in a React component and gets **no** nonce.

| # | Method | Path template | Function | Body |
|---|---|---|---|---|
| 1 | GET | `/api/ddnstasklist` | `getDdnsTasks` | — |
| 2 | GET | `/api/ddns/task/{key}` | `getDdnsTask` | — |
| 3 | POST | `/api/ddns` | `createDdnsTask` | `JSON.stringify(value)` |
| 4 | PUT | `/api/ddns?key={key}` | `updateDdnsTask` | `JSON.stringify(value)` |
| 5 | DELETE | `/api/ddns?key={key}` | `deleteDdnsTask` | — |
| 6 | GET | `/api/ddns/enable?enable={enable}&key={key}` | `setDdnsTaskEnabled` | — |
| 7 | GET | `/api/ddns/expanded?expanded={expanded}&key={key}` | `setDdnsTaskExpanded` | — |
| 8 | GET | `/api/ddns/ipsectionexpanded?expanded={expanded}&key={key}` | `setDdnsIpSectionExpanded` | — |
| 9 | GET | `/api/ddns/manualSync/{key}` | `syncDdnsTask` | — |
| 10 | GET | `/api/ddns/configure` | `getDdnsConfigure` | — |
| 11 | PUT | `/api/ddns/configure` | `updateDdnsConfigure` | `JSON.stringify(value)` |
| 12 | GET | `/api/ddns/odhcpdclients` | `getDdnsOdhcpdClients` | — |

| 13 | GET | `/api/ddns/getipfromcmdtest?iptype={iptype}&command={command}` | `testDdnsIpCommand` | — |
| 14 | POST | `/api/ddns/webhooktest?key={key}` | `testDdnsWebhook` | `JSON.stringify(value)` |
| 15 | PUT | `/api/ddns/taskorderadjustment` | `reorderDdnsTasks` | `JSON.stringify(keys)` |
| 16 | PUT | `/api/ddns/recordOrderadjustment/{taskKey}` | `reorderDdnsRecords` | `JSON.stringify(keys)` |
| 17 | DELETE | `/api/ddns/{taskKey}/{recordKey}` | `deleteDdnsRecord` | — |
| 18 | PUT | `/api/ddns/{taskKey}/{recordKey}/option/{option}` | `setDdnsRecordOption` | — |
| 19 | GET | `/api/ddns/logs?pageSize={pageSize}&page={page}` | `getDdnsLogs` | — |
| 20 | GET | `/api/ddns/lastlogs` | `getDdnsLastLogs` | — |
| 21 | GET | `/api/ssl` | `getSslCertificates` | — |
| 22 | GET | `/api/ssl/{key}` | `getSslCertificate` | — |
| 23 | POST | `/api/ssl` | `createSslCertificate` | `JSON.stringify(value)` |
| 24 | PUT | `/api/ssl` | `updateSslCertificate` | `JSON.stringify(value)` |
| 25 | DELETE | `/api/ssl?key={key}` | `deleteSslCertificate` | — |
| 26 | PUT | `/api/ssl/{key}?enable={enable}` | `setSslCertificateEnabled` | — |
| 27 | PUT | `/api/ssl/flush?key={key}` | `flushSslCertificate` | — |
| 28 | GET | `/api/ssl/manualsync/{key}` | `syncSslCertificate` | — |
| 29 | PUT | `/api/ssl/sslorderadjustment` | `reorderSslCertificates` | `JSON.stringify(keys)` |
| 30 | GET | `/api/ssl/syncclients` | `getSslSyncClients`, `getSslSyncClientOptions` | — |
| 31 | GET | `/api/ssl/setting` | `getSslSetting` | — |
| 32 | PUT | `/api/ssl/setting` | `updateSslSetting` | `JSON.stringify(value)` |
| 33 | DELETE | `/api/ssl/{key}/acmecancel` | `cancelSslAcme` | — |
| 34 | GET | `/api/ssl/logs?key={key}&pageSize={pageSize}&page={page}` | `getSslLogs` | — |
| 35 | GET | `/api/ssl/lastlogs?key={key}` | `getSslLastLogs` | — |
| 36 | GET | `/api/iconlib/icons` | `getIconLibraryIcons` | — |
| 37 | GET | `/api/iconlib/icon?path={relativePath}` | *(image URL, `app/docker.tsx:741`)* | — |

Casing traps that must survive the port verbatim: `manualSync` (ddns, camelCase) vs
`manualsync` (ssl, all-lower); `recordOrderadjustment` (ddns) vs
`taskorderadjustment` (ddns) vs `sslorderadjustment` (ssl); `ddnstasklist` is a
top-level path (`/api/ddnstasklist`), **not** under `/api/ddns/`.

---

## 2. Type aliases (`src/types/lucky.ts`)

```ts
export type LuckyRecord = Record<string, unknown>;
export type LuckyResponse<T extends LuckyRecord = LuckyRecord> = T & { ret: number; msg?: string };
export type LuckyListItem = LuckyRecord & {
  Key?: string; key?: string; id?: string; Name?: string; name?: string;
  TaskName?: string; Enable?: boolean; enable?: boolean; status?: string; Status?: string;
};
```

Swift equivalent: `LuckyRecord` = `[String: JSONValue]` (an enum-backed dynamic JSON
value), **not** a concrete `Codable` struct — the extractors below index arbitrary keys
at runtime and the port must keep that flexibility.

---

## 3. Shared transport + helpers (must be ported before the three modules)

### 3.1 `luckyFetch(path, options)` — `src/lib/lucky-fetch.ts`

All 37 functions go through it. Contract the three modules depend on:

- URL = `baseUrl.trim()` with trailing `/`s stripped + `withLuckyRequestNonce(path)`;
  `baseUrl` comes from `luckySessionState.baseUrl` unless overridden. Empty base URL
  throws `Error("请输入 Lucky 服务地址")`.
- Default timeout **12000 ms** (`DEFAULT_REQUEST_TIMEOUT_MS`) via an internal
  `AbortController`; an external `signal` is chained onto it.
- Headers: `Accept: application/json` (unless already set); `Content-Type:
  application/json` whenever a body is present and it is not `FormData`/`Blob`;
  `Lucky-Admin-Token: <token>` when a token exists.
- Returns the **whole envelope** `LuckyResponse` (i.e. `{ ret, msg, ...payload }`), not
  `payload.data`. `ret` is coerced through `numericRet` and defaults to `0`.
  A non-object JSON body becomes `{ ret: 0, data: parsed }`.
  HTTP 204 or `content-length: 0` becomes `{ ret: 0 }`.
- Auth: HTTP 401 or `ret === -1` triggers one token refresh (`POST /api/login` with body
  `{"Account","Password","TwoFA","TwoFACode"}`) and one retry with `retryAuth: false`;
  on refresh failure the session is ended and a `LuckyAuthError` is thrown
  (default message `"登录已失效，请重新登录"`).
- Failure: `!response.ok || ret !== 0` → `Error(payload.msg || \`请求失败（HTTP ${status}）\`)`.
  So a Lucky-side error message is surfaced through `msg`; this is the channel the
  `syncSslCertificate` guard (§5.8) matches against.

### 3.2 `createLuckyRequestNonce` / `withLuckyRequestNonce` (exported, shared)

```ts
export function createLuckyRequestNonce(now = Date.now()) {
  const timestamp = String(now).slice(0, -1);                                    // drop last ms digit
  const checksum = [...timestamp].reduce((sum, digit) => sum + Number(digit), 0) % 8;
  return `${timestamp}${checksum}`;
}
export function withLuckyRequestNonce(path: string, now = Date.now()) {
  const separator = path.includes('?') ? '&' : '?';
  return `${path}${separator}_=${createLuckyRequestNonce(now)}`;
}
```

Swift: `let ts = String(Int(Date().timeIntervalSince1970 * 1000)).dropLast()`, sum of
decimal digits `% 8`, concatenate; append as `_=`.

### 3.3 Non-exported helpers duplicated **verbatim** in `ddns.ts` and `ssl.ts`

Both files declare their own private copies; `iconlib.ts` declares only `isRecord`.

```ts
function isRecord(value: unknown): value is LuckyRecord {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function query(params: LuckyRecord) {
  const value = Object.entries(params)
    .filter(([, item]) => item !== undefined && item !== null && item !== "")
    .map(([key, item]) => `${encodeURIComponent(key)}=${encodeURIComponent(String(item))}`)
    .join("&");
  return value ? `?${value}` : "";
}
```

`query()` semantics that must be reproduced exactly:

1. Drop order-sensitive keys only when value is `undefined`, `null`, or `""`.
   `false` and `0` are **kept** (`enable=false`, `page=0` are emitted).
2. Values are stringified with JS `String()`: booleans → `"true"`/`"false"`,
   numbers → shortest decimal form (`100` → `"100"`).
3. Both key and value are `encodeURIComponent`-escaped.
4. Returns `""` when nothing survives, so the path stays bare (`/api/ssl`).
5. Emission order = literal property order at the call site (`{ enable, key }`
   → `enable=…&key=…`; `{ key, pageSize, page }` → `key=…&pageSize=…&page=…`).

`encodeURIComponent` leaves `A–Z a–z 0–9 - _ . ! ~ * ' ( )` unescaped and encodes
everything else UTF-8 percent-style, **including `/`** (→ `%2F`). Swift's
`addingPercentEncoding(withAllowedCharacters:)` with `.urlQueryAllowed` or
`.urlPathAllowed` is **not** equivalent; use an explicit allowed set:

```swift
private let luckyUnreserved = CharacterSet(charactersIn:
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
```

This same escaping is used for interpolated **path** segments
(`/api/ddns/task/${encodeURIComponent(key)}`), so a key containing `/` becomes `%2F`
rather than an extra path segment. Do not switch to `URLComponents`
default behaviour here.

---

## 4. `src/services/ddns.ts` — 20 exported functions

### 4.0 Private extractor: `taskScore` + `extractTasks`

```ts
function taskScore(value: LuckyRecord) {
  return ["TaskKey", "taskKey", "DDNSTaskKey", "Key", "key", "TaskName", "taskName",
          "DDNSTaskName", "Name", "name", "Records", "records", "DNSProvider", "dnsProvider"]
    .reduce((score, key) => score + (value[key] !== undefined ? 1 : 0), 0);
}
```

14 probe keys, `+1` per key **present** (`!== undefined`; a key explicitly set to
`null` still scores).

`extractTasks(payload)` is a breadth-first search for the "most task-like" array in an
arbitrarily shaped envelope. Exact algorithm:

```
queue   = [payload]            // FIFO, shift() from front, push() to back
visited = Set<object>()        // identity-based cycle guard
best = [] ; bestScore = 0
while queue not empty:
  current = queue.shift()
  if !current or typeof current !== "object" or visited.has(current): continue
  visited.add(current)
  if Array.isArray(current):
      records = current.filter(isRecord)                 // non-array objects only
      score   = sum(taskScore(r) for r in records)
      if records.length && score > bestScore: best = records; bestScore = score
      queue.push(...current)                             // all elements, incl. non-objects
      continue
  // plain object branch — DDNS ONLY: also treat the object's values as a task map
  mapped      = Object.values(current).filter(isRecord)
  mappedScore = sum(taskScore(m) for m in mapped)
  if mapped.length && mappedScore > bestScore: best = mapped; bestScore = mappedScore
  queue.push(...Object.values(current))
return bestScore > 0 ? best : []
```

Notes for the port: strictly `>` (first winner keeps ties, and BFS order therefore
matters — shallower candidates win ties); the object-values branch means a
`{"key1": {...}, "key2": {...}}` map is accepted as a task list; the top-level envelope
itself is scanned, so `{ret, msg, data:{…task}}` yields `[data]`.

### 4.1 `getDdnsTasks(signal?: AbortSignal)` — `async function`

`GET /api/ddnstasklist` (signal forwarded). Returns
`{ items: LuckyListItem[], raw: LuckyResponse }` where `items = extractTasks(raw)` and
`raw` is the untouched envelope. **Both fields are consumed by callers** — the Swift
port must return a struct with both, e.g. `(items: [LuckyRecord], raw: LuckyRecord)`.

### 4.2 `getDdnsTask(key: string, signal?: AbortSignal)` — arrow, no unwrapping

`GET /api/ddns/task/{key}` → raw envelope.

### 4.3 `createDdnsTask(value: LuckyRecord)`

`POST /api/ddns`, body `JSON.stringify(value)`. The caller-supplied record is sent
**as-is**: no key renaming, no defaults injected, no pruning of `undefined` (JS
`JSON.stringify` silently drops `undefined`-valued keys — a Swift encoder must do the
same by omitting them rather than emitting `null`).

### 4.4 `updateDdnsTask(key: string, value: LuckyRecord)`

`PUT /api/ddns?key={key}`, body `JSON.stringify(value)`.

### 4.5 `deleteDdnsTask(key: string)`

`DELETE /api/ddns?key={key}`, no body.

### 4.6 `setDdnsTaskEnabled(key: string, enable: boolean)`

`GET /api/ddns/enable?enable={enable}&key={key}` — note the method is **GET**, not
PUT/POST, and `enable` precedes `key`. `enable` serialises as `"true"`/`"false"`.

### 4.7 `setDdnsTaskExpanded(key: string, expanded: boolean)`

`GET /api/ddns/expanded?expanded={expanded}&key={key}`.

### 4.8 `setDdnsIpSectionExpanded(key: string, expanded: boolean)`

`GET /api/ddns/ipsectionexpanded?expanded={expanded}&key={key}`.

### 4.9 `syncDdnsTask(key: string)`

`GET /api/ddns/manualSync/{key}` — camelCase `manualSync`.

### 4.10 `getDdnsConfigure(signal?: AbortSignal)` / 4.11 `updateDdnsConfigure(value: LuckyRecord)`

`GET /api/ddns/configure` / `PUT /api/ddns/configure` with body `JSON.stringify(value)`.

### 4.12 `getDdnsOdhcpdClients(signal?: AbortSignal)`

`GET /api/ddns/odhcpdclients`.

### 4.13 `testDdnsIpCommand(iptype: string, command: string, signal?: AbortSignal)`

`GET /api/ddns/getipfromcmdtest?iptype={iptype}&command={command}`. Both values are
percent-encoded; an empty `command` drops the pair entirely.

### 4.14 `testDdnsWebhook(key: string, value: LuckyRecord, signal?: AbortSignal)`

`POST /api/ddns/webhooktest?key={key}`, body `JSON.stringify(value)`, signal forwarded.
The only POST in the module that also carries a query string.

### 4.15 `reorderDdnsTasks(keys: unknown)`

`PUT /api/ddns/taskorderadjustment`, body `JSON.stringify(keys)`. `keys` is typed
`unknown`; call sites pass an **array of task keys**, so the body is a bare JSON array
(e.g. `["k1","k2"]`), not an object. Swift must encode a top-level array.

### 4.16 `reorderDdnsRecords(taskKey: string, keys: unknown)`

`PUT /api/ddns/recordOrderadjustment/{taskKey}`, body `JSON.stringify(keys)` (bare array).

### 4.17 `deleteDdnsRecord(taskKey: string, recordKey: string)`

`DELETE /api/ddns/{taskKey}/{recordKey}` — both segments individually encoded.

### 4.18 `setDdnsRecordOption(taskKey: string, recordKey: string, option: string)`

`PUT /api/ddns/{taskKey}/{recordKey}/option/{option}` — three encoded segments, no body.

### 4.19 `getDdnsLogs(pageSize = 100, page = 1, signal?: AbortSignal)`

`GET /api/ddns/logs?pageSize={pageSize}&page={page}` — **defaults `pageSize=100`,
`page=1`**, `pageSize` first. Note there is no `key` parameter here (unlike SSL).

### 4.20 `getDdnsLastLogs(signal?: AbortSignal)`

`GET /api/ddns/lastlogs` — no query at all (unlike SSL's `lastlogs`, which takes `key`).

**Client-side validation in `ddns.ts`: none.** No empty-key checks, no Chinese error
strings, no try/catch. All error text reaching the UI comes from `luckyFetch` (§3.1).

---

## 5. `src/services/ssl.ts` — 16 exported functions

### 5.0 Private extractor: `certificateScore` + `extractCertificates`

```ts
function certificateScore(item: LuckyRecord) {
  return ["Key", "key", "Remark", "remark", "AddFrom", "CertsInfo", "ExtParams", "SyncInfo"]
    .reduce((score, key) => score + (item[key] !== undefined ? 1 : 0), 0);
}
```

`extractCertificates(payload)` is the same BFS as `extractTasks` **minus the
object-values branch** — only real arrays can win:

```
queue = [payload]; visited = Set(); best = []; bestScore = 0
while queue:
  current = queue.shift()
  if !current or typeof current !== "object" or visited.has(current): continue
  visited.add(current)
  if Array.isArray(current):
      records = current.filter(isRecord)
      score   = sum(certificateScore(r) for r in records)
      if records.length && score > bestScore: best = records; bestScore = score
      queue.push(...current); continue
  queue.push(...Object.values(current))     // plain object: recurse only
return bestScore > 0 ? best : []
```

8 probe keys, `+1` each. Do **not** copy the DDNS map-of-objects behaviour here.

### 5.1 `getSslCertificates(signal?: AbortSignal)` — `async function`

`GET /api/ssl`. Returns `{ items: extractCertificates(raw), raw }`.

### 5.2 `getSslCertificate(key: string, signal?: AbortSignal)`

`GET /api/ssl/{key}` → raw envelope.

### 5.3 `createSslCertificate(value: LuckyRecord)`

`POST /api/ssl`, body `JSON.stringify(value)` — **no `key` in the query**.

### 5.4 `updateSslCertificate(value: LuckyRecord)`

`PUT /api/ssl`, body `JSON.stringify(value)` — also **no query key**; the certificate
identity travels inside the body (asymmetric with `updateDdnsTask`, which uses `?key=`).

### 5.5 `deleteSslCertificate(key: string)`

`DELETE /api/ssl?key={key}`.

### 5.6 `setSslCertificateEnabled(key: string, enable: boolean)`

`PUT /api/ssl/{key}?enable={enable}` — **PUT** here, whereas the DDNS equivalent is GET,
and the key is a path segment rather than a query parameter.

### 5.7 `flushSslCertificate(key: string)`

`PUT /api/ssl/flush?key={key}`, no body.

### 5.8 `syncSslCertificate(key: string)` — the only error-translating function

```ts
export async function syncSslCertificate(key: string) {
  try {
    return await luckyFetch(`/api/ssl/manualsync/${encodeURIComponent(key)}`);
  } catch (error) {
    if (error instanceof Error && /PermissionDeniedCannotUseSyncFunction/i.test(error.message))
      throw new Error("当前账号没有证书分发同步权限");
    throw error;
  }
}
```

`GET /api/ssl/manualsync/{key}` (all-lowercase `manualsync`). Validation/translation:
if the thrown error's `message` matches `/PermissionDeniedCannotUseSyncFunction/i`
(**case-insensitive substring**, not equality), replace it with the verbatim Chinese
string `当前账号没有证书分发同步权限`; otherwise rethrow untouched. The matched text
arrives via `payload.msg` from `luckyFetch`. Swift: `range(of:options: .caseInsensitive)`
on the localized description, then `throw LuckyError.message("当前账号没有证书分发同步权限")`.
Preserve the rethrow path — a `LuckyAuthError` must not be downgraded.

### 5.9 `reorderSslCertificates(keys: unknown)`

`PUT /api/ssl/sslorderadjustment`, body `JSON.stringify(keys)` (bare array).

### 5.10 `getSslSyncClients(signal?: AbortSignal)`

`GET /api/ssl/syncclients` → raw envelope.

### 5.11 `getSslSyncClientOptions(signal?: AbortSignal)` — `async function`

Calls `getSslSyncClients(signal)` (same `GET /api/ssl/syncclients`, one request) and runs
a **third, inline BFS** with its own scoring. Differences from §5.0:

- probe keys: `["Key", "ClientKey", "Name", "ClientName", "DeviceName"]` (5 keys), scored
  per item as `keys.filter(k => item[k] !== undefined).length`, summed over the array;
- array branch pushes children and falls through (no `continue`; the object branch is an
  `else`) — behaviourally identical to §5.0's `continue`;
- **returns `best` directly**, with no `bestScore > 0` gate. `best` is initialised to `[]`
  and only reassigned when `score > bestScore` (from `0`), so an all-zero-scoring array is
  still rejected; the observable result matches `bestScore > 0 ? best : []`.

Return type: `LuckyListItem[]` (flat array, no envelope).

### 5.12 `getSslSetting(signal?: AbortSignal)` / 5.13 `updateSslSetting(value: LuckyRecord)`

`GET /api/ssl/setting` / `PUT /api/ssl/setting` with body `JSON.stringify(value)`.

### 5.14 `cancelSslAcme(key: string)`

`DELETE /api/ssl/{key}/acmecancel` — DELETE with a trailing action segment, no body.

### 5.15 `getSslLogs(key = "", pageSize = 100, page = 1, signal?: AbortSignal)`

`GET /api/ssl/logs?key={key}&pageSize={pageSize}&page={page}`. Defaults `key=""`,
`pageSize=100`, `page=1`. Because `query()` drops `""`, the default call emits
`/api/ssl/logs?pageSize=100&page=1`. Swift: `key: String = ""`, `pageSize: Int = 100`,
`page: Int = 1`, and keep the key-first emission order.

### 5.16 `getSslLastLogs(key = "", signal?: AbortSignal)`

`GET /api/ssl/lastlogs?key={key}`; default `key=""` → `/api/ssl/lastlogs`.

**Client-side validation in `ssl.ts`:** only §5.8. The single verbatim Chinese message in
the module is `当前账号没有证书分发同步权限`. No empty-key/format checks anywhere.

---

## 6. `src/services/iconlib.ts` — 1 exported function

Full source (15 lines):

```ts
import { luckyFetch } from "@/src/lib/lucky-fetch";
import type { LuckyRecord } from "@/src/types/lucky";

function isRecord(value: unknown): value is LuckyRecord {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

export async function getIconLibraryIcons() {
  const payload = await luckyFetch("/api/iconlib/icons");
  for (const source of [payload, payload.data, payload.result]) {
    if (!isRecord(source)) continue;
    if (Array.isArray(source.icons)) return source.icons.filter(isRecord);
  }
  return [];
}
```

### 6.1 `getIconLibraryIcons()` — no parameters, no `AbortSignal`

`GET /api/iconlib/icons`, no query, no body. Note the missing `signal` parameter: the
call site (`app/docker.tsx:1437`, `queryFn: getIconLibraryIcons`) cannot cancel it.

**Unwrapping — candidates probed in this exact order, first match wins:**

1. `payload` (the envelope itself → `payload.icons`)
2. `payload.data` → `payload.data.icons`
3. `payload.result` → `payload.result.icons`

A candidate is skipped when it is not a non-array object; the `icons` value must be an
array or the loop continues to the next candidate. The winning array is filtered with
`isRecord`, i.e. nested arrays / strings / numbers / `null` inside `icons` are dropped.
No recursive BFS here (unlike ddns/ssl) and no scoring. Fallback: `[]`.
Returned shape: `LuckyRecord[]` — a flat array of dictionaries, **not** the envelope.
Swift signature: `func getIconLibraryIcons() async throws -> [LuckyRecord]`.

### 6.2 Shape of an icon list entry

`iconlib.ts` itself imposes no shape. The consumer `containerIcon()`
(`app/docker.tsx:700-732`) reads each entry through `pick(item, keys, fallback = "")`
(`app/docker.tsx:493-502`), which returns the first key whose value is a `string` or
`number` (`String(value)`), joins arrays with `", "`, else the fallback:

- **path** = `pick(icon, ["RelativePath", "Path", "path"])` — first present wins;
  this is the value sent to the icon endpoint.
- **display/match name** = `pick(icon, ["Name", "FileName", "name"], path).toLowerCase()`
  — falls back to the path when no name key exists.

So a Swift model should stay tolerant: `RelativePath | Path | path` and
`Name | FileName | name`, all optional, resolved in that order.

### 6.3 How an icon URL is constructed (`app/docker.tsx:734-761`)

```ts
const external = /^(https?:|data:|file:)/i.test(icon);
const uri = !icon ? "" : external
  ? icon
  : `${luckySessionState.baseUrl.replace(/\/+$/, "")}/api/iconlib/icon?path=${encodeURIComponent(icon)}`;
```

Rules to reproduce:

1. Empty icon string → no URL, render the placeholder glyph.
2. If the icon string starts (case-insensitively) with `http:`, `https:`, `data:` or
   `file:` it is used **verbatim** as an absolute/inline URL.
3. Otherwise it is a server-relative library path: `baseUrl` with trailing slashes
   stripped + `/api/iconlib/icon?path=` + `encodeURIComponent(path)`.
4. This URL is built **directly, bypassing `luckyFetch`** — therefore **no `_=` nonce**
   and no automatic auth. The image loader adds the header manually:
   `headers: external || !token ? undefined : { "Lucky-Admin-Token": token }`.
   In Swift, `AsyncImage` cannot set headers — a `URLSession`-backed loader (or
   `URLRequest` + custom cache) is required for internal icons; external ones can use
   `AsyncImage` directly.
5. Which icon string is chosen: `containerIcon()` first takes the first non-blank of
   `item.Icon`, `item.icon`, `item.Logo`, `item.logo`, `item.ImageIcon`,
   `Labels["net.unraid.docker.icon"]`, `Labels["org.opencontainers.image.icon"]`,
   `Labels["com.docker.desktop.extension.icon"]`, `Labels.icon` (trimmed). Only if none
   exists does it fuzzy-match the icon library: terms = `Names|Name|name` and
   `Image|ImageName` lowercased and split on `/[\/:@._-]+/`, keeping terms of length ≥ 3
   that are not `latest`, `docker`, `library`, `ghcr`, `com`; per icon,
   `score += name === term ? 10 : name.includes(term) ? term.length : 0`; the highest
   scoring `path` is used only when `bestScore >= 3`, else `""`.

---

## 7. Verbatim Chinese error strings reachable from these three modules

Owned by the modules themselves:

| String | Origin | Trigger |
|---|---|---|
| `当前账号没有证书分发同步权限` | `ssl.ts:62` | server error message contains `PermissionDeniedCannotUseSyncFunction` (case-insensitive) |

Inherited from the shared transport (`src/lib/lucky-fetch.ts`) — every one of the 37
functions can surface these, so they belong in the Swift error layer:

| String | Line | Trigger |
|---|---|---|
| `请输入 Lucky 服务地址` | 129 | empty base URL |
| `请求失败（HTTP {status}）` | 174/184/191/197/217 | non-2xx with no `msg`, or `ret !== 0` with no `msg` |
| `请求已取消` | 222 | caller's `AbortSignal` fired |
| `请求超时，请检查服务器连接` | 223 | 12 s timeout elapsed |
| `登录已失效，请重新登录` | 5 | `LuckyAuthError` default (401 / `ret === -1` after failed refresh) |
| `重新登录失败：服务器返回了无法识别的数据` | 88 | re-login response body not JSON, HTTP ok |
| `重新登录失败（HTTP {status}）` | 89 | re-login response body not JSON, HTTP not ok |
| `重新登录成功但未返回 Token` | 97 | re-login succeeded, no token in body or `Lucky-Admin-Token` header |
| `重新登录超时，请检查服务器连接` | 102 | re-login timeout |
| `重新登录请求已取消` | 103 | re-login aborted |
| `重新登录失败，请检查服务器连接` | 104 | any other re-login failure |

Note the full-width parentheses `（）` in the HTTP messages — keep them byte-identical.

---

## 8. `package.json`

`name` `lucky-mobile`, `version` `1.0.0`, `main` `expo-router/entry`, `private: true`.

### 8.1 Scripts (16)

| Script | Command |
|---|---|
| `postinstall` | `node scripts/patch-expo-modules-jsi.mjs` |
| `generate:endpoints` | `node scripts/generate-endpoints.mjs` |
| `check:endpoints` | `node scripts/generate-endpoints.mjs --check` |
| `typecheck` | `tsc --noEmit` |
| `verify` | `npm run check:endpoints && npm run typecheck && npm audit --audit-level=low` |
| `start` | `expo start` |
| `android` | `expo start --android` |
| `ios` | `expo start --ios` |
| `eas:build:development` | `eas build --profile development` |
| `eas:build:preview` | `eas build --profile preview` |
| `eas:build:production` | `eas build --profile production` |
| `eas:update:preview` | `eas update --branch preview --message` |
| `eas:update:production` | `eas update --branch production --message` |
| `start:dev-client` | `expo start --dev-client` |
| `eas:build:development:android` | `eas build -p android --profile development` |
| `eas:build:development:ios` | `eas build -p ios --profile development` |

(16 entries; `verify` is the one CI runs.)

### 8.2 Dependencies (35) with exact version ranges, and the Swift-side plan

| Package | Version | Native Swift counterpart |
|---|---|---|
| `@hookform/resolvers` | `^5.2.2` | none — hand-roll validation binding |
| `@tanstack/react-query` | `^5.90.21` | **none — hand-roll** async cache/retry/invalidation |
| `babel-plugin-react-compiler` | `^1.0.0` | build-only, drop |
| `expo` | `~57.0.7` | drop (runtime replaced by native app) |
| `expo-build-properties` | `~57.0.6` | drop (Xcode build settings) |
| `expo-clipboard` | `~57.0.1` | `UIPasteboard.general` |
| `expo-constants` | `~57.0.3` | `Bundle.main.infoDictionary` |
| `expo-dev-client` | `~57.0.7` | drop |
| `expo-document-picker` | `~57.0.1` | `.fileImporter` / `UIDocumentPickerViewController` |
| `expo-file-system` | `~57.0.0` | `FileManager` |
| `expo-font` | `~57.0.0` | system fonts / `Font.custom` |
| `expo-image` | `~57.0.1` | `AsyncImage` + `URLSession`/`URLCache`; **header-capable loader must be hand-rolled** (§6.3) |
| `expo-linking` | `~57.0.3` | `UIApplication.shared.open`, `.onOpenURL` |
| `expo-router` | `~57.0.7` | `NavigationStack` / `TabView` |
| `expo-secure-store` | `~57.0.1` | Keychain (`Security`) |
| `expo-splash-screen` | `~57.0.4` | launch screen storyboard |
| `expo-status-bar` | `~57.0.1` | `.statusBarHidden` / `.toolbarColorScheme` |
| `expo-system-ui` | `~57.0.1` | `.preferredColorScheme`, window tint |
| `expo-updates` | `~57.0.8` | **no equivalent — OTA feature is dropped** |
| `lucide-react-native` | `^0.577.0` | SF Symbols for most glyphs; missing ones need custom `Path`/`Shape` |
| `pako` | `^3.0.1` | **none — hand-roll gzip** (`ungzip`, used in `src/hooks/use-lucky-status.ts:3,65`); `Compression` framework only does raw DEFLATE, so gzip header/CRC handling is manual |
| `protobufjs` | `^8.7.0` | **none first-party — hand-roll or add SwiftProtobuf**; `protobufjs/light` builds two message types at runtime in `use-lucky-status.ts:13-44` |
| `react` | `19.2.3` | SwiftUI |
| `react-hook-form` | `^7.71.2` | none — hand-roll form state/validation |
| `react-native` | `0.86.0` | SwiftUI / UIKit |
| `react-native-gesture-handler` | `~2.32.0` | SwiftUI gestures |
| `react-native-reanimated` | `4.5.0` | SwiftUI `withAnimation`, `.animation`, `phaseAnimator` |
| `react-native-safe-area-context` | `~5.7.0` | `safeAreaInsets` / `GeometryReader` |
| `react-native-screens` | `4.25.2` | native navigation, drop |
| `react-native-svg` | `15.15.4` | `Path`/`Canvas` — only `Svg, Circle, Line, Polyline` are used (`src/components/docker-overview.tsx:13`, `app/(tabs)/monitor.tsx:6`), so this is a clean 1:1 |
| `react-native-worklets` | `0.10.0` | drop |
| `tailwindcss` | `^4.2.1` | design tokens must be re-encoded as Swift constants |
| `uniwind` | `^1.3.2` | same as above |
| `valtio` | `^2.3.1` | `@Observable` / `ObservableObject` |
| `zod` | `^4.3.6` | `Codable` covers decoding; **refinements + message text must be hand-rolled** |

### 8.3 devDependencies (3)

`@types/pako` `^2.0.4`, `@types/react` `~19.2.4`, `typescript` `~6.0.3`.

### 8.4 `overrides` (exact pins, security/compat forcing — all irrelevant to Swift)

`@expo/metro` `56.0.2`, `@xmldom/xmldom` `0.8.15`, `brace-expansion` `5.0.9`,
`browserslist` `4.28.9`, `decode-uri-component` `0.5.0`, `js-yaml` `4.3.2`,
`nanoid` `3.3.18`, `postcss` `8.5.28`, `query-string` `9.5.1`,
`@react-native/dev-middleware` → `ws` `7.5.11`,
`metro` → `.` `0.84.5` and `ws` `7.5.11`, `metro-config` `0.84.5`,
`metro-transform-worker` `0.84.5`, `react-devtools-core` → `ws` `7.5.11`,
`react-native` → `ws` `7.5.11`, `xcode` → `uuid` `11.1.1`.

These exist because `npm run verify` ends with `npm audit --audit-level=low`, which the
CI job treats as blocking.

---

## 9. CI: `.github/workflows/ios-unsigned-ipa.yml`

### 9.1 Job summary

- **Name** `Build Unsigned iOS IPA`; single job `build`.
- **Triggers** `workflow_dispatch` (manual) and `push` to `main`.
- **Concurrency** group `unsigned-ios-ipa-${{ github.ref }}`, `cancel-in-progress: true`.
- **Runner image** `macos-15`. **Permissions** `contents: read`.
- **Environment variables: none.** There is no `env:` block at workflow, job, or step
  level, and no `secrets` usage — the build is intentionally credential-free (unsigned).
  The only variables are shell locals (`XCODE_26_PATH`, `PROJECT_FILE`, `WORKSPACE`,
  `XCODEPROJ`, `SCHEME`, `APP_PATH`, `XCODEBUILD_EXIT`), all under `set -euo pipefail`.
- **Node/package manager: npm, not pnpm.** `actions/setup-node@v4` with
  `node-version: 20` and `cache: npm`, then `npm ci`. No pnpm/corepack step exists.
- Steps in order: Checkout (`actions/checkout@v4`, default depth) → Setup Node.js →
  `npm ci` → `npm run verify` (endpoint-coverage check + `tsc --noEmit` +
  `npm audit --audit-level=low`) → Select Xcode 26 → `npx expo prebuild` →
  strip code signing from `project.pbxproj` via inline Ruby → `xcodebuild clean build`
  → package IPA with `ditto` → upload IPA → upload diagnostics (`if: always()`).
- **Xcode selection** is discovery-based rather than pinned: it globs
  `/Applications/Xcode_26*.app`, sorts, takes the **last** (highest) match, and
  `sudo xcode-select -s` to it; the step **fails hard** with
  `Xcode 26 is required for native iOS Liquid Glass.` if none is found. It then logs
  `xcodebuild -version` and `xcrun --sdk iphoneos --show-sdk-version`.
- **Project generation** `npx expo prebuild --platform ios --clean --non-interactive`
  (regenerates `ios/` from scratch each run, so the pbxproj patch must run after it).
- **Unsigned build** — signing is disabled twice over: statically in `project.pbxproj`
  (`CODE_SIGN_STYLE` → `Manual`, `DEVELOPMENT_TEAM`/`PROVISIONING_PROFILE_SPECIFIER` and
  their `[sdk=iphoneos*]` variants → `""`) and again on the `xcodebuild` command line
  (`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`).
- **IPA packaging** is manual, not `-exportArchive`: the `.app` is located under
  `build/DerivedData/**/Build/Products/*-iphoneos/*.app`, copied into `artifacts/Payload/`,
  and zipped with `ditto -c -k --sequesterRsrc --keepParent Payload
  lucky-mobile-unsigned.ipa`. No archive, no export options plist, no entitlements.
- **Artifacts** (`actions/upload-artifact@v4`): `lucky-mobile-unsigned-ipa` ←
  `artifacts/lucky-mobile-unsigned.ipa` (`if-no-files-found: error`); and
  `lucky-mobile-ios-build-diagnostics` ← `artifacts/diagnostics`
  (`if-no-files-found: ignore`, `if: always()`), containing
  `xcodebuild-schemes.txt`, `xcodebuild.log`, `build-products.txt`.
- **Failure handling** the build step wraps `xcodebuild` in `set +e` / `set -e`, captures
  `${PIPESTATUS[0]}` (so the exit code is `xcodebuild`'s, not `tee`'s), dumps the build
  product tree for diagnostics, then re-exits with the saved code.

### 9.2 Verbatim YAML

```yaml
name: Build Unsigned iOS IPA

on:
  workflow_dispatch:
  push:
    branches:
      - main

concurrency:
  group: unsigned-ios-ipa-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    runs-on: macos-15
    permissions:
      contents: read

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Verify endpoint coverage, types, and dependencies
        run: npm run verify

      - name: Select Xcode 26
        run: |
          set -euo pipefail
          XCODE_26_PATH="$(find /Applications -maxdepth 1 -name 'Xcode_26*.app' -type d | sort | tail -n 1)"
          if [ -z "$XCODE_26_PATH" ]; then
            echo "Xcode 26 is required for native iOS Liquid Glass."
            exit 1
          fi
          sudo xcode-select -s "$XCODE_26_PATH"
          xcodebuild -version
          xcrun --sdk iphoneos --show-sdk-version

      - name: Generate iOS project
        run: npx expo prebuild --platform ios --clean --non-interactive

      - name: Disable iOS code signing
        run: |
          set -euo pipefail

          PROJECT_FILE="$(find ios -maxdepth 2 -name project.pbxproj -print -quit)"
          if [ -z "$PROJECT_FILE" ]; then
            echo "No Xcode project.pbxproj found under ios/."
            exit 1
          fi

          ruby - "$PROJECT_FILE" <<'RUBY'
          path = ARGV.fetch(0)
          text = File.read(path)
          text.gsub!(/CODE_SIGN_STYLE = Automatic;/, 'CODE_SIGN_STYLE = Manual;')
          text.gsub!(/DEVELOPMENT_TEAM = [A-Z0-9]+;/, 'DEVELOPMENT_TEAM = "";')
          text.gsub!(/"DEVELOPMENT_TEAM\[sdk=iphoneos\*\]" = [A-Z0-9]+;/, '"DEVELOPMENT_TEAM[sdk=iphoneos*]" = "";')
          text.gsub!(/PROVISIONING_PROFILE_SPECIFIER = .*?;/, 'PROVISIONING_PROFILE_SPECIFIER = "";')
          text.gsub!(/"PROVISIONING_PROFILE_SPECIFIER\[sdk=iphoneos\*\]" = .*?;/, '"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = "";')
          File.write(path, text)
          RUBY

      - name: Build unsigned app
        run: |
          set -euo pipefail
          mkdir -p artifacts/diagnostics

          WORKSPACE="$(find ios -maxdepth 1 -name "*.xcworkspace" -print -quit)"
          if [ -z "$WORKSPACE" ]; then
            echo "No Xcode workspace found under ios/."
            exit 1
          fi

          XCODEPROJ="$(find ios -maxdepth 1 -name "*.xcodeproj" -print -quit)"
          if [ -z "$XCODEPROJ" ]; then
            echo "No Xcode project found under ios/."
            exit 1
          fi

          SCHEME="$(basename "$XCODEPROJ" .xcodeproj)"
          if [ -z "$SCHEME" ]; then
            echo "No Xcode scheme found in $WORKSPACE."
            exit 1
          fi

          echo "Workspace: $WORKSPACE"
          echo "Scheme: $SCHEME"
          xcodebuild -list -workspace "$WORKSPACE" | tee artifacts/diagnostics/xcodebuild-schemes.txt

          set +e
          xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME" \
            -configuration Release \
            -sdk iphoneos \
            -destination generic/platform=iOS \
            -derivedDataPath build/DerivedData \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY="" \
            DEVELOPMENT_TEAM="" \
            PROVISIONING_PROFILE_SPECIFIER="" \
            clean build 2>&1 | tee artifacts/diagnostics/xcodebuild.log
          XCODEBUILD_EXIT="${PIPESTATUS[0]}"
          set -e

          find build/DerivedData -maxdepth 8 -path "*/Build/Products/*" -print > artifacts/diagnostics/build-products.txt || true
          exit "$XCODEBUILD_EXIT"

      - name: Package unsigned IPA
        run: |
          set -euo pipefail

          APP_PATH="$(find build/DerivedData -path "*/Build/Products/*-iphoneos/*.app" -type d -print -quit)"
          if [ -z "$APP_PATH" ]; then
            echo "No built .app found."
            echo "Available build products:"
            find build/DerivedData -maxdepth 8 -path "*/Build/Products/*" -print || true
            exit 1
          fi

          echo "App path: $APP_PATH"

          mkdir -p artifacts/Payload
          cp -R "$APP_PATH" artifacts/Payload/
          (
            cd artifacts
            ditto -c -k --sequesterRsrc --keepParent Payload lucky-mobile-unsigned.ipa
          )

      - name: Upload unsigned IPA
        uses: actions/upload-artifact@v4
        with:
          name: lucky-mobile-unsigned-ipa
          path: artifacts/lucky-mobile-unsigned.ipa
          if-no-files-found: error

      - name: Upload build diagnostics
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: lucky-mobile-ios-build-diagnostics
          path: artifacts/diagnostics
          if-no-files-found: ignore
```

### 9.3 What the native rewrite must change in this workflow

The `Generate iOS project` step (`npx expo prebuild`) and the `npm ci` /
`npm run verify` steps disappear once the app is native: `ios/*.xcodeproj` (or
`.xcworkspace`) becomes a checked-in artifact instead of a generated one. Everything
downstream — the pbxproj signing patch, the `xcodebuild` invocation, the
`ditto`-based Payload zip, and both uploads — carries over unchanged, since it already
operates on a plain Xcode workspace. Keep the `Xcode_26*` discovery step verbatim: it is
the guard that guarantees the Liquid Glass SDK is present. If no `.xcworkspace` is
checked in (SPM-only project), the `find ios -maxdepth 1 -name "*.xcworkspace"` guard
must be relaxed to fall back to `-project "$XCODEPROJ"`.
