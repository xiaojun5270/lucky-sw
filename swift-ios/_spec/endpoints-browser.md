# Behavioural specification — endpoint registry browser & endpoint debugger

Source of truth (React Native / TypeScript):

- `C:\Users\xiaoj\Desktop\lucky\app\modules\[module].tsx` (66 lines) — module endpoint list screen
- `C:\Users\xiaoj\Desktop\lucky\app\endpoints\[id].tsx` (320 lines) — endpoint request runner / debugger
- `C:\Users\xiaoj\Desktop\lucky\src\services\lucky-endpoints.ts` (219 lines) — registry queries + raw caller
- `C:\Users\xiaoj\Desktop\lucky\src\api\lucky-endpoints.generated.ts` (4450 lines, 89,279 bytes) — generated registry
- `C:\Users\xiaoj\Desktop\lucky\Lucky_API_Endpoints.json` (2297 lines, **51,781 bytes**, LF) — raw registry source
- `C:\Users\xiaoj\Desktop\lucky\docs\Lucky_API_Endpoints.json` (2297 lines, 54,078 bytes, CRLF) — the copy the generator actually reads
- `C:\Users\xiaoj\Desktop\lucky\src\lib\query-client.ts` (25 lines) — TanStack Query defaults

Supporting files read for exact constants, transport and component contracts:

- `C:\Users\xiaoj\Desktop\lucky\src\types\lucky.ts` — `LuckyEndpointDefinition`, `LuckyModuleDefinition`, `LuckyHttpMethod`, `LuckyEndpointCall`, `LuckyRecord`
- `C:\Users\xiaoj\Desktop\lucky\scripts\generate-endpoints.mjs` (73 lines) — the JSON → TS derivation rules and the module label map
- `C:\Users\xiaoj\Desktop\lucky\src\lib\lucky-fetch.ts` — `withLuckyRequestNonce`, `createLuckyRequestNonce`, `refreshLuckyToken`, `LuckyAuthError`
- `C:\Users\xiaoj\Desktop\lucky\src\store\lucky-session.ts` — `luckySessionState` (`baseUrl`, `account`, `password`, `token`, `hydrated`), `endLuckySession`
- `C:\Users\xiaoj\Desktop\lucky\src\components\lucky-ui.tsx` — `Page`, `Panel`, `SectionHeader`, `SearchField`, `EmptyState`, `ErrorState`
- `C:\Users\xiaoj\Desktop\lucky\src\components\structured-form.tsx` — `StructuredForm`, `StructuredDataView` (detailed in `_spec/structured-form.md`)
- `C:\Users\xiaoj\Desktop\lucky\src\lib\theme.ts` — `useAppTheme()` colour roles
- `C:\Users\xiaoj\Desktop\lucky\app\_layout.tsx` — native stack registration for both routes

## 0. Feature summary

Two screens over a **static, bundled, read-only registry of 328 Lucky HTTP endpoints grouped into 45
modules**. Screen 1 lists the endpoints of one module with a client-side text filter. Screen 2 is a
generic request builder for one endpoint: method picker, path-variable inputs, path-suffix input,
query editor (object or key/value array), JSON body editor (object or heterogeneous array),
optional multipart file upload, dangerous-request confirmation, send/cancel, and a typed response
viewer with binary download.

There is **no request history, no favourites, no saved presets and no persistence of any kind** on
either screen. All builder state is component-local and is wiped whenever the endpoint changes.

Registry totals (verified by parsing the generated file):

| Metric | Value |
| --- | --- |
| Endpoint entries | **328** |
| Distinct modules | **45** |
| Total methods (Σ `methods.length`) | **448** |
| Entries with `requiresSuffix: true` | **87** |
| Entries with non-empty `pathVariables` | **58** (all exactly `["e"]`, all in module `docker`) |
| Entries with non-empty `notes` | **0** |
| Distinct `source` values | 23 |
| Method occurrences | GET 208, POST 103, PUT 83, DELETE 54 (PATCH 0) |

---

## 1. Registry data model

### 1.1 `Lucky_API_Endpoints.json` — raw resource schema

Top level is a **flat JSON array** (no wrapper object, no metadata) of 328 objects. Every object has
exactly these five string keys, in this order, and **no key is ever absent or null**:

```json
[
  {
    "path": "/LoginPageConfig",
    "methods": "GET",
    "module": "base",
    "source": "lucky_index.js",
    "notes": ""
  }
]
```

| Key | Type | Notes |
| --- | --- | --- |
| `path` | `String` | Absolute path starting with `/`. May end with `/` (means "append a suffix"). May contain `${e}` placeholders. |
| `methods` | `String` | **Not an array.** `/`-separated HTTP verbs, optionally suffixed with `*` (e.g. `GET/PUT/DELETE*`). |
| `module` | `String` | Module key. |
| `source` | `String` | Originating Lucky web-bundle filename, e.g. `lucky_index.js`. |
| `notes` | `String` | Always `""` in the current data. |

Distinct `methods` strings and their frequencies (15 variants — the `*` marker appears on 22 rows):

`GET` 142 · `POST` 77 · `PUT` 26 · `GET/PUT/DELETE*` 21 · `GET/PUT` 17 · `DELETE` 11 ·
`DELETE/GET/POST/PUT` 7 · `DELETE/GET` 7 · `GET/POST/PUT` 6 · `GET/POST` 5 · `DELETE/POST/PUT` 5 ·
`GET/POST*` 1 · `DELETE/POST` 1 · `DELETE/GET/PUT` 1 · `DELETE/GET/POST` 1

The root copy and `docs/` copy are **semantically identical** (`json.load` equality confirmed); they
differ only in line endings (root LF, docs CRLF), which is the whole 2,297-byte size delta. The
generator script reads the `docs/` copy. Either file can be bundled as the Swift resource.

### 1.2 Generated registry — `LuckyEndpointDefinition`

```ts
export type LuckyHttpMethod = 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';

export type LuckyEndpointDefinition = {
  id: string;              // e.g. "docker-080"
  path: string;            // e.g. "/api/docker/containers/${e}"
  methods: LuckyHttpMethod[];
  module: string;          // e.g. "docker"
  source: string;
  notes: string;
  requiresSuffix: boolean;
  pathVariables: string[]; // e.g. ["e"]
};
```

### 1.3 Generated registry — `LuckyModuleDefinition`

```ts
export type LuckyModuleDefinition = {
  key: string;           // module key, matches LuckyEndpointDefinition.module
  label: string;         // Chinese display label
  endpointCount: number;
  methodCount: number;   // Σ methods.length over that module's endpoints
};
```

`LUCKY_ENDPOINTS` and `LUCKY_MODULES` are exported as `as const satisfies readonly …[]` arrays; the
JSON body is literally `JSON.stringify(value, null, 2)`, so the generated TS is machine-decodable.

### 1.4 Derivation rules (`scripts/generate-endpoints.mjs`) — must be reproduced exactly

For row index `i` (0-based) of the raw JSON array:

1. **methods** — `String(item.methods).replaceAll('*','').split('/').filter(Boolean)`.
   Order is preserved verbatim from the string; verbs are **never sorted or de-duplicated**.
   Verified: `methods[k]` in the generated file equals this expression for all 328 rows. Any verb
   outside `GET|POST|PUT|DELETE|PATCH` is a hard generation error.
2. **id** — `` `${item.module}-${String(i + 1).padStart(3, '0')}` ``. The counter is the **global
   1-based row index**, not a per-module counter, so ids run `base-001`, `baseconfigure-002`,
   `cloudflared-003`, … `base-328`. Collisions would get a `-2`, `-3` … suffix; there are **none**
   in the current data (verified: no id contains a second `-`). Ids are therefore stable only as
   long as row order is stable.
3. **pathVariables** — `[...path.matchAll(/\$\{([^}]+)\}/g)].map(m => m[1])`, i.e. every `${name}`
   capture, in order of appearance. All 58 hits are the single variable `e`.
4. **requiresSuffix** — `path.endsWith('/') || pathVariables.length > 0`.
5. **source / notes** — `item.source ?? ''`, `item.notes ?? ''`.
6. **modules** — `[...new Set(endpoints.map(e => e.module))]` (first-appearance order), mapped to
   `{ key, label: moduleLabels[key] ?? key, endpointCount, methodCount }`, then
   **`.sort((l, r) => l.label.localeCompare(r.label, 'zh-CN'))`**. This zh-CN collation puts the
   Chinese labels first (pinyin order) and the Latin-initial labels last; the resulting order is
   listed in §1.6 and is the exact order a Swift port must reproduce (hard-code the array order
   rather than relying on `String.compare(options: .caseInsensitive)` — ICU pinyin collation is
   what produced it).

### 1.5 Swift `Codable` shape

```swift
struct LuckyEndpointDefinition: Codable, Hashable, Identifiable {
    let id: String
    let path: String
    let methods: [LuckyHTTPMethod]   // String enum: GET, POST, PUT, DELETE, PATCH
    let module: String
    let source: String
    let notes: String
    let requiresSuffix: Bool
    let pathVariables: [String]
}

struct LuckyModuleDefinition: Codable, Hashable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let endpointCount: Int
    let methodCount: Int
}
```

Recommended bundling: pre-transform `Lucky_API_Endpoints.json` into a single resource
`LuckyEndpoints.json` of the shape

```json
{ "endpoints": [ …328 LuckyEndpointDefinition… ], "modules": [ …45 LuckyModuleDefinition… ] }
```

decoded once into a `static let` registry. Deriving it at runtime from the raw 5-key array is also
acceptable provided rules §1.4.1–§1.4.6 are applied verbatim, including the global row counter for
`id` and the zh-CN label sort for `modules`.

### 1.6 Module table — all 45 modules, in `LUCKY_MODULES` order

| # | `key` | `label` (verbatim) | `endpointCount` | `methodCount` |
| --- | --- | --- | --- | --- |
| 1 | `update` | 程序更新 | 2 | 2 |
| 2 | `storagemanagement` | 存储管理 | 8 | 13 |
| 3 | `login` | 登录 | 1 | 1 |
| 4 | `third` | 第三方服务 | 4 | 5 |
| 5 | `thirdPartyAuthManager` | 第三方认证 | 5 | 8 |
| 6 | `ddns` | 动态域名 DDNS | 15 | 26 |
| 7 | `portforward` | 端口转发 | 5 | 10 |
| 8 | `portforwards_lite` | 端口转发精简列表 | 1 | 1 |
| 9 | `portforwards` | 端口转发列表 | 1 | 1 |
| 10 | `webservice` | 反向代理 / Web 服务 | 18 | 28 |
| 11 | `restoreconfigureconfirm` | 恢复配置 | 1 | 1 |
| 12 | `baseconfigure` | 基础配置 | 1 | 2 |
| 13 | `base` | 基础资源 | 4 | 4 |
| 14 | `cron` | 计划任务 | 12 | 18 |
| 15 | `modules` | 模块状态 | 1 | 1 |
| 16 | `logs` | 全局日志 | 1 | 1 |
| 17 | `twofapassword` | 双因素认证 | 1 | 1 |
| 18 | `iconlib` | 图标库 | 6 | 11 |
| 19 | `logout` | 退出登录 | 1 | 1 |
| 20 | `wol` | 网络唤醒 | 11 | 14 |
| 21 | `netinterfaces` | 网络接口 | 1 | 1 |
| 22 | `info` | 系统信息 | 1 | 1 |
| 23 | `status` | 运行状态 | 1 | 1 |
| 24 | `reboot_program` | 重启程序 | 1 | 1 |
| 25 | `cloudflared` | Cloudflared | 5 | 9 |
| 26 | `coraza` | Coraza / WAF | 6 | 8 |
| 27 | `ddnstasklist` | DDNS 任务列表 | 1 | 1 |
| 28 | `dlnaservice` | DLNA 服务 | 4 | 5 |
| 29 | `docker` | Docker 管理 | 122 | 140 |
| 30 | `frp` | FRP | 5 | 9 |
| 31 | `ftpserver` | FTP 服务 | 4 | 5 |
| 32 | `ipregtest` | IP 规则测试 | 1 | 1 |
| 33 | `ipfliter` | IP 过滤 | 6 | 7 |
| 34 | `ipdb` | IP 数据库 | 9 | 14 |
| 35 | `lucky` | Lucky 服务 | 1 | 1 |
| 36 | `oauth` | OAuth | 4 | 4 |
| 37 | `rclone` | Rclone | 20 | 32 |
| 38 | `ssl` | SSL / TLS 证书 | 9 | 17 |
| 39 | `stun` | STUN | 3 | 6 |
| 40 | `stunrule` | STUN 规则 | 3 | 5 |
| 41 | `stunrulelist` | STUN 规则列表 | 1 | 1 |
| 42 | `stunrulelist_lite` | STUN 精简列表 | 1 | 1 |
| 43 | `v2l` | V2L | 1 | 1 |
| 44 | `webdav` | WebDAV | 4 | 5 |
| 45 | `webterminal` | WebTerminal | 15 | 23 |

Sums: 328 endpoints / 448 methods. Note `ipfliter` is the upstream spelling (not `ipfilter`) and
must not be "corrected". The label map in the generator is total — every one of the 45 keys has an
explicit label, so the `?? key` fallback is never hit today.

### 1.7 Path-variable endpoints (58, all `${e}`, all module `docker`)

`docker-046 … docker-053` (`/api/docker/compose/${e}/…`: `backup/cancel`, `backups`, `backups/all`,
`backups/download.tar.gz`, `backups/restore`, `backups/upload`, `logs`, `ps`),
`docker-080 … docker-115` (`/api/docker/containers/${e}` and its 35 sub-paths: `commit`,
`compose-config`, `copy`, `edit`, `export`, `files`, `files/chmod`, `files/compress`,
`files/compress-async`, `files/copy`, `files/decompress`, `files/decompress-async`,
`files/download`, `files/list`, `files/mkdir`, `files/preview-archive`, `files/read`,
`files/rename`, `files/search`, `files/touch`, `files/upload`, `files/write`, `label`, `logs`,
`pause`, `processes`, `rename`, `restart`, `start`, `stats`, `stats-cached`, `stop`, `unpause`,
`upgrade`, `upgrade-check`),
`docker-122 … docker-126` (`/api/docker/images/${e}` + `filesystem`, `history`, `tag`, `tags`),
`docker-147` (`/api/docker/labels/${e}/containers`), `docker-151`
(`/api/docker/networks/${e}`), `docker-156` (`/api/docker/tasks/${e}`),
`docker-159 … docker-164` (`/api/docker/volumes/${e}`, `backup`, `backup/cancel`, `backups`,
`backups/restore`, `backups/upload`).

The remaining 29 `requiresSuffix` endpoints (87 − 58) are trailing-slash paths such as
`/api/cloudflared/`, `/api/cloudflared/list/`.

---

## 2. `src/services/lucky-endpoints.ts`

### 2.1 Exported surface

| Export | Kind | Signature |
| --- | --- | --- |
| `LuckyEndpointResult` | type | see below |
| `getLuckyModules` | fn | `() => readonly LuckyModuleDefinition[]` |
| `getLuckyEndpoints` | fn | `(module?: string) => readonly LuckyEndpointDefinition[]` |
| `getLuckyEndpoint` | fn | `(id: string) => LuckyEndpointDefinition \| undefined` |
| `isDangerousLuckyRequest` | fn | `(endpoint, method, dynamicPath = '') => boolean` |
| `resolveLuckyEndpointPath` | fn | `(call) => string` |
| `callLuckyEndpoint` | async fn | `(call) => Promise<LuckyEndpointResult>` |

```ts
export type LuckyEndpointResult = {
  status: number;
  contentType: string;
  filename?: string;
  kind: 'json' | 'text' | 'binary' | 'empty';
  data?: unknown;
  byteLength?: number;
  blob?: Blob;
};

type LuckyEndpointQuery = LuckyRecord | unknown[];
type LuckyEndpointRunnerCall = Omit<LuckyEndpointCall, 'query'> & { query?: LuckyEndpointQuery };
// LuckyEndpointCall = { endpoint; method; pathValues?: Record<string,string>; suffix?: string;
//                       query?; body?: unknown; retryAuth?: boolean; signal?: AbortSignal }
```

Swift mapping: `enum LuckyEndpointResult { case json(Any), text(String), binary(Data), empty }` plus
`status: Int`, `contentType: String`, `filename: String?`, `byteLength: Int?`.

### 2.2 Module-level regular expressions (verbatim, both case-insensitive)

```ts
const dangerousGetActions = /\/(reboot_program|restoreconfigureconfirm|update\/comfire|manualsync|[^/]*flush[^/]*|enable|expanded|ipsectionexpanded|wakeup|shutdown|restart|start|stop|down|up|prune|remove|build|pull|push|import|export|load|dojobs|cancel|[^/]*test|[^/]*orderadjustment)(\/|$)/i;
const longRunningActions = /\/(upload|import|load|restore|export|build|pull|push|backup|download)(?:[/?]|$)/i;
```

Note `update/comfire` is the upstream typo and must be kept. `dangerousGetActions` matches a whole
path segment (delimited by `/` on the left and `/` or end-of-string on the right) — it therefore
does **not** fire on a query string, whereas `longRunningActions` also accepts `?` as the right
delimiter and so still fires after the query has been appended.

### 2.3 Registry lookups

```ts
export function getLuckyModules() { return LUCKY_MODULES; }

export function getLuckyEndpoints(module?: string) {
  return module ? LUCKY_ENDPOINTS.filter((e) => e.module === module) : LUCKY_ENDPOINTS;
}

export function getLuckyEndpoint(id: string) {
  return LUCKY_ENDPOINTS.find((e) => e.id === id);
}
```

- `module` matching is **exact and case-sensitive**; no trimming, no normalisation.
- A falsy `module` (`undefined` **or the empty string**) returns **all 328** endpoints, not none.
- Filter/find preserve registry order. There is no sorting anywhere in the service or either screen:
  the display order is always the raw JSON row order.

### 2.4 `isDangerousLuckyRequest(endpoint, method, dynamicPath = '')`

```ts
if (method !== 'GET') return true;
const candidate = dynamicPath.trim()
  ? `${endpoint.path.replace(/\/+$/, '')}/${dynamicPath.replace(/^\/+/, '')}`
  : endpoint.path;
return dangerousGetActions.test(candidate);
```

- **Every non-GET method is dangerous**, unconditionally (POST/PUT/DELETE/PATCH).
- For GET, the check runs against the endpoint's registry path with the caller-supplied dynamic tail
  glued on: trailing slashes stripped from the left side, leading slashes stripped from the right
  side, exactly one `/` inserted. Note `dynamicPath` is `.trim()`-tested but appended **untrimmed**.
- `${e}` placeholders are *not* substituted here, so the candidate can still contain `${e}`; that is
  harmless because the regex only looks for known action segments.

### 2.5 Query serialisation

```ts
function appendQueryValue(params: string[], key: string, value: unknown) {
  if (!key || value === undefined || value === null || value === '') return;
  if (Array.isArray(value)) { value.forEach((item) => appendQueryValue(params, key, item)); return; }
  const encodedValue = encodeURIComponent(typeof value === 'object' ? JSON.stringify(value) : String(value));
  params.push(`${encodeURIComponent(key)}=${encodedValue}`);
}
```

Rules: empty key → dropped. `undefined`, `null`, `''` → dropped (but `0` and `false` are **kept**,
serialising as `0` / `false`). Array → the key is repeated once per element (recursively, so nested
arrays flatten under the same key). Non-null object → `JSON.stringify` then percent-encode. Anything
else → `String(value)` then percent-encode. Both key and value are percent-encoded with
`encodeURIComponent` semantics (space → `%20`, and `!'()*-._~` left unescaped).

```ts
function appendQuery(path: string, query?: LuckyEndpointQuery) {
  if (!query || Object.keys(query).length === 0) return path;
  const params: string[] = [];
  if (Array.isArray(query)) {
    query.forEach((item) => {
      if (item && typeof item === 'object' && !Array.isArray(item)) {
        const entry = item as LuckyRecord;
        const key = String(entry.key ?? entry.Key ?? entry.name ?? entry.Name ?? '').trim();
        const value = entry.value ?? entry.Value;
        appendQueryValue(params, key, value);
      } else appendQueryValue(params, 'value', item);
    });
  } else Object.entries(query).forEach(([key, value]) => appendQueryValue(params, key, value));
  const text = params.join('&');
  return text ? `${path}${path.includes('?') ? '&' : '?'}${text}` : path;
}
```

- Object mode: iterate `Object.entries` in **insertion order**; keys are used verbatim (untrimmed).
- Array mode: each element that is a plain object supplies its key from the first present of
  `key`, `Key`, `name`, `Name` (`??` chain — so `null`/`undefined` fall through but `''` does not),
  `.trim()`-ed; its value from `value ?? Value`. Non-object elements (and nested arrays) are emitted
  under the literal key `value`.
- Separator: `?` unless `path` already contains `?`, then `&`. Pairs joined with `&`.
- If every pair was dropped, the path is returned unchanged (no dangling `?`).

### 2.6 `encodePathSuffix(value)`

```ts
const parts = value.trim().split('/').filter(Boolean);
if (!parts.length) throw new Error('请填写资源 Key / 路径后缀');
if (parts.some((part) => part === '.' || part === '..')) throw new Error('路径后缀不能包含 . 或 ..');
return parts.map((part) => encodeURIComponent(part)).join('/');
```

Trim → split on `/` → drop empty segments (so leading/trailing/duplicate slashes collapse) → reject
`.` and `..` segments → percent-encode each segment → rejoin with single `/`. Note the encoding is
per-segment, so an inner `/` typed by the user survives as a real path separator while spaces and
non-ASCII become `%xx`.

### 2.7 `resolveLuckyEndpointPath(call)` — the URL-building algorithm

```ts
let path = call.endpoint.path;
call.endpoint.pathVariables.forEach((variable) => {
  const value = call.pathValues?.[variable] ?? call.suffix;
  if (!value?.trim()) throw new Error(`请填写路径参数 ${variable}`);
  path = path.replaceAll(`\${${variable}}`, encodeURIComponent(value.trim()));
});
if (path.endsWith('/') && call.suffix?.trim()) path += encodePathSuffix(call.suffix);
return appendQuery(path, call.query);
```

Step by step:

1. Start from the **registry path** verbatim.
2. For each declared path variable, in declaration order:
   - value = `pathValues[variable]` if that key is present and not `null`/`undefined`, otherwise
     fall back to `call.suffix`. **An empty-string `pathValues` entry does not fall back** (`??` is
     nullish, not falsy) — it goes straight to the guard and throws.
   - if the chosen value is missing or whitespace-only → throw `` `请填写路径参数 ${variable}` ``.
   - replace **every** literal occurrence of `${variable}` with `encodeURIComponent(value.trim())`
     (`replaceAll`, so a path with the same variable twice gets both filled).
3. If the (already substituted) path ends with `/` **and** `suffix` is non-blank, append
   `encodePathSuffix(suffix)`. A path that does not end in `/` ignores `suffix` entirely at this
   step. A `requiresSuffix` trailing-slash path with a blank suffix silently produces the bare
   trailing-slash URL (the screen's own validation is what prevents that).
4. Append the query string per §2.5.
5. The **cache-buster nonce is *not* added here** — `callLuckyEndpoint` adds it at fetch time via
   `withLuckyRequestNonce(path)`.

`withLuckyRequestNonce` / `createLuckyRequestNonce` (from `src/lib/lucky-fetch.ts`):

```ts
const timestamp = String(now).slice(0, -1);                                  // ms epoch minus last digit
const checksum  = [...timestamp].reduce((s, d) => s + Number(d), 0) % 8;     // digit sum mod 8
nonce = `${timestamp}${checksum}`;
path + (path.includes('?') ? '&' : '?') + `_=${nonce}`;
```

Final absolute URL: `` `${baseUrl}${withLuckyRequestNonce(resolveLuckyEndpointPath(call))}` `` where
`baseUrl = luckySessionState.baseUrl.trim().replace(/\/+$/, '')`.

Worked example — `docker-104` `/api/docker/containers/${e}/logs`, method GET,
`pathValues = { e: 'my app' }`, `suffix = ''`, `query = { tail: 100, follow: false, skip: '' }`:

`/api/docker/containers/my%20app/logs?tail=100&follow=false&_=17572584321`

(`skip: ''` dropped; `follow: false` kept; nonce appended last with `&`.)

### 2.8 Private helpers

```ts
function getFilename(header: string | null) {          // from Content-Disposition
  if (!header) return undefined;
  const utf8 = header.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
  if (utf8) { try { return decodeURIComponent(utf8); } catch { return utf8; } }
  return header.match(/filename="?([^";]+)"?/i)?.[1];   // NOT percent-decoded
}

function getBody(body: unknown) {                       // request body encoder
  if (body === undefined || body === null) return undefined;
  if (typeof body === 'string' || body instanceof FormData || body instanceof Blob) return body;
  return JSON.stringify(body);
}

function numericRet(value: unknown) {                   // envelope ret coercion
  if (typeof value === 'number') return value;           // no isFinite check here
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;                                      // absent / unparseable
}
```

### 2.9 `callLuckyEndpoint(call)` — execution flow

1. `if (!call.endpoint.methods.includes(call.method)) throw new Error('该端点不支持所选请求方法')`.
2. `baseUrl = luckySessionState.baseUrl.trim().replace(/\/+$/, '')`; if empty →
   `throw new Error('请输入 Lucky 服务地址')`.
3. `path = resolveLuckyEndpointPath(call)` (may itself throw the §2.6/§2.7 messages).
4. Create an internal `AbortController`; if `call.signal` is already aborted, abort immediately,
   otherwise attach a one-shot `abort` listener that aborts the internal controller.
5. **Timeout**: `setTimeout(abort, longRunningActions.test(path) ? 600_000 : 20_000)` — 600 s for
   upload/import/load/restore/export/build/pull/push/backup/download paths, else 20 s.
6. Headers: `Accept: application/json, text/plain, */*`; plus
   `Lucky-Admin-Token: <luckySessionState.token>` when a token exists.
7. `requestBody = ['GET','HEAD'].includes(method) ? undefined : getBody(call.body)`.
   If `requestBody` exists and is neither `FormData` nor `Blob`, set
   `Content-Type: application/json` (multipart/blob bodies get no explicit Content-Type so the
   runtime can supply the boundary).
8. `fetch(baseUrl + withLuckyRequestNonce(path), { method, headers, body, signal })`.
9. Read `contentType = response.headers['content-type'] ?? ''`,
   `filename = getFilename(response.headers['content-disposition'])`,
   `likelyBinaryPath = /\/(?:download|export|backup|file|[^/]*\.tar\.gz)(?:[/?]|$)/i.test(path)`.
10. **HTTP 401**: drain the body (`await response.arrayBuffer()`, errors swallowed); if
    `call.retryAuth !== false`, `await refreshLuckyToken()` then **recurse** with
    `{ ...call, retryAuth: false }`; if the refresh throws, `await endLuckySession()` and rethrow
    when it is a `LuckyAuthError`; finally `throw new LuckyAuthError()` (message
    `登录已失效，请重新登录`).
11. **HTTP 204 or `content-length: 0`**: if `!response.ok` →
    `` throw new Error(`请求失败（HTTP ${status}）`) ``; else return `kind: 'empty'`.
12. **JSON branch** — taken when `contentType` includes `application/json` or `+json`, **or** when
    there is no content type *and* no filename *and* the path is not `likelyBinaryPath`:
    - read text, `JSON.parse`; a parsed plain object becomes `data`, anything else is wrapped as
      `{ data: parsed }`.
    - on parse failure: if `!response.ok` → `throw new Error(raw || 请求失败（HTTP …）)`; else return
      `kind: 'text'` with the raw string when non-blank, otherwise `kind: 'empty'`.
    - `ret = numericRet(data.ret)`. **`ret === -1`** → same refresh/recurse/`endLuckySession` dance
      as step 10, ending in `throw new LuckyAuthError(data.msg)` when `msg` is a string.
    - `if (!response.ok || (ret !== undefined && ret !== 0))` → throw `data.msg` if it is a string,
      else `` `请求失败（HTTP ${status}）` ``. A **missing** `ret` on a 2xx is treated as success.
    - otherwise return `kind: 'json'`, `data` = the whole envelope (including `ret`/`msg`).
13. **Text branch** — `contentType.startsWith('text/')` or it includes `xml` or `yaml`: read text;
    `!ok` → throw `text || 请求失败（HTTP …）`; else `kind: 'text'`.
14. **Blob branch** (everything else): read blob; `!ok` → error detail = `blob.text().trim()` when
    `blob.size <= 65536` else `''`, throw `detail || 请求失败（HTTP …）`; `blob.size === 0` →
    `kind: 'empty'`; else `kind: 'binary'` with `byteLength = blob.size` and the `blob`.
15. **catch**: an `AbortError` becomes `请求已取消` when the *external* signal is aborted, otherwise
    `请求超时，请检查服务器连接`. (There is no `timedOut` flag — an internal timeout is reported as a
    timeout precisely because the external signal is untouched.) Other errors propagate as-is.
16. **finally**: clear the timeout and detach the external abort listener.

### 2.10 Error message inventory (service layer, verbatim)

| Message | Raised when |
| --- | --- |
| `该端点不支持所选请求方法` | method not in `endpoint.methods` |
| `请输入 Lucky 服务地址` | blank `luckySessionState.baseUrl` |
| `请填写路径参数 {variable}` | blank value for a `${variable}` |
| `请填写资源 Key / 路径后缀` | `encodePathSuffix` got no usable segment |
| `路径后缀不能包含 . 或 ..` | suffix contains a `.` or `..` segment |
| `请求失败（HTTP {status}）` | non-2xx with no usable body/`msg` (note full-width parentheses) |
| `登录已失效，请重新登录` | `LuckyAuthError` default (401 / `ret === -1` after failed refresh) |
| `请求已取消` | external abort |
| `请求超时，请检查服务器连接` | internal 20 s / 600 s timeout |

---

## 3. `src/lib/query-client.ts` — QueryClient defaults

```ts
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 30_000,          // 30 s
      gcTime: 2 * 60_000,         // 120 s
      refetchOnWindowFocus: false,
      refetchOnReconnect: true,
    },
  },
});
```

There is **no `mutations` default block**, so mutations use library defaults (`retry: 0`).
Non-specified query defaults also stay at library defaults (`refetchOnMount: true`,
`retryDelay` exponential `min(1000 * 2 ** n, 30000)`, `networkMode: 'online'`).

Focus wiring, executed at module load on non-web platforms only:

```ts
if (Platform.OS !== 'web') {
  focusManager.setFocused(AppState.currentState === 'active');
  focusManager.setEventListener((setFocused) => {
    const sub = AppState.addEventListener('change', (state) => setFocused(state === 'active'));
    return () => sub.remove();
  });
}
```

Swift equivalent for the two screens specifically: because `refetchOnWindowFocus` is `false` and the
endpoint debugger uses a **mutation** (not a query), no automatic refetch/retry behaviour applies to
either screen — the send button is the only trigger, and a failed send is **not** retried. The
30 s/120 s cache values are only relevant to other screens that use `useQuery`.

---

## 4. `app/modules/[module].tsx` — module endpoint list

Route: `/modules/:module`. Registered in `app/_layout.tsx` as
`<Stack.Screen name="modules/[module]" options={{ title: '模块接口', headerBackTitle: '返回' }} />`
— so the native navigation bar reads **模块接口** while the in-page header shows the module label.
**No screen in the app navigates here**; it is reachable only by deep link / URL. A Swift port should
add an entry point (e.g. a module index) or keep it deep-link-only, but must not change the two
strings above.

### 4.1 Param decoding

```ts
function routeParam(value: string | string[] | undefined) {
  const raw = Array.isArray(value) ? value[0] ?? '' : value ?? '';
  try { return decodeURIComponent(raw); } catch { return raw; }
}
```

Array param → first element; missing → `''`; `decodeURIComponent` with raw-string fallback on
malformed escapes.

### 4.2 Data derivation

```ts
const module = useMemo(() => getLuckyModules().find((m) => m.key === moduleKey), [moduleKey]);
const [search, setSearch] = useState('');
const endpoints = useMemo(() => {
  const keyword = search.trim().toLowerCase();
  return getLuckyEndpoints(moduleKey).filter((e) =>
    !keyword || `${e.path} ${e.id} ${e.source}`.toLowerCase().includes(keyword));
}, [moduleKey, search]);
```

- Search is **immediate (no debounce)**, case-insensitive, substring, over the single string
  `"<path> <id> <source>"` joined by single spaces — so a query may span fields (e.g. `logs docker`
  will *not* match, but `containers docker-0` can, since the space is part of the haystack).
  `module` and `notes` are **not** searched.
- Blank/whitespace-only search shows everything.
- Order is registry order; no sorting or grouping.

### 4.3 Not-found state

```tsx
if (!module) return <Page title="模块不存在" icon={Braces}>
  <EmptyState message="接口清单中没有找到该模块" icon={Braces} />
</Page>;
```

### 4.4 Layout

`Page` props: `title = module.label`, `subtitle = ` `` `${module.endpointCount} 个端点 · ${module.methodCount} 个方法` ``,
`icon = Braces`, `scrollable = false` (so the `FlatList` owns the scrolling). `Page` wraps content in
a `SafeAreaView` (`edges: ['top']`, background `colors.page`) and a centred column
`maxWidth 820, paddingHorizontal 16, paddingTop 14, paddingBottom 12, gap 16, flex 1`.
`PageHeader` renders a 44 pt `IconTile` (icon 22 pt), title 26/32 weight 800, subtitle 13/18 subtext.

Children, in order:

1. `SearchField` — `placeholder="搜索路径或接口"`; height 46, radius 14, border 1 `border`, bg `card`,
   paddingHorizontal 12, gap 9, leading `Search` icon 17 (`subtext`, strokeWidth 2.1), `TextInput`
   flex 1, fontSize 15, paddingVertical 10, `autoCapitalize="none"`, `autoCorrect={false}`.
2. `SectionHeader` — `icon={Search}`, `title="接口列表"`, `meta={`${endpoints.length} 项`}`;
   minHeight 32, gap 9, 32 pt `IconTile` (icon 16), title 16/21 weight 700, meta pill
   paddingH 9 / paddingV 5, radius 10, bg `mutedCard`, text 11 weight 600 `subtext`.
3. `FlatList` — `keyExtractor: item.id`, `keyboardShouldPersistTaps="handled"`,
   `removeClippedSubviews` only on Android, `initialNumToRender 12`, `maxToRenderPerBatch 12`,
   `windowSize 9`, `style { flex: 1, width: '100%' }`,
   `contentContainerStyle { gap: 10, paddingBottom: 96, flexGrow: endpoints.length ? 0 : 1 }`,
   `ListEmptyComponent = <EmptyState message="没有匹配的接口" icon={Search} />`.

### 4.5 `EndpointRow`

Container `Pressable`: `minHeight 82, borderRadius 14, borderWidth 1, borderColor: border,
backgroundColor: card, padding 13, gap 8, opacity: pressed ? 0.65 : 1`. No shadow.

1. **Top row** (`flexDirection row, alignItems center, gap 8`):
   - method chips container `flexDirection row, flexWrap wrap, gap 5, flex 1`; one chip per method in
     `endpoint.methods` order — `paddingHorizontal 7, paddingVertical 3, borderRadius 7,
     backgroundColor: `${methodColor}22`` (the method colour at **0x22 = 13.3 % alpha**), label
     `fontSize 10, fontWeight '800'`, colour = `methodColor`.
   - `ChevronRight` 16 pt in `colors.disabled`.
2. **Path** — `Text numberOfLines={2} selectable`, `fontFamily 'monospace'`, `fontSize 12`,
   `lineHeight 17`, colour `text`. Rendered raw, so `${e}` placeholders are visible.
3. **Footer** — `Text numberOfLines={1}`, `fontSize 10`, colour `subtext`, content
   `` `${endpoint.source || 'Lucky API'}${endpoint.requiresSuffix ? ' · 需要路径参数' : ''}` ``.
   (`'Lucky API'` is the fallback when `source` is empty — never hit by current data.)

Method colour map:

```ts
function methodColor(method: string, colors) {
  if (method === 'GET') return colors.success;   // #248a3d light / #30d158 dark
  if (method === 'POST') return colors.primary;  // #007aff / #0a84ff
  if (method === 'PUT') return colors.warning;   // #c93400 / #ff9f0a
  return colors.danger;                          // #ff3b30 / #ff453a  (DELETE, PATCH, anything else)
}
```

Tap action: `router.push(`/endpoints/${encodeURIComponent(item.id)}`)` — the id is percent-encoded on
the way out and `decodeURIComponent`-ed on the way in.

---

## 5. `app/endpoints/[id].tsx` — endpoint debugger

Route `/endpoints/:id`, registered as
`<Stack.Screen name="endpoints/[id]" options={{ title: '接口调试', headerBackTitle: '返回' }} />`.
`Page` is also titled **接口调试**, with `subtitle = ` `` `${endpoint.module} · ${endpoint.id}` `` —
note this is the **raw module key**, not the Chinese label (e.g. `docker · docker-104`) —
`icon = Braces`, `safeTop = false`, `scrollable = false`.

Not found: `<Page title="接口不存在" icon={Braces}><EmptyState message="无法在接口清单中找到该端点" icon={Braces} /></Page>`.

### 5.1 Local state

| State | Type | Initial |
| --- | --- | --- |
| `method` | `LuckyHttpMethod` | `'GET'` (then `endpoint.methods[0]` via effect) |
| `pathValues` | `Record<string, string>` | `{}` → `{ [each pathVariable]: '' }` |
| `suffix` | `string` | `''` |
| `queryMode` | `'object' \| 'array'` | `'object'` |
| `queryObject` | `LuckyRecord` | `{}` |
| `queryArray` | `LuckyRecord[]` | `[]` |
| `bodyMode` | `'object' \| 'array'` | `'object'` |
| `bodyObject` | `LuckyRecord` | `{}` |
| `bodyArray` | `unknown[]` | `[]` |
| `sendBody` | `boolean` | `true` |
| `selectedFile` | `DocumentPickerAsset \| undefined` | `undefined` |
| `fileField` | `string` | `'file'` |
| `saving` | `boolean` | `false` |
| `inputError` | `string` | `''` |
| `requestControllerRef` | `AbortController \| undefined` (ref) | `undefined` |

### 5.2 Effects

1. `[endpoint]` — full reset: `method = endpoint.methods[0]`,
   `pathValues = Object.fromEntries(pathVariables.map(n => [n, '']))`, `suffix ''`,
   `queryMode 'object'`, `queryObject {}`, `queryArray []`, `bodyMode 'object'`, `bodyObject {}`,
   `bodyArray []`, `sendBody true`, `selectedFile undefined`, `fileField 'file'`, `inputError ''`.
   Guarded by `if (!endpoint) return`.
2. unmount — `requestControllerRef.current?.abort()`.
3. `[endpoint, method]` — abort the in-flight request and `mutation.reset()` (clears any previous
   response/error whenever the verb changes).

### 5.3 Derived flags

```ts
const fileCapable = Boolean(endpoint && method !== 'GET'
  && /\/(?:upload|import|load|restore|build-from-zip)(?:[/?]|$)/i.test(endpoint.path));

const dangerous = isDangerousLuckyRequest(endpoint, method,
  [suffix, ...Object.values(pathValues)].filter(Boolean).join('/'));
```

`fileCapable` is tested against the **registry** path (placeholders unsubstituted). The dynamic tail
handed to `isDangerousLuckyRequest` is `suffix` first, then the `pathValues` values in insertion
order (= `pathVariables` order), blanks removed, joined with `/`.

### 5.4 The mutation (`useMutation`, no key, no retry)

```ts
mutationFn: async () => {
  if (!endpoint) throw new Error('接口不存在');
  const controller = new AbortController();
  requestControllerRef.current = controller;
  try {
    const values = { ...pathValues };
    if (endpoint.pathVariables.length === 0 && suffix.trim()) values.e = suffix.trim();
    const query     = queryMode === 'array' ? queryArray : queryObject;
    const formValue = bodyMode  === 'array' ? bodyArray  : bodyObject;
    const body = method === 'GET' ? undefined
      : fileCapable && selectedFile
        ? multipartBody(selectedFile, fileField.trim() || 'file', sendBody ? formValue : {})
        : sendBody ? formValue : undefined;
    return await callLuckyEndpoint({ endpoint, method, pathValues: values,
      suffix: suffix.trim(), query, body, signal: controller.signal });
  } finally {
    if (requestControllerRef.current === controller) requestControllerRef.current = undefined;
  }
}
```

Body selection matrix:

| method | fileCapable && file picked | `sendBody` | body sent |
| --- | --- | --- | --- |
| GET | – | – | none (and `callLuckyEndpoint` would drop it anyway) |
| non-GET | yes | on | `multipart/form-data`: file + flattened form fields |
| non-GET | yes | off | `multipart/form-data`: file only |
| non-GET | no | on | JSON (`queryObject`-style record, or the raw array) |
| non-GET | no | off | none |

Notable quirk: `values.e = suffix.trim()` is set when the endpoint declares **no** path variables, so
it has no effect on URL building (there is nothing to substitute) — it is dead weight that a Swift
port may omit without behavioural change.

### 5.5 Multipart construction

```ts
function appendMultipartValue(data: FormData, key: string, value: unknown) {
  if (!key || value === undefined || value === null || value === '') return;
  if (Array.isArray(value) || isRecord(value)) data.append(key, JSON.stringify(value));
  else data.append(key, String(value));
}

function multipartBody(asset, field, value) {
  if (typeof FormData === 'undefined') throw new Error('当前运行环境不支持文件上传');
  const data = new FormData();
  if (asset.file) data.append(field, asset.file, asset.name);            // web
  else data.append(field, { uri: asset.uri, name: asset.name,
                            type: asset.mimeType || 'application/octet-stream' });  // native
  if (Array.isArray(value)) data.append('payload', JSON.stringify(value));
  else Object.entries(value).forEach(([key, item]) => {
    if (key !== field) appendMultipartValue(data, key, item);
  });
  return data;
}
```

- Field name = `fileField.trim() || 'file'`.
- Array body mode → the whole array goes into a single part named **`payload`** as JSON text.
- Object body mode → one part per top-level key, **skipping the key that collides with the file
  field**; nested objects/arrays are JSON-stringified; empty-string/null/undefined values dropped.
- Native MIME fallback `application/octet-stream`.

### 5.6 Actions

`run()`:

1. `setInputError('')`.
2. `missing = pathVariables.filter(n => !String(pathValues[n] ?? '').trim())`.
3. If `missing.length` **or** (`pathVariables.length === 0 && requiresSuffix && !suffix.trim()`):
   `` setInputError(`请填写路径参数 ${missing.join(', ') || '资源 Key / 路径后缀'}`) `` and return.
   (So the suffix-only case renders exactly `请填写路径参数 资源 Key / 路径后缀`.)
4. `execute = () => { mutation.reset(); mutation.mutate(); }`.
5. If `dangerous`, show a confirm alert instead of executing:
   - title `确认执行高风险接口`
   - message `` `${method} ${endpoint.path}\n\n该请求可能修改或删除系统、网络、证书或容器数据。` ``
   - buttons `[{ text: '取消', style: 'cancel' }, { text: '确认执行', style: 'destructive', onPress: execute }]`
6. Otherwise `execute()` directly.

`cancelRequest()`: abort the controller, clear the ref, `mutation.reset()`, `setInputError('')`.

`chooseFile()`: `setInputError('')` then
`DocumentPicker.getDocumentAsync({ type: '*/*', copyToCacheDirectory: true, multiple: false, base64: false })`;
on `!selection.canceled` → `setSelectedFile(selection.assets[0])`; on throw →
`setInputError(error.message ?? '无法读取所选文件')`.

`saveBinary()`: no-op unless `mutation.data?.kind === 'binary'`; sets `saving`, calls
`saveBinaryResult`, then `Alert.alert(Platform.OS === 'web' ? '下载已开始' : '保存成功', location)`;
on failure `Alert.alert('保存失败', error.message ?? '无法保存文件')`; always clears `saving`.

`saveBinaryResult(result)`:

- `if (!result.blob) throw new Error('响应中没有可保存的文件')`.
- `safeFilename(v)` = `(v?.trim() || 'lucky-download.bin').replace(/[<>:"/\\|?*\u0000-\u001f]/g, '_')` — replaces `<`, `>`, `:`, `"`, `/`, `\`, `|`,
  `?`, `*` and every C0 control character (U+0000–U+001F) with `_`.
- **web**: `URL.createObjectURL` → hidden `<a download>` click → `revokeObjectURL` after 1000 ms;
  returns the filename.
- **Android**: `await Directory.pickDirectoryAsync()`; **iOS/other**: `new Directory(Paths.document)`.
- `availableFile(dir, name)`: use `name` if free, else `` `${base} (${i})${ext}` `` for `i = 1…999`
  (extension split at the **last** `.`, only when its index `> 0`), else
  `` `${base}-${Date.now()}${ext}` ``.
- Write: `file.create({ overwrite: false, intermediates: true })`, then stream
  `blob.stream() → file.writableStream()` chunk by chunk when both exist (aborting the writer and
  rethrowing on error), else `file.write(new Uint8Array(await blob.arrayBuffer()))`. On any failure a
  freshly created file is deleted before rethrowing. Returns `file.uri`.

Swift port notes: use `UIDocumentPickerViewController` / `.fileImporter` for input,
`.fileExporter` or a share sheet for output; keep the `(1)`, `(2)`… de-duplication and the
`<>:"/\|?*` + C0-control sanitisation, and keep `lucky-download.bin` as the fallback name.

### 5.7 Screen layout — control list in render order

Root: `Page` (see §5) → `ScrollView keyboardShouldPersistTaps="handled"`,
`contentContainerStyle { gap: 14, paddingBottom: 100 }`.

Shared `inputStyle` for this screen:
`{ color: text, backgroundColor: mutedCard, borderRadius: 12, borderWidth: 1, borderColor: border,
paddingHorizontal: 12, paddingVertical: 11, fontFamily: 'monospace', fontSize: 12 }`.
`Panel` = `bg card, border 1 border, radius 18, padding 16, gap 12` + iOS/web shadow
(`#000`, opacity 0.055, radius 12, offset 0/4; Android `elevation: 2`).

| # | Control | Details |
| --- | --- | --- |
| 1 | **Path panel** | `Panel` → row (`alignItems flex-start, gap 9`): `Route` icon 18 `primary` + `Text selectable` monospace 13/20 with `endpoint.path`; then `Text` 11 `subtext`: `` `来源：${endpoint.source || '开发文档'}` `` |
| 2 | **Section header** | `SectionHeader icon={SlidersHorizontal} title="请求配置"` (no meta) |
| 3 | **Method picker** | row, `flexWrap wrap, gap 8`; one `Pressable` per `endpoint.methods` entry: `paddingHorizontal 14, paddingVertical 9, borderRadius 10`, bg `primary` when selected else `card`, border 1 (`primary` when selected else `border`), label `fontWeight '800', fontSize 12`, colour `#fff` when selected else `text`. Press → abort in-flight request, `setMethod(item)`, `mutation.reset()` |
| 4 | **Danger banner** | only when `dangerous`: row `gap 9, padding 12, borderRadius 12, backgroundColor dangerBg`, `AlertTriangle` 18 `danger`, text `danger` 12/18: `高风险请求，执行前会再次确认。` |
| 5 | **Path-variable inputs** | one block per `pathVariables` entry (`gap 7`): label `` `路径参数 ${name}` `` (`text`, weight 700, 13) + `TextInput` (`inputStyle`, `placeholder="输入 ID、Key 或资源名称"`, `placeholderTextColor placeholder`, `autoCapitalize="none"`, `autoCorrect={false}`) |
| 6 | **Suffix input** | only when `pathVariables.length === 0 && requiresSuffix`: label `资源 Key / 路径后缀` + `TextInput` `placeholder="输入资源名称或路径后缀"`, same style/flags |
| 7 | **Query panel** | `Panel`: label `查询参数` (weight 700, 13) + `RootModePicker` + (`array` → `QueryArrayForm`, `object` → `StructuredForm value={queryObject}`) |
| 8 | **Body panel** | only when `method !== 'GET'`: `Panel` → switch row (`minHeight 38, gap 10`): label `发送请求体` (flex 1, weight 700, 13) + `Switch accessibilityLabel="发送请求体"` `trackColor {false: disabled, true: primary}`; when on → `RootModePicker` + (`array` → `RootArrayForm`, `object` → `StructuredForm value={bodyObject}`) |
| 9 | **Upload panel** | only when `fileCapable`: `Panel` → row (`gap 8`): `FileUp` 17 `primary` + label `上传文件` (flex 1, weight 700, 13) + (when a file is picked) remove button `accessibilityLabel="移除文件"`, 32×32, radius 9, bg `dangerBg`, `X` 15 `danger`; then `TextInput` `placeholder="Multipart 字段名"` (`inputStyle`, no autocapitalise/autocorrect); then picker `Pressable` `minHeight 44, radius 11, border 1` (`success` when a file is picked else `border`), bg `mutedCard`, `paddingHorizontal 11, gap 8`, `FileUp` 16 (`success` if picked else `primary`), label `numberOfLines 1` 12: `` `${name}${size ? ` · ${size} bytes` : ''}` `` else `选择文件` |
| 10 | **Errors** | `inputError` → `ErrorState message={inputError}`; then `mutation.error` → `ErrorState message={mutation.error.message}`. Both can show at once. `ErrorState` = padding 14, radius 18, border+bg `dangerBg`, 34 pt `TriangleAlert` tile on `card`, message `danger` lineHeight 19 (no retry button here) |
| 11 | **Send / cancel** | `Pressable minHeight 48, borderRadius 13`, bg `danger` when `mutation.isPending \|\| dangerous` else `primary`, centred row `gap 8`; icon `X` 17 `#fff` while pending else `Send` 17 `#fff`; label `#fff` weight 800: `取消请求` while pending else `` `执行 ${method}` ``. Press → `cancelRequest()` while pending, else `run()` |
| 12 | **Response** | only when `mutation.data`: `SectionHeader icon={CheckCircle2} title="响应" meta={`HTTP ${status}`}` + `Panel` (see §5.9) |

### 5.8 Sub-forms defined in this file

**`RootModePicker({ value, onChange })`** — segmented control:
container `flexDirection row, gap 6, padding 4, borderRadius 12, backgroundColor mutedCard`;
options exactly `[['object', '对象', Braces], ['array', '数组', List]]`; each segment
`flex 1, minHeight 38, borderRadius 9`, bg `card` when selected else `transparent`, centred row with
`gap 6`, icon 15 (`primary` selected / `subtext` otherwise), label `fontSize 12, fontWeight '800'`
same colour rule.

**`QueryArrayForm({ value: LuckyRecord[], onChange })`** — key/value rows, `gap 9`:

- Row `flexDirection row, alignItems center, gap 7`.
- Key `TextInput` `flex 0.9`, displayed value `String(entry.key ?? entry.Key ?? '')`,
  `placeholder="参数名"`; edit writes lowercase **`key`** (`{ ...item, key: text }`).
- Value `TextInput` `flex 1.1`, displayed value `String(entry.value ?? entry.Value ?? '')`,
  `placeholder="参数值"`; edit writes lowercase **`value`**.
- Shared input style: `minHeight 42, borderRadius 10, borderWidth 1, borderColor border,
  backgroundColor card, color text, paddingHorizontal 10, fontSize 12`, `autoCapitalize="none"`,
  `placeholderTextColor placeholder`.
- Delete button `accessibilityLabel="删除查询参数"`, 38×38, radius 10, bg `dangerBg`,
  `Trash2` 15 `danger`.
- Add button: `minHeight 40, borderRadius 11, borderWidth 1, borderColor border`, centred row
  `gap 6`, `Plus` 15 `primary`, label `添加查询参数` (`primary`, 12, weight 800); appends
  `{ key: '', value: '' }`.
- Rows are keyed by array index, so reordering is not supported (there is no reorder UI).

**`RootArrayForm({ value: unknown[], onChange })`** — heterogeneous JSON array editor, `gap 10`:

- Each item sits in a card row: `flexDirection row, alignItems flex-start, gap 8, padding 10,
  borderRadius 12, borderWidth 1, borderColor border`; content chosen by runtime type:
  - **array** → label `嵌套数组` (`subtext`, 11) + recursive `RootArrayForm`
  - **record** → `StructuredForm`
  - **boolean** → row `minHeight 42`: label `` `第 ${index + 1} 项` `` (flex 1, `text`, 12) +
    `Switch` `trackColor {false: disabled, true: primary}`
  - **number** → `NumberArrayInput` with `placeholder = ` `` `第 ${index + 1} 项` ``
  - **anything else** → `TextInput value={String(entry ?? '')}`, `keyboardType="default"`,
    `placeholder = ` `` `第 ${index + 1} 项` ``
- Delete button `accessibilityLabel="删除数组项"`, 36×36, radius 10, bg `dangerBg`, `Trash2` 15.
- Add row: `flexWrap wrap, gap 7`, five buttons from
  `[['文本',''], ['数字',0], ['开关',false], ['对象',{}], ['数组',[]]]`, each labelled
  `` `${label}项` `` → **文本项 / 数字项 / 开关项 / 对象项 / 数组项**;
  `minHeight 38, paddingHorizontal 11, borderRadius 10, borderWidth 1`, `Plus` 14 `primary`,
  label 11 weight 800 `primary`. `addItem` creates a **fresh** `[]` / `{}` (never shares the
  template instance) or appends the primitive as-is.

**`NumberArrayInput({ value, onChange, placeholder })`** — numeric text field with a draft buffer:

- `draft` initialised to `String(value)`; an effect on `[value]` resets the draft when it is blank or
  when `Number(draft) !== value`.
- `onChangeText`: always update the draft; then if the trimmed text is non-empty and **not** one of
  `'-'`, `'+'`, `'.'`, `'-.'`, `'+.'` and `Number.isFinite(Number(trimmed))`, push the number up.
- `onBlur` / `onSubmitEditing` commit: if the trimmed text is non-empty and finite, push it and
  normalise the draft to `String(next)`; otherwise revert the draft to `String(value)`.
- `keyboardType="numeric"`, same `inputStyle` as `QueryArrayForm`.

The object-mode editors are `StructuredForm` (spec: `_spec/structured-form.md`) — insertion-ordered,
no key hiding, with its own add/remove/typed-field affordances.

### 5.9 Response viewer

Shown only when `mutation.data` exists (i.e. after a success — a thrown error goes to `ErrorState`
instead). `SectionHeader icon={CheckCircle2} title="响应" meta={`HTTP ${status}`}` then one `Panel`:

| `kind` | Rendering |
| --- | --- |
| `json` | `<StructuredDataView value={data} />` — recursive read-only tree; **filters out the `ret` and `msg` keys** at every object level, caps at 200 entries/items per level with the overflow notes `仅显示前 200 个字段，共 N 个` / `仅显示前 200 项，共 N 项`, renders empty object as `暂无数据`, empty array as `暂无项目`, booleans as `是`/`否`, and `null`/`undefined`/`''` as `--`; array items are labelled `第 N 项` |
| `binary` | `<StructuredDataView value={formatBinary(data)} />` followed by the save button |
| `empty` | `<Text style={{ color: subtext }}>响应体为空</Text>` |
| `text` (fallback branch) | `<Text selectable style={{ color: text, fontSize: 12, lineHeight: 18 }}>{String(data ?? '')}</Text>` |

```ts
function formatBinary(result: LuckyEndpointResult) {
  return {
    状态: result.status,
    类型: result.contentType || 'application/octet-stream',
    文件名: result.filename || '未命名文件',
    大小: `${result.byteLength ?? 0} bytes`,
  };
}
```

The Chinese keys pass through `StructuredDataView`'s `fieldLabel` unchanged (no entry in the label
map, and the underscore/camel-case regexes are no-ops on CJK), so the four rows read
**状态 / 类型 / 文件名 / 大小**.

Save button (binary only): `Pressable disabled={saving}`, `minHeight 44, borderRadius 11`,
bg `disabled` while saving else `primary`, centred row `gap 7`, `Download` 16 `#fff`, label `#fff`
weight 800 = `保存中...` while saving, else `下载文件` on web and `保存文件` on native.

### 5.10 Behaviour a port must preserve

- Changing the method aborts any in-flight request **and clears the previous response**.
- Changing the endpoint (only possible by re-navigating) resets every field.
- The send button turns red (`danger`) whenever the request is dangerous **or** in flight, and the
  same button doubles as cancel while pending.
- A dangerous request always requires the confirm alert, even after a previous confirmation.
- Query params are sent for **every** method, including GET; the body is dropped for GET.
- `sendBody` off with a file selected still uploads the file (multipart with just the file part).
- No response, request, or field values are persisted anywhere — a fresh mount starts empty.

---

## 6. Chinese string inventory (verbatim, deduplicated)

`app/modules/[module].tsx`: `模块不存在` · `接口清单中没有找到该模块` · `{n} 个端点 · {m} 个方法` ·
`搜索路径或接口` · `接口列表` · `{n} 项` · `没有匹配的接口` · `需要路径参数` (prefixed by ` · `) ·
`Lucky API` (source fallback, ASCII).

`app/_layout.tsx` (headers for these routes): `模块接口` · `接口调试` · `返回`.

`app/endpoints/[id].tsx`: `接口不存在` · `无法在接口清单中找到该端点` · `接口调试` · `来源：` ·
`开发文档` · `请求配置` · `高风险请求，执行前会再次确认。` · `路径参数 {name}` ·
`输入 ID、Key 或资源名称` · `资源 Key / 路径后缀` · `输入资源名称或路径后缀` · `查询参数` ·
`对象` · `数组` · `参数名` · `参数值` · `删除查询参数` · `添加查询参数` · `发送请求体` ·
`嵌套数组` · `第 {n} 项` · `删除数组项` · `文本项` · `数字项` · `开关项` · `对象项` · `数组项` ·
`上传文件` · `移除文件` · `Multipart 字段名` · `选择文件` · `无法读取所选文件` ·
`当前运行环境不支持文件上传` · `取消请求` · `执行 {METHOD}` · `确认执行高风险接口` ·
`该请求可能修改或删除系统、网络、证书或容器数据。` · `取消` · `确认执行` · `响应` ·
`HTTP {status}` · `响应体为空` · `状态` · `类型` · `文件名` · `未命名文件` · `大小` ·
`保存中...` · `下载文件` · `保存文件` · `下载已开始` · `保存成功` · `保存失败` ·
`无法保存文件` · `响应中没有可保存的文件` · `请填写路径参数 {names\|资源 Key / 路径后缀}` ·
`接口不存在` (mutation guard).

`src/services/lucky-endpoints.ts`: see §2.10.

`StructuredDataView` (shared): `暂无数据` · `暂无项目` · `是` · `否` · `--` · `第 {n} 项` ·
`仅显示前 200 个字段，共 {n} 个` · `仅显示前 200 项，共 {n} 项`.

Shared UI: `重试` (`ErrorState` retry — unused on these screens) · `刷新` (`PageHeader` refresh —
unused on these screens).

---

## 7. Colour roles used by these two screens (`src/lib/theme.ts`)

Selected by `useColorScheme() === 'dark'`.

| Role | Light | Dark | Used for |
| --- | --- | --- | --- |
| `page` | `#f5f5f7` | `#000000` | screen background |
| `card` | `#ffffff` | `#1c1c1e` | rows, panels, unselected chips |
| `mutedCard` | `#f2f2f7` | `#2c2c2e` | inputs, mode picker track, meta pills |
| `text` | `#1d1d1f` | `#f5f5f7` | primary text |
| `subtext` | `#6e6e73` | `#a1a1a6` | captions, source line, empty text |
| `border` | `#e1e1e6` | `#3a3a3c` | all 1 pt borders |
| `primary` | `#007aff` | `#0a84ff` | POST chip, selected states, send button |
| `primarySoft` | `#e5f1ff` | `#0b2f52` | `IconTile` background |
| `success` | `#248a3d` | `#30d158` | GET chip, picked-file border/icon |
| `warning` | `#c93400` | `#ff9f0a` | PUT chip |
| `danger` | `#ff3b30` | `#ff453a` | DELETE chip, errors, cancel/danger button |
| `dangerBg` | `#fff0ef` | `#3d1412` | danger banner, `ErrorState`, delete buttons |
| `disabled` | `#aeaeb2` | `#636366` | chevron, switch off track, saving button |
| `placeholder` | `#8e8e93` | `#8e8e93` | placeholder text |

Literal `#fff` is hard-coded for the selected-method label, the send-button content and the
save-button content. Method chip backgrounds are the method colour with the literal alpha suffix
`22` appended to the 6-digit hex (`#007aff22` etc.).

---

## 8. 1:1 coverage checklist for the SwiftUI port

Service layer (`lucky-endpoints.ts`, 7 exported symbols):

- [ ] `getLuckyModules`, `getLuckyEndpoints(module?)` (empty string ⇒ all), `getLuckyEndpoint(id)`
- [ ] `isDangerousLuckyRequest` — non-GET always true; GET tested against
      `path(trailing / stripped) + "/" + dynamicPath(leading / stripped)`
- [ ] `resolveLuckyEndpointPath` — variable substitution (nullish fallback to `suffix`,
      per-value `encodeURIComponent(trim)`, `replaceAll`), trailing-slash suffix append via
      `encodePathSuffix` (segment split, `.`/`..` rejection, per-segment encoding), then query
- [ ] `appendQuery` / `appendQueryValue` — drop empty key & `undefined`/`null`/`''`, keep `0`/`false`,
      repeat key per array element, `JSON.stringify` objects, `?` vs `&` separator
- [ ] `callLuckyEndpoint` — method whitelist check, base-URL normalisation, nonce, 20 s / 600 s
      timeout split, `Lucky-Admin-Token`, JSON/text/blob branch conditions, `ret === -1` and 401
      single-shot token refresh + `endLuckySession`, `filename` extraction, all 9 error strings
- [ ] `LuckyEndpointResult` four-way `kind`

Registry:

- [ ] 328 endpoints, 45 modules, 448 methods; ids `module-NNN` from the **global** row index
- [ ] `LUCKY_MODULES` in the exact zh-CN label order of §1.6 with the exact labels and counts
- [ ] `requiresSuffix` 87 true; `pathVariables` 58 × `["e"]`

Screens:

- [ ] Module list: label/subtitle header, search over `"path id source"`, `接口列表` +
      `{n} 项` meta, 82 pt rows with method chips at 13 % alpha, `需要路径参数` marker,
      empty states for unknown module vs no match, push to `/endpoints/{encoded id}`
- [ ] Debugger: all 12 controls of §5.7 in order, the four sub-forms of §5.8, the body matrix of
      §5.4, multipart rules of §5.5, validation/confirm/cancel of §5.6, response viewer of §5.9
- [ ] No history / favourites / persistence anywhere
