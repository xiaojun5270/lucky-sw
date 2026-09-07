# API Specification — `src/services/docker.ts`

Source of truth: `C:\Users\xiaoj\Desktop\lucky\src\services\docker.ts` (1138 lines).
Transport: `C:\Users\xiaoj\Desktop\lucky\src\lib\lucky-fetch.ts` (`luckyFetch`).
Types: `C:\Users\xiaoj\Desktop\lucky\src\types\lucky.ts` (`LuckyRecord = Record<string, unknown>`, `LuckyListItem`, `LuckyResponse<T> = T & { ret: number; msg?: string }`).

Exported callables: **123**. Exported types: **3** (`DockerContainerFileOperation`, `DockerComposeCreateInput`, `DockerTaskWaitOptions`).
Every request goes through `callDockerApi`, so every URL is `/api/docker/<path>` plus a query string, plus the cache-buster `_=<nonce>` appended by `luckyFetch`.

## 1. Distinct API paths

All paths are relative to `/api/docker/`. `{...}` segments are `encodeURIComponent`-escaped (except where noted).

| Path | Methods | Functions |
| --- | --- | --- |
| `containers` | GET, POST | `listDockerContainers`, `createDockerContainer` |
| `containers/{id}` | GET, DELETE | `getDockerContainer`, `removeDockerContainer` |
| `containers/{id}/edit` | POST | `editDockerContainer` |
| `containers/{id}/rename` | POST | `renameDockerContainer` |
| `containers/{id}/{action}` (`start`\|`stop`\|`restart`\|`pause`\|`unpause`) | POST | `runDockerContainerAction` |
| `containers/{id}/logs` | GET | `getDockerContainerLogs` |
| `containers/{id}/stats-cached` | GET | `getDockerContainerStats` |
| `containers/{id}/stats` | GET | `getDockerContainerLiveStats` |
| `containers/{id}/processes` | GET | `getDockerContainerProcesses` |
| `containers/stats-cached` | GET | `getAllDockerContainerStats` |
| `containers/{id}/files` | DELETE | `runDockerContainerFileOperation("delete")` |
| `containers/{id}/files/{operation}` | GET, POST | `runDockerContainerFileOperation` |
| `containers/{id}/files/upload` | POST | `uploadDockerContainerFile` |
| `containers/{id}/files/download` | GET | `downloadDockerContainerFile` |
| `containers/{id}/export` | POST | `exportDockerContainer` |
| `containers/{id}/commit` | POST | `commitDockerContainer` |
| `containers/{id}/copy` | POST | `copyDockerContainer` |
| `containers/{id}/upgrade-check` | GET | `checkDockerContainerUpgrade` |
| `containers/{id}/upgrade` | POST | `upgradeDockerContainer` |
| `containers/{id}/compose-config` | GET | `getDockerContainerComposeConfig` |
| `containers/{id}/label` | POST, DELETE | `setDockerContainerLabel`, `removeDockerContainerLabel` |
| `containers/order-mapping` | GET, PUT | `getDockerContainerOrderMapping`, `updateDockerContainerOrderMapping` |
| `containers/set-group` | POST | `setDockerContainerGroup` |
| `containers/switch-version` | POST | `switchDockerContainerVersion` |
| `labels` | GET | `getDockerLabels` |
| `labels/{label}/containers` | GET | `getDockerLabelContainers` |
| `container-groups` | GET, POST, PUT, DELETE | `getDockerContainerGroups`, `createDockerContainerGroup`, `updateDockerContainerGroup`, `removeDockerContainerGroup` |
| `container-groups/count` | GET | `getDockerContainerGroupCount` |
| `container-groups/order` | PUT | `reorderDockerContainerGroups` |
| `container-groups/collapsed` | PUT | `setDockerContainerGroupCollapsed` |
| `container-groups/collapsed/states` | GET | `getDockerContainerGroupCollapsedStates` |
| `images` | GET | `listDockerImages` |
| `images/{id}` | GET, DELETE | `getDockerImage`, `removeDockerImage` (id branch) |
| `images/pull-async` | POST | `pullDockerImage` |
| `images/remove` | DELETE | `removeDockerImage` (tag branch) |
| `images/{id}/tag` | POST | `tagDockerImage` |
| `images/search` | POST | `searchDockerImages` |
| `images/{id}/history` | GET | `getDockerImageHistory` |
| `images/build` | POST | `buildDockerImage` |
| `images/pull` | POST | `pullDockerImageSync` |
| `images/push` | POST | `pushDockerImage` |
| `images/build-from-git` | POST | `buildDockerImageFromGit` |
| `images/build-from-zip` | POST | `buildDockerImageFromZip` |
| `images/import` | POST | `importDockerImage` |
| `images/load` | POST | `loadDockerImage` |
| `images/{id}/tags` | GET | `getDockerImageTags` |
| `images/{id}/filesystem` | GET | `getDockerImageFilesystem` |
| `images/upgrade-check` | POST | `checkDockerImageUpgrade`, `checkDockerImagesUpgrade` |
| `images/upgrade-status` | GET, DELETE | `getDockerImageUpgradeStatus`, `clearDockerImageUpgradeStatus` |
| `images/upgrade-dismiss` | POST | `dismissDockerImageUpgrade` |
| `images/remove-saved-digest` | POST | `removeDockerSavedDigest` |
| `images/backup-tag` | POST | `backupDockerImageTag` |
| `images/containers` | GET | `getDockerImageContainers` |
| `images/pull-with-backup` | POST | `pullDockerImageWithBackup` |
| `images/upgrade-containers` | POST | `upgradeDockerImageContainers` |
| `compose/projects` | GET | `listDockerComposeProjects` |
| `compose/up-async` | POST | `createDockerCompose` |
| `compose/{action}` (`up`\|`down`\|`start`\|`stop`\|`restart`) | POST | `runDockerComposeAction` |
| `compose/{name}/logs` | POST | `getDockerComposeLogs` |
| `compose/config` | POST | `readDockerComposeConfig` |
| `compose/read-file` | POST | `readDockerComposeFile` |
| `compose/update-config` | POST | `updateDockerComposeConfig` |
| `compose/discover` | POST | `discoverDockerCompose` |
| `compose/backup` | POST | `backupDockerCompose` |
| `compose/{projectName}/backups` | GET, DELETE | `listDockerComposeBackups`, `removeDockerComposeBackup` |
| `compose/{projectName}/backups/upload` | POST | `uploadDockerComposeBackup` |
| `compose/{projectName}/backups/download.tar.gz` | GET | `downloadDockerComposeBackup` |
| `compose/{projectName}/backups/all` | DELETE | `clearDockerComposeBackups` |
| `compose/{projectName}/backups/restore` | POST | `restoreDockerComposeBackup` |
| `compose/restore` | POST | `restoreDockerCompose` |
| `compose/{projectName}/backup/cancel` | DELETE | `cancelDockerComposeBackup` |
| `compose/backup/status` | GET | `getDockerComposeBackupStatus` |
| `compose/{projectName}/ps` | GET | `getDockerComposeContainers` |
| `compose/containers-for-cron` | GET | `getDockerComposeContainersForCron` |
| `compose/dockerfile` | POST | `readDockerComposeDockerfile` |
| `compose/update-dockerfile` | POST | `updateDockerComposeDockerfile` |
| `networks` | GET, POST | `listDockerNetworks`, `createDockerNetwork` |
| `networks/{id}` | DELETE | `removeDockerNetwork` |
| `volumes` | GET, POST | `listDockerVolumes`, `createDockerVolume` |
| `volumes/{name}` | DELETE | `removeDockerVolume` |
| `volumes/{name}/backup` | POST | `backupDockerVolume` |
| `volumes/{name}/backups` | GET, DELETE | `listDockerVolumeBackups`, `removeDockerVolumeBackup` |
| `volumes/{name}/backups/upload` | POST | `uploadDockerVolumeBackup` |
| `volumes/{name}/backups/restore` | POST | `restoreDockerVolumeBackup` |
| `volumes/{name}/backup/cancel` | DELETE | `cancelDockerVolumeBackup` |
| `volumes/export` | GET | `exportDockerVolume` |
| `volumes/import` | POST | `importDockerVolume` |
| `volumes/backup/status` | GET | `getDockerVolumeBackupStatus` |
| `tasks` | GET, DELETE | `listDockerTasks`, `clearDockerTasks` |
| `tasks/{id}` | GET, DELETE | `getDockerTask`, `removeDockerTask` |
| `info` | GET | `getDockerInfo` |
| `version` | GET | `getDockerVersion` |
| `disk-usage` | GET | `getDockerDiskUsage` |
| `monitor/status` | GET | `getDockerMonitorStatus` |
| `self-container` | GET | `getDockerSelfContainerInfo` |
| `config` | GET, POST | `getDockerConfig`, `updateDockerConfig` |
| `logs` | GET | `getDockerLogs` |
| `prune` | POST | `pruneDocker` |
| `registry/mirrors` | GET, POST, DELETE | `getDockerRegistryMirrors`, `addDockerRegistryMirror`, `removeDockerRegistryMirror` |

103 distinct path templates. `callDockerApi` itself is exported, so arbitrary paths are also reachable.

## 2. Transport contract (`luckyFetch`, needed for a 1:1 port)

- Final URL = `baseUrl.trim().replace(/\/+$/,"")` + path (path is prefixed with `/` if missing) + nonce.
- Nonce: `withLuckyRequestNonce(path)` appends `?_=<nonce>` or `&_=<nonce>` (`&` when the path already contains `?`). `createLuckyRequestNonce(now = Date.now())`: `timestamp = String(now).slice(0, -1)`; `checksum = (sum of the digits of timestamp) % 8`; nonce = `` `${timestamp}${checksum}` ``.
- Headers: `Accept: application/json` (or `application/octet-stream, application/json;q=0.8, text/plain;q=0.6` when `responseType === "blob"`); `Content-Type: application/json` when a body exists and it is not `FormData`/`Blob`; `Lucky-Admin-Token: <token>` when a token exists.
- Default timeout `DEFAULT_REQUEST_TIMEOUT_MS = 12000` ms. `callDockerApi` overrides it per call (see tables).
- Response normalisation: HTTP 401 → `{ ret: -1 }`; HTTP 204 or `content-length: 0` → `{ ret: 0 }`; blob branch (only when `responseType === "blob"` and content type is not JSON) → `{ ret: 0, data: Blob, contentType, filename, byteLength }`, but if the blob is ≤ 1048576 bytes and parses as JSON that parsed envelope wins; text branch → `{ ret: 0, data: <raw string> }`; JSON branch → parsed object with `ret` coerced through `Number`, defaulting to `0`.
- Blob-branch error path: on `!response.ok`, if `blob.size <= 65536` the body text (trimmed) is the error message, else `请求失败（HTTP <status>）`.
- Auth retry: on HTTP 401 or `ret === -1`, with `retryAuth` (default `true`), refresh the token (POST `/api/login` with body `{"Account","Password","TwoFA","TwoFACode"}`) and retry once with `retryAuth: false`; on refresh failure the session is ended and a `LuckyAuthError` is thrown (default message `登录已失效，请重新登录`).
- Failure: `!response.ok || ret !== 0` → `Error(payload.msg || `请求失败（HTTP <status>）`)`.
- Abort/timeout mapping: external abort → `Error("请求已取消")`; internal timeout → `Error("请求超时，请检查服务器连接")`.

## 3. Types declared in this module

```ts
type DockerMethod = "GET" | "POST" | "PUT" | "DELETE";
type DockerSignalInput = AbortSignal | { signal?: AbortSignal };
type DockerContainerInput = LuckyListItem[] | { items?: LuckyListItem[]; signal?: AbortSignal } | AbortSignal;
type DockerBatchProgress<T> = { succeeded: T[]; failed: { item: T; error: string }[]; completedCount: number; totalCount: number };
```
```ts
export type DockerContainerFileOperation =
  | "list" | "read" | "write" | "delete" | "mkdir" | "touch" | "rename" | "copy"
  | "chmod" | "search" | "compress" | "compress-async" | "decompress"
  | "decompress-async" | "preview-archive";

export type DockerComposeCreateInput = {
  project_name?: string;
  working_dir: string;      // required
  compose_content: string;  // required
  config_file_name: string; // required
  build?: boolean;
};

export type DockerTaskWaitOptions = {
  signal?: AbortSignal;
  timeoutMs?: number;
  intervalMs?: number;
  onProgress?: (task: LuckyRecord) => void;
};
```

## 4. Non-exported helpers (full logic — must be reproduced exactly)

### `isRecord(value): value is LuckyRecord`
`Boolean(value) && typeof value === "object" && !Array.isArray(value)`. Note: `null` → false; `Date`/`Blob` → true.

### `encodeQuery(params?: LuckyRecord): string`
1. `if (!params) return ""`.
2. Take `Object.entries(params)` **in insertion order**.
3. Drop entries whose value is `undefined`, `null`, or `""` (exact triple-equals checks; `false` and `0` are **kept**).
4. Map each to `` `${encodeURIComponent(key)}=${encodeURIComponent(typeof value === "string" ? value : JSON.stringify(value))}` ``. So booleans become `true`/`false`, numbers become their JSON text, arrays/objects become JSON text.
5. Join with `&`; return `""` if empty, otherwise `"?" + text`.

### `findArray(payload: LuckyRecord, keys: string[]): unknown[] | undefined`
Wrapper key set (lower-case compare): **`["data", "result", "response", "payload"]`**.
For each `wantedKey` of `keys` **in order** (a fresh BFS per key):
- `queue = [payload]`, `visited = new Set<object>()`.
- Loop while queue non-empty; `source = queue.shift()`:
  - `if (Array.isArray(source)) return source;` (this is how a wrapper array such as `{ data: [...] }` is returned even when the key name never matches)
  - `if (!isRecord(source) || visited.has(source)) continue;` then `visited.add(source)`.
  - **First pass** over `Object.entries(source)`: if `key.toLowerCase() === wanted && Array.isArray(value)` → return `value`.
  - **Second pass** over `Object.entries(source)`: push `value` if `isRecord(value)`; else push `value` if `Array.isArray(value) && wrappers.has(key.toLowerCase())`.
Return `undefined` when no key matched.

### `list(payload, keys): LuckyListItem[]`
`(findArray(payload, keys) ?? []).filter(isRecord)` — non-object array elements are silently dropped.
### `findScalar(payload: unknown, keys: string[]): string | number | boolean | undefined`
`wanted` = **all** keys lower-cased in one Set (not per-key like `findArray`). BFS:
- `queue = [payload]`, `visited`.
- `current = queue.shift()`; skip when falsy or `typeof current !== "object"`; skip when already visited; then mark visited.
- If `Array.isArray(current)` → `queue.push(...current)` and `continue`.
- For each `[key, value]` of `Object.entries(current)`: return `value` when `wanted.has(key.toLowerCase())` **and** `typeof value` is one of `"string" | "number" | "boolean"`.
- Then `queue.push(...Object.values(current))`.
Return `undefined` if exhausted.

### `findRecord(payload: LuckyRecord, keys: string[]): LuckyRecord`
`wanted` = all keys lower-cased. BFS over records only:
- `current = queue.shift()!`; skip if visited; mark visited.
- First pass: return `value` when `wanted.has(key.toLowerCase()) && isRecord(value)`.
- Second pass: push every `isRecord(value)`.
**Fallback: returns `payload` itself** (never `undefined`).

### `resolveDockerSignal(input?: DockerSignalInput): AbortSignal | undefined`
`isAbortSignal(input) ? input : input?.signal`.

### `isAbortSignal(value): value is AbortSignal`
`Boolean(value) && typeof value === "object" && typeof value.aborted === "boolean" && typeof value.addEventListener === "function"`.

### `containerText(item: LuckyRecord, keys: string[]): string`
For each key **in order**: `value = item[key]` (direct property, **case-sensitive, no nesting**).
- `typeof value === "string" && value.trim()` → return `value.trim()`.
- `Array.isArray(value) && value.length` → return `value.map(String).join(", ")`.
Return `""`.

### `resolveDockerContainerInput(input?: DockerContainerInput)`
- `Array.isArray(input)` → `{ items: input, signal: undefined }`.
- `isAbortSignal(input)` → `{ items: undefined, signal: input }`.
- otherwise → `{ items: input?.items, signal: input?.signal }`.

### `throwIfAborted(signal?: AbortSignal)`
`if (!signal?.aborted) return;` else throw `new Error("Request cancelled")` with `error.name = "AbortError"`.

### `dockerContainerFileMethods: Record<DockerContainerFileOperation, DockerMethod>`
```ts
{ list: "GET", read: "GET", write: "POST", delete: "DELETE", mkdir: "POST", touch: "POST",
  rename: "POST", copy: "POST", chmod: "POST", search: "POST", compress: "POST",
  "compress-async": "POST", decompress: "POST", "decompress-async": "POST",
  "preview-archive": "GET" }
```
### Verbatim key-name arrays for image identity

```ts
const dockerImageIdKeys = [
  "ImageID", "ImageId", "imageID", "imageId", "image_id", "Digest", "digest",
] as const;

const dockerImageReferenceKeys = [
  "Image", "image", "ImageName", "imageName", "image_ref", "imageRef",
  "RepoTag", "repoTag", "RepoTags", "repoTags",
  "RepoDigest", "repoDigest", "RepoDigests", "repoDigests",
  "Tags", "tags", "Name", "name",
] as const;

const dockerImageRecordIdKeys = ["Id", "ID", "id", ...dockerImageIdKeys] as const;
// = ["Id","ID","id","ImageID","ImageId","imageID","imageId","image_id","Digest","digest"]

const dockerContainerImageReferenceKeys = dockerImageReferenceKeys.filter(
  (key) => !["Name", "name"].includes(key),
);
// = ["Image","image","ImageName","imageName","image_ref","imageRef","RepoTag","repoTag",
//    "RepoTags","repoTags","RepoDigest","repoDigest","RepoDigests","repoDigests","Tags","tags"]
```

Other verbatim key-name arrays used elsewhere in the module:

| Where | Array |
| --- | --- |
| `listDockerContainers` unwrap | `["containers", "list"]` |
| `listDockerImages` unwrap | `["images", "list"]` |
| `listDockerComposeProjects` unwrap | `["projects", "list", "composeProjects"]` |
| `listDockerNetworks` unwrap | `["networks", "list"]` |
| `listDockerVolumes` unwrap | `["volumes", "list"]` |
| `listDockerTasks` unwrap | `["tasks", "list"]` |
| `refreshDockerContainerStats` id | `["Id", "ID", "id", "ContainerID", "ContainerId"]` |
| `refreshDockerContainerStats` name | `["Names", "Name", "name", "ContainerName"]` |
| `refreshDockerContainerStats` state join | `[item.State, item.state, item.Status, item.status]` |
| `waitForDockerTask` status | `["status", "state"]` |
| `waitForDockerTask` failure detail | `["error", "message", "output", "msg"]` |
| `waitForDockerTask` success statuses | `["completed", "complete", "success", "succeeded"]` |
| `waitForDockerTask` failure statuses | `["failed", "error", "cancelled", "canceled"]` |
| `getDockerOverview` info record | `["info", "dockerInfo", "data", "result"]` |
| `getDockerOverview` container fallback | `["Containers", "containers"]` |
| `getDockerOverview` image fallback | `["Images", "images"]` |
| `getDockerOverview` image size | `["Size", "size", "VirtualSize", "virtualSize"]` |
| `pruneUnusedDockerImages` id pick | `[image.Id, image.ID, image.id]` |
| `pruneDocker` other-cleanup keys | `["containers", "networks", "volumes", "build_cache"]` |
### `stringValues(value: unknown): string[]`
- `typeof value === "string" || typeof value === "number"` → `[String(value)]`.
- `Array.isArray(value)` → `value.flatMap(stringValues)` (recursive).
- otherwise → `[]` (booleans, `null`, objects produce nothing).

### `collectDockerImageValues(item: LuckyRecord, keys: readonly string[]): string[]`
Depth-limited BFS ("Reads image fields from the Docker list shape and Lucky's nested variants"):
- `wanted` = keys lower-cased Set. `values: unknown[] = []`.
- `queue = [{ value: item, depth: 0 }]`, `visited = new Set<object>()`.
- Pop front; skip when `!current.value || typeof current.value !== "object"`; skip when visited; mark visited.
- If array: **only if `current.depth < 3`** push every element with `depth + 1`; then `continue`.
- Else for each `[key, value]` of `Object.entries(record)`:
  - if `wanted.has(key.toLowerCase())` → `values.push(value)`;
  - if `current.depth < 2 && value && typeof value === "object"` → push `{ value, depth: current.depth + 1 }`.
- Return `values.flatMap(stringValues)`.

### `imageIdAliases(value: string): Set<string>`
- `normalized = value.trim().toLowerCase().replace(/^sha256:/, "")`.
- If `/^[a-f\d]{12,64}$/i.test(normalized)` → `new Set(["id:" + normalized, "id:sha256:" + normalized])`, else empty Set.

### `canonicalDockerImageReference(value: string): string`
- `reference = value.trim().replace(/^\/+/, "").toLowerCase()`; return `""` if empty.
- `parts = reference.split("/")`, `first = parts[0]`.
- `hasRegistry = parts.length > 1 && (first.includes(".") || first.includes(":") || first === "localhost")`.
- If `!hasRegistry`: `reference = parts.length === 1 ? "docker.io/library/" + reference : "docker.io/" + reference`.
- Return `reference`.

### `dockerImageAliases(value: string): Set<string>`
- `raw = value.trim().replace(/^\/+/, "").toLowerCase()`; return empty Set when `raw` is empty.
- Add every alias from `imageIdAliases(raw)`.
- `digestMatch = raw.match(/(?:^|@)(sha256:[a-f\d]{12,64})$/i)`; if matched, add every alias from `imageIdAliases(digestMatch[1])`.
- `reference = canonicalDockerImageReference(raw)`; if empty, return what we have.
- Add `` `ref:${raw}` `` and `` `ref:${reference}` ``.
- `last = reference.slice(reference.lastIndexOf("/") + 1)`; if `!last.includes(":") && !last.includes("@")` add `` `ref:${reference}:latest` ``.

### `dockerImageAliasesIntersect(left: Set<string>, right: Set<string>): boolean`
1. Exact membership: any alias of `left` present in `right` → `true`.
2. Otherwise compare only `id:` aliases: strip the `id:` prefix (`slice(3)`) then a leading `sha256:` on both sides; return `true` when some left id and some right id both have length ≥ 12 and one is a prefix of the other (short-ID matching).

### `collectDockerImageAliases(item: LuckyRecord, imageRecord = false)`
- `idValues = collectDockerImageValues(item, imageRecord ? dockerImageRecordIdKeys : dockerImageIdKeys)`.
- `referenceValues = collectDockerImageValues(item, imageRecord ? dockerImageReferenceKeys : dockerContainerImageReferenceKeys)`.
- For each id value: add all its `dockerImageAliases`, and additionally record those starting with `id:` in a separate `idAliases` set.
- For each reference value: add all its `dockerImageAliases`.
- Returns `{ aliases, hasIdentity: aliases.size > 0, hasImageId: idAliases.size > 0 }`.
### `runDockerBatch<T>(items, task, options = {})`
```ts
options: { concurrency?: number; onProgress?: (p: DockerBatchProgress<T>) => void; isCancelled?: () => boolean }
// defaults: concurrency = 4
```
- `succeeded: T[]`, `failed: { item: T; error: string }[]`, shared `cursor = 0`.
- Worker loop: `while (cursor < items.length)`; if `isCancelled?.()` **return immediately** (does not consume the item); `item = items[cursor++]`; `try { await task(item); succeeded.push(item); } catch { failed.push({ item, error: error instanceof Error ? error.message : "请求失败" }); } finally { onProgress?.({ succeeded: [...succeeded], failed: [...failed], completedCount: succeeded.length + failed.length, totalCount: items.length }); }`
- Worker count: `Math.min(concurrency, items.length)`, all started with `Promise.all` (0 workers when `items` is empty).
- Returns `{ succeeded, failed, cancelled: cursor < items.length }`.
- Progress arrays are fresh copies each callback; `onProgress` fires once per completed item (success **and** failure).

### `unusedImageScanResult(unused, used, failed, totalCount): LuckyRecord`
```ts
{ ret: 0, unused, used, failed,
  unusedCount: unused.length, usedCount: used.length, failedCount: failed.length,
  completedCount: unused.length + used.length + failed.length, totalCount }
```

### `preferredTaskScalar(payload: LuckyRecord, keys: string[])`
For each key **in order**: `value = findScalar(payload, [key])` (one-key search, so key priority is respected); return it when `value !== undefined && value !== ""`. Return `undefined` otherwise.

### `waitForDockerPoll(ms: number, signal?: AbortSignal): Promise<void>`
- If `signal?.aborted` already → reject `Error("Request cancelled")` with `name = "AbortError"`.
- `setTimeout(ms)` → remove the abort listener, resolve.
- Abort listener (`{ once: true }`) → `clearTimeout`, reject `Error("Request cancelled")` with `name = "AbortError"`.

### `optionalDockerRequest<T>(request: Promise<T>, signal?: AbortSignal): Promise<T | undefined>`
`try { return await request } catch (error) { if (signal?.aborted) throw error; return undefined }`.

### `pruneUnusedDockerImages()` (private, used only by `pruneDocker` fallback)
1. `const { items } = await listDockerImages();` — **no abort signal**.
2. For each image: `id = [image.Id, image.ID, image.id].find(v => typeof v === "string" && v.trim())`; push to `ids` when found, else `missingIdCount += 1`.
3. `scan = await scanUnusedDockerImages(ids)` — one container snapshot decides usage; uncertain images stay skipped.
4. `unused = Array.isArray(scan.unused) ? scan.unused.map(String) : []`.
5. `removal = await runDockerBatch(unused, id => removeDockerImage(id, true), { concurrency: 4 })` — note `force = true` here.
6. `used = Array.isArray(scan.used) ? scan.used.map(String) : []`.
7. `uncertain = Array.isArray(scan.failed) ? scan.failed.flatMap(item => isRecord(item) && typeof item.item === "string" ? [item.item] : []) : []`.
8. Returns
```ts
{ removed: removal.succeeded,
  skipped: [ ...Array.from({ length: missingIdCount }, () => "未知镜像"), ...used, ...uncertain,
             ...removal.failed.map(({ item }) => item) ],
  removedCount: removal.succeeded.length,
  skippedCount: used.length + uncertain.length + removal.failed.length + missingIdCount }
```
## 5. Exported functions

### 5.0 `callDockerApi` — the single request primitive

```ts
export function callDockerApi(
  path: string,
  method: DockerMethod = "GET",
  data?: unknown,
  params?: LuckyRecord,
  timeoutMs?: number,
  signal?: AbortSignal,
  responseType: "auto" | "json" | "text" | "blob" = "auto",
)
```
- URL: `` `/api/docker/${path.replace(/^\//, "")}${encodeQuery(params)}` `` — the regex strips **exactly one** leading `/`.
- Body: `undefined` when `data === undefined`; the `FormData` instance itself when `data instanceof FormData` (so the browser sets the multipart boundary and `luckyFetch` omits `Content-Type`); otherwise `JSON.stringify(data)`. `null` is **not** treated as absent — it serialises to `"null"`.
- `timeoutMs`, `signal`, `responseType` are forwarded verbatim to `luckyFetch`; when `timeoutMs` is `undefined` the 12000 ms default applies.
- Returns the `LuckyResponse` envelope (`ret` plus whatever the server sent).

Reading conventions for the tables below: "query" is the `params` argument (rendered through `encodeQuery`, so `false`/`0` survive and `undefined`/`null`/`""` are dropped); "body" is the `data` argument; blank timeout = 12000 ms default; blank signal = none.

### 5.1 Containers

| Function | Method | Path + query | Body | Timeout |
| --- | --- | --- | --- | --- |
| `listDockerContainers(input?: DockerSignalInput)` — async, returns `{ items: LuckyListItem[], raw }` | GET | `containers?all=true&includeStats=false&includeNetworkMode=true` | — | 12000 |
| `getDockerContainer(id: string)` | GET | `containers/{id}` | — | 12000 |
| `createDockerContainer(data: LuckyRecord)` | POST | `containers` | `data` verbatim | 12000 |
| `editDockerContainer(id: string, data: LuckyRecord)` | POST | `containers/{id}/edit` | `data` verbatim | 300000 |
| `removeDockerContainer(id: string, force = false, removeVolumes = false)` | DELETE | `containers/{id}?force={force}&remove_volumes={removeVolumes}` | — | 12000 |
| `renameDockerContainer(id: string, name: string)` | POST | `containers/{id}/rename` | `{"name": name}` | 12000 |
| `runDockerContainerAction(id: string, action: "start"\|"stop"\|"restart"\|"pause"\|"unpause")` | POST | `containers/{id}/{action}` | `{"timeout": 10}` when action is `stop` or `restart`, otherwise **no body** | 12000 |
| `getDockerContainerLogs(id: string, tail = 200)` | GET | `containers/{id}/logs?tail={tail}&timestamps=true` | — | 12000 |
| `getDockerContainerStats(id: string, input?: DockerSignalInput)` | GET | `containers/{id}/stats-cached` | — | 12000 |
| `getDockerContainerLiveStats(id: string, input?: DockerSignalInput)` | GET | `containers/{id}/stats` | — | 10000 |
| `getDockerContainerProcesses(id: string)` | GET | `containers/{id}/processes` | — | 12000 |
| `getAllDockerContainerStats(input?: DockerSignalInput)` | GET | `containers/stats-cached` | — | 15000 |
| `uploadDockerContainerFile(id: string, data: FormData)` | POST | `containers/{id}/files/upload` | multipart `FormData` | 600000 |
| `downloadDockerContainerFile(id: string, path: string)` | GET | `containers/{id}/files/download?path={path}` | — | 600000, `responseType: "blob"` |
| `exportDockerContainer(id: string)` | POST | `containers/{id}/export` | — | 600000, `responseType: "blob"` |
| `commitDockerContainer(id: string, data: LuckyRecord)` | POST | `containers/{id}/commit` | `data` verbatim | 300000 |
| `copyDockerContainer(id: string, name: string)` | POST | `containers/{id}/copy` | `{"name": name}` | 300000 |
| `checkDockerContainerUpgrade(id: string)` | GET | `containers/{id}/upgrade-check` | — | 60000 |
| `upgradeDockerContainer(id: string, data: LuckyRecord)` | POST | `containers/{id}/upgrade` | `data` verbatim | 300000 |
| `getDockerContainerComposeConfig(id: string)` | GET | `containers/{id}/compose-config` | — | 12000 |
| `setDockerContainerLabel(id: string, label: string)` | POST | `containers/{id}/label` | `{"label": label}` | 12000 |
| `removeDockerContainerLabel(id: string)` | DELETE | `containers/{id}/label` | — | 12000 |
`listDockerContainers` unwrapping: `raw = await callDockerApi(...)`; result is `{ items: list(raw, ["containers", "list"]), raw }` — `items` is `LuckyListItem[]`, `raw` is the full envelope. The signal is `resolveDockerSignal(input)`, so the argument may be either an `AbortSignal` or `{ signal }`.

### 5.2 Labels, groups and ordering

| Function | Method | Path + query | Body | Timeout |
| --- | --- | --- | --- | --- |
| `getDockerLabels(input?: DockerSignalInput)` | GET | `labels` | — | 12000 |
| `getDockerLabelContainers(label: string)` | GET | `labels/{label}/containers` | — | 12000 |
| `getDockerContainerGroups(input?: DockerSignalInput)` | GET | `container-groups` | — | 12000 |
| `createDockerContainerGroup(data: LuckyRecord)` | POST | `container-groups` | `data` verbatim | 12000 |
| `updateDockerContainerGroup(data: LuckyRecord)` | PUT | `container-groups` | `data` verbatim | 12000 |
| `removeDockerContainerGroup(key: string)` | DELETE | `container-groups?key={key}` | — (query, not body) | 12000 |
| `getDockerContainerGroupCount(groupKey: string)` | GET | `container-groups/count?groupKey={groupKey}` | — | 12000 |
| `reorderDockerContainerGroups(data: unknown)` | PUT | `container-groups/order` | `data` verbatim (any JSON value) | 12000 |
| `setDockerContainerGroupCollapsed(key: string, collapsed: boolean)` | PUT | `container-groups/collapsed` | `{"key": key, "collapsed": collapsed}` | 12000 |
| `getDockerContainerGroupCollapsedStates(input?: DockerSignalInput)` | GET | `container-groups/collapsed/states` | — | 12000 |
| `getDockerContainerOrderMapping(input?: DockerSignalInput)` | GET | `containers/order-mapping` | — | 12000 |
| `updateDockerContainerOrderMapping(containerGroupMap: unknown, orderList: unknown)` | PUT | `containers/order-mapping` | `{"containerGroupMap": containerGroupMap, "orderList": orderList}` | 12000 |
| `setDockerContainerGroup(containerName: string, groupKey: string)` | POST | `containers/set-group` | `{"containerName": containerName, "groupKey": groupKey}` | 12000 |
| `switchDockerContainerVersion(containerIds: unknown, targetImageRef: string)` | POST | `containers/switch-version` | `{"container_ids": containerIds, "target_image_ref": targetImageRef}` | 300000 |

### 5.3 `runDockerContainerFileOperation(id: string, operation: string, data: LuckyRecord)`

1. **Validation:** `if (!Object.prototype.hasOwnProperty.call(dockerContainerFileMethods, operation)) throw new Error(`不支持的容器文件操作：${operation || "空"}`)` — an empty/falsy `operation` renders the message as `不支持的容器文件操作：空`. This throws **synchronously**, before any request.
2. `method = dockerContainerFileMethods[operation]`.
3. `path = operation === "delete" ? `containers/${encodeURIComponent(id)}/files` : `containers/${encodeURIComponent(id)}/files/${operation}`` — note the operation segment is **not** URL-encoded (it is already a safe literal).
4. `readOnly = method === "GET"` → true for `list`, `read`, `preview-archive`.
5. `longRunning = operation.includes("compress") || operation.includes("decompress")` → true for `compress`, `compress-async`, `decompress`, `decompress-async` (`"decompress".includes("compress")` is already true).
6. Call: `callDockerApi(path, method, readOnly ? undefined : data, readOnly ? data : undefined, longRunning ? 600000 : undefined)`.
   - **GET operations send `data` as the query string**, no body.
   - **POST/DELETE operations send `data` as the JSON body**, no query.
   - Timeout 600000 ms for the four (de)compress operations, otherwise the 12000 ms default.
### 5.4 `refreshDockerContainerStats(onProgress?, containerInput?, signal?)`

```ts
export async function refreshDockerContainerStats(
  onProgress?: (payload: LuckyRecord) => void,
  containerInput?: DockerContainerInput,
  signal?: AbortSignal,
): Promise<LuckyRecord>
```
1. `resolved = resolveDockerContainerInput(containerInput)`; `requestSignal = signal ?? resolved.signal` (explicit third argument wins).
2. `throwIfAborted(requestSignal)`.
3. `items = resolved.items ?? (await listDockerContainers(requestSignal)).items` — the container list is fetched only when no items were supplied.
4. `throwIfAborted(requestSignal)` again.
5. Build `targets` from each item:
   - `id = containerText(item, ["Id", "ID", "id", "ContainerID", "ContainerId"])`.
   - `name = containerText(item, ["Names", "Name", "name", "ContainerName"]).replace(/^\/+/, "")` — leading slashes stripped (Docker's `/name` form).
   - `runningValue = item.Running ?? item.running`; `normalizedRunning = typeof runningValue === "string" ? runningValue.trim().toLowerCase() : runningValue`.
   - `state = [item.State, item.state, item.Status, item.status].filter(Boolean).join(" ").toLowerCase()`.
   - `running = normalizedRunning === true || normalizedRunning === 1 || normalizedRunning === "true" || normalizedRunning === "1" || /running|active|\bup\b|paused|restarting/.test(state)`.
   - Then `.filter(item => item.id && item.running)` — targets need a non-empty id **and** a running-ish state.
6. **Batched polling loop:** `for (let index = 0; index < targets.length; index += 6)`
   - `throwIfAborted(requestSignal)` at the top of every batch.
   - `batch = targets.slice(index, index + 6)`; all 6 requests run concurrently via `Promise.all`.
   - Per target: `try { result = await getDockerContainerLiveStats(target.id, requestSignal); return { Id: target.id, Name: target.name, stats: result }; } catch (error) { if (requestSignal?.aborted) throw error; return undefined; }` — individual failures are swallowed unless aborted.
   - Successful entries are appended to `stats`, then `onProgress?.({ ret: 0, stats: [...stats], sampled: stats.length, total: targets.length })` fires **once per batch** with a copy of the accumulated array.
7. `payload = { ret: 0, stats, sampled: stats.length, total: targets.length }`; when `targets.length === 0` the callback fires once with this payload; the payload is returned.

Concurrency limit: **6 per batch, batches strictly sequential.** Each stats request carries the 10000 ms timeout of `getDockerContainerLiveStats`.

### 5.5 Images — simple wrappers

| Function | Method | Path + query | Body | Timeout |
| --- | --- | --- | --- | --- |
| `listDockerImages(input?: DockerSignalInput)` — async, returns `{ items, raw }` | GET | `images?all=false` | — | 12000 |
| `getDockerImage(id: string)` | GET | `images/{id}` | — | 12000 |
| `pullDockerImage(data: LuckyRecord)` | POST | `images/pull-async` | `data` verbatim | 12000 |
| `tagDockerImage(id: string, repository: string, tag = "latest")` | POST | `images/{id}/tag` | `{"repository": repository, "tag": tag}` | 12000 |
| `searchDockerImages(term: string)` | POST | `images/search` | `{"term": term, "limit": 25}` | 12000 |
| `getDockerImageHistory(id: string)` | GET | `images/{id}/history` | — | 12000 |
| `buildDockerImage(data: LuckyRecord)` | POST | `images/build` | `data` verbatim | 600000 |
| `pullDockerImageSync(image: string, tag = "latest")` | POST | `images/pull` | `{"image": image, "tag": tag}` | 600000 |
| `pushDockerImage(image: string, tag = "latest")` | POST | `images/push` | `{"image": image, "tag": tag}` | 600000 |
| `buildDockerImageFromGit(data: LuckyRecord)` | POST | `images/build-from-git` | `data` verbatim | 600000 |
| `buildDockerImageFromZip(data: LuckyRecord \| FormData)` | POST | `images/build-from-zip` | `data` verbatim (JSON **or** multipart) | 600000 |
| `importDockerImage(data: LuckyRecord)` | POST | `images/import` | `data` verbatim | 300000 |
| `loadDockerImage(data: LuckyRecord \| FormData)` | POST | `images/load` | `data` verbatim (JSON **or** multipart) | 300000 |
| `getDockerImageTags(id: string)` | GET | `images/{id}/tags` | — | 12000 |
| `getDockerImageFilesystem(id: string, path = "/")` | GET | `images/{id}/filesystem?path={path}` | — | 12000 |

Image upgrade / digest bookkeeping:

| Function | Method | Path + query | Body | Timeout |
| --- | --- | --- | --- | --- |
| `checkDockerImageUpgrade(imageRef: string, signal?: AbortSignal)` | POST | `images/upgrade-check` | `{"image_ref": imageRef}` | 45000 |
| `getDockerImageUpgradeStatus(imageRef = "", signal?: AbortSignal)` | GET | `images/upgrade-status` plus `?image_ref={imageRef}` **only when `imageRef` is non-empty** (params argument is `undefined` otherwise) | — | 12000 |
| `dismissDockerImageUpgrade(imageRef: string, imageId = "")` | POST | `images/upgrade-dismiss` | `{"image_ref": imageRef, "image_id": imageId}` (empty string is sent) | 12000 |
| `clearDockerImageUpgradeStatus()` | DELETE | `images/upgrade-status` | — | 12000 |
| `removeDockerSavedDigest(imageId: string)` | POST | `images/remove-saved-digest` | `{"image_id": imageId}` | 12000 |
| `backupDockerImageTag(imageRef: string)` | POST | `images/backup-tag` | `{"image_ref": imageRef}` | 12000 |
| `getDockerImageContainers(imageRef: string, signal?: AbortSignal)` | GET | `images/containers?image_ref={imageRef}` | — | 12000 |
| `pullDockerImageWithBackup(imageRef: string, backupTag = true, architecture = "")` | POST | `images/pull-with-backup` | `{"image_ref": imageRef, "backup_tag": backupTag, "architecture": architecture}` | 600000 |
| `upgradeDockerImageContainers(imageRef: string, upgradeCompose = true, upgradeStandalone = true, containerIds: unknown = null)` | POST | `images/upgrade-containers` | `{"image_ref": imageRef, "upgrade_compose": upgradeCompose, "upgrade_standalone": upgradeStandalone, "container_ids": containerIds}` — `container_ids` defaults to JSON `null` | 300000 |

`listDockerImages` unwrapping: `{ items: list(raw, ["images", "list"]), raw }`.

### 5.6 `removeDockerImage(reference: string, force = false)` — two-branch routing

```ts
const isImageId = /^(?:sha256:)?[a-f\d]{12,}$/i.test(reference);
```
- **Tag branch** — taken when `!isImageId && (reference.includes("/") || reference.includes(":"))`:
  `DELETE images/remove?tag={reference}&force={force}&noprune=false` (query order: `tag`, `force`, `noprune`; no body).
- **ID branch** — everything else:
  `DELETE images/{encodeURIComponent(reference)}?force={force}&noprune=false` (query order: `force`, `noprune`; no body).
- Both branches use the 12000 ms default timeout and carry no abort signal.

### 5.7 `removeDockerImages(references: string[], onProgress?)` — batch delete

```ts
export async function removeDockerImages(
  references: string[],
  onProgress?: (progress: LuckyRecord) => void,
): Promise<LuckyRecord>
```
1. `items = [...new Set(references.map(item => item.trim()).filter(Boolean))]` — trim, drop empties, de-duplicate preserving first-seen order.
2. `runDockerBatch(items, reference => removeDockerImage(reference, false), { onProgress: ... })` — **concurrency 4** (the default), `force = false`, no cancellation hook.
3. Progress payload per completed item: `{ completedCount, totalCount, removedCount: succeeded.length, failedCount: failed.length }`.
4. Result:
```ts
{ ret: 0, removed: succeeded /* string[] */, failed /* {item,error}[] */,
  removedCount, failedCount,
  completedCount: succeeded.length + failed.length, totalCount: items.length }
```
Never throws for partial failure; individual error strings come from `runDockerBatch` (`error.message` or `请求失败`).
### 5.8 `checkDockerImagesUpgrade(imageRefs: string[], onProgress?, signal?)`

```ts
export async function checkDockerImagesUpgrade(
  imageRefs: string[],
  onProgress?: (progress: LuckyRecord) => void,
  signal?: AbortSignal,
): Promise<LuckyRecord>
```
1. `items` = trimmed, non-empty, de-duplicated `imageRefs`.
2. `results: LuckyRecord[] = []` accumulates `{ imageRef, result: response }` for each success, where `response` is the `checkDockerImageUpgrade(imageRef, signal)` envelope (POST `images/upgrade-check`, 45000 ms).
3. `runDockerBatch(..., { concurrency: 4, isCancelled: () => Boolean(signal?.aborted), onProgress })`.
4. Progress payload per completed item:
```ts
{ ret: 0, checked: [...results], failed: progress.failed,
  checkedCount: progress.succeeded.length, failedCount: progress.failed.length,
  completedCount: progress.completedCount, totalCount: progress.totalCount,
  inProgress: progress.completedCount < progress.totalCount }
```
5. **Error escalation:** `if (!result.succeeded.length && result.failed.length) throw new Error(result.failed[0].error)` — total failure rethrows the first error message.
6. Result:
```ts
{ ret: 0, checked: results, failed: result.failed,
  checkedCount, failedCount, completedCount, totalCount: items.length, inProgress: false }
```

### 5.9 `scanUnusedDockerImages(imageIds: string[], onProgress?, signal?)`

```ts
export async function scanUnusedDockerImages(
  imageIds: string[],
  onProgress?: (progress: LuckyRecord) => void,
  signal?: AbortSignal,
): Promise<LuckyRecord>
```
Makes **no dedicated request per image** — it derives usage from one container snapshot (and optionally one image snapshot).

1. `items` = trimmed, non-empty, de-duplicated `imageIds`. Accumulators `unused: string[]`, `used: string[]`, `failed: { item: string; error: string }[]`.
2. `report()` = `onProgress?.(unusedImageScanResult(unused, used, failed, items.length))`.
3. `failAll(error)` pushes `{ item, error }` for **every** item, calls `report()`, and returns the result object.
4. Empty input → `report()` then return `unusedImageScanResult(unused, used, failed, 0)` (note `totalCount: 0`).
5. `throwIfAborted(signal)`; `containerResult = await listDockerContainers(signal)`; `throwIfAborted(signal)`. On throw: if `signal?.aborted` rethrow, else `failAll(error.message || "Unable to read Docker containers")`.
6. `containerArray = findArray(containerResult.raw, ["containers", "list"])`; if falsy → `failAll("Unable to determine image usage safely")`.
7. `containerRows = containerArray.filter(isRecord)`; `hasUnknownContainerRows = containerRows.length !== containerArray.length`.
8. `usageRows = containerRows.map(item => collectDockerImageAliases(item))` (i.e. `imageRecord = false` → container key sets).
9. `hasUnidentifiedContainer = usageRows.some(row => !row.hasIdentity)`.
10. `hasReferenceOnlyContainer = usageRows.some(row => row.hasIdentity && !row.hasImageId)`.
11. `hasImageIdCandidate = items.some(item => [...dockerImageAliases(item)].some(alias => alias.startsWith("id:")))`.
12. `imageIndexError = "Unable to map image IDs to container references"` (default). When `hasReferenceOnlyContainer && hasImageIdCandidate`, try `listDockerImages(signal)`, then `findArray(imageResult.raw, ["images", "list"])`; if the array exists and `every(isRecord)`, build `imageIndex = array.map(item => ({ aliases: collectDockerImageAliases(item, true).aliases }))`. On throw: rethrow when `signal?.aborted`, otherwise replace `imageIndexError` with `error.message` when non-empty.
13. For each `imageId` of `items`, in order:
    - `throwIfAborted(signal)`.
    - `aliases = dockerImageAliases(imageId)`.
    - `matchingImage = imageIndex?.find(image => dockerImageAliasesIntersect(aliases, image.aliases))`; when found, **merge all of that image's aliases into `aliases`** (so a bare image ID can match a container that only names a tag).
    - `isUsed = usageRows.some(row => dockerImageAliasesIntersect(aliases, row.aliases))`.
    - Classification, in this exact order:
      1. `isUsed` → `used.push(imageId)`.
      2. `hasUnknownContainerRows || hasUnidentifiedContainer` → `failed.push({ item: imageId, error: "Unable to determine image usage safely" })`.
      3. `hasReferenceOnlyContainer && hasImageIdCandidate && (!imageIndex || !matchingImage)` → `failed.push({ item: imageId, error: imageIndexError })`.
      4. else → `unused.push(imageId)`.
    - `report()` after **every** image (progressive callback, one per item).
14. Return `unusedImageScanResult(unused, used, failed, items.length)`.

Error strings (English, verbatim): `"Unable to read Docker containers"`, `"Unable to determine image usage safely"`, `"Unable to map image IDs to container references"`.

### 5.10 Compose

| Function | Method | Path + query | Body | Timeout |
| --- | --- | --- | --- | --- |
| `listDockerComposeProjects(input?: DockerSignalInput)` — async, returns `{ items, raw }` | GET | `compose/projects` | — | 12000 |
| `createDockerCompose(data: DockerComposeCreateInput, signal?: AbortSignal)` | POST | `compose/up-async` | `data` verbatim (`project_name?`, `working_dir`, `compose_content`, `config_file_name`, `build?`) | 12000 |
| `runDockerComposeAction(action: "up"\|"down"\|"start"\|"stop"\|"restart", data: LuckyRecord)` | POST | `compose/{action}` | `data` verbatim | **300000 when `action === "up"`, otherwise 120000** |
| `getDockerComposeLogs(name: string, data: LuckyRecord = {})` | POST | `compose/{name}/logs` | `data` verbatim, default `{}` (an empty JSON object is still sent) | 12000 |
| `readDockerComposeConfig(projectPath: string)` | POST | `compose/config` | `{"project_path": projectPath}` | 12000 |
| `readDockerComposeFile(workingDirectory: string, filename: string)` | POST | `compose/read-file` | `{"working_dir": workingDirectory, "filename": filename}` | 12000 |
| `updateDockerComposeConfig(projectPath: string, content: string)` | POST | `compose/update-config` | `{"project_path": projectPath, "content": content}` | 12000 |
| `discoverDockerCompose(scanPath: string)` | POST | `compose/discover` | `{"scan_path": scanPath}` | 12000 |
| `backupDockerCompose(projectPath: string, projectName: string)` | POST | `compose/backup` | `{"project_path": projectPath, "project_name": projectName}` | 600000 |
| `listDockerComposeBackups(projectName: string)` | GET | `compose/{projectName}/backups` | — | 12000 |
| `uploadDockerComposeBackup(projectName: string, data: FormData)` | POST | `compose/{projectName}/backups/upload` | multipart `FormData` | 600000 |
| `downloadDockerComposeBackup(projectName: string, backup: string)` | GET | `compose/{projectName}/backups/download.tar.gz?backup={backup}` | — | 600000, `responseType: "blob"` |
| `removeDockerComposeBackup(projectName: string, backup: string)` | DELETE | `compose/{projectName}/backups` | `{"backup": backup}` — **JSON body on a DELETE**, not a query param | 12000 |
| `clearDockerComposeBackups(projectName: string)` | DELETE | `compose/{projectName}/backups/all` | — | 12000 |
| `restoreDockerComposeBackup(projectName: string, backup: string)` | POST | `compose/{projectName}/backups/restore` | `{"backup": backup}` | 600000 |
| `restoreDockerCompose(data: FormData)` | POST | `compose/restore` | multipart `FormData` | 600000 |
| `cancelDockerComposeBackup(projectName: string)` | DELETE | `compose/{projectName}/backup/cancel` | — | 12000 |
| `getDockerComposeBackupStatus(input?: DockerSignalInput)` | GET | `compose/backup/status` | — | 12000 |
| `getDockerComposeContainers(projectName: string, projectPath = "")` | GET | `compose/{projectName}/ps?path={projectPath}` — params are `{ path: projectPath \|\| undefined }`, so an empty `projectPath` produces **no query string at all** | — | 12000 |
| `getDockerComposeContainersForCron()` | GET | `compose/containers-for-cron` | — | 12000 |
| `readDockerComposeDockerfile(projectPath: string)` | POST | `compose/dockerfile` | `{"project_path": projectPath}` | 12000 |
| `updateDockerComposeDockerfile(projectPath: string, content: string)` | POST | `compose/update-dockerfile` | `{"project_path": projectPath, "content": content}` | 12000 |

`listDockerComposeProjects` unwrapping: `{ items: list(raw, ["projects", "list", "composeProjects"]), raw }`.
### 5.11 Networks and volumes

| Function | Method | Path + query | Body | Timeout |
| --- | --- | --- | --- | --- |
| `listDockerNetworks(input?: DockerSignalInput)` — async, returns `{ items, raw }` | GET | `networks` | — | 12000 |
| `createDockerNetwork(data: LuckyRecord)` | POST | `networks` | `data` verbatim | 12000 |
| `removeDockerNetwork(id: string)` | DELETE | `networks/{id}` | — | 12000 |
| `listDockerVolumes(input?: DockerSignalInput)` — async, returns `{ items, raw }` | GET | `volumes` | — | 12000 |
| `createDockerVolume(data: LuckyRecord)` | POST | `volumes` | `data` verbatim | 12000 |
| `removeDockerVolume(name: string)` | DELETE | `volumes/{name}` | — | 12000 |
| `backupDockerVolume(name: string)` | POST | `volumes/{name}/backup` | — (no body) | 600000 |
| `listDockerVolumeBackups(name: string)` | GET | `volumes/{name}/backups` | — | 12000 |
| `uploadDockerVolumeBackup(name: string, data: FormData)` | POST | `volumes/{name}/backups/upload` | multipart `FormData` | 600000 |
| `exportDockerVolume(name: string)` | GET | `volumes/export?name={name}` | — | 600000, `responseType: "blob"` |
| `importDockerVolume(data: FormData)` | POST | `volumes/import` | multipart `FormData` | 600000 |
| `restoreDockerVolumeBackup(name: string, backup: string)` | POST | `volumes/{name}/backups/restore` | `{"backup": backup}` | 600000 |
| `removeDockerVolumeBackup(name: string, backup: string)` | DELETE | `volumes/{name}/backups` | `{"backup": backup}` — **JSON body on a DELETE** | 12000 |
| `cancelDockerVolumeBackup(name: string)` | DELETE | `volumes/{name}/backup/cancel` | — | 12000 |
| `getDockerVolumeBackupStatus(input?: DockerSignalInput)` | GET | `volumes/backup/status` | — | 12000 |

Unwrapping: networks → `list(raw, ["networks", "list"])`; volumes → `list(raw, ["volumes", "list"])`.

### 5.12 Tasks

| Function | Method | Path + query | Body | Timeout |
| --- | --- | --- | --- | --- |
| `listDockerTasks(input?: DockerSignalInput)` — async, returns `{ items, raw }` | GET | `tasks` | — | 12000 |
| `getDockerTask(id: string, input?: DockerSignalInput)` | GET | `tasks/{id}` | — | 12000 |
| `removeDockerTask(id: string)` | DELETE | `tasks/{id}` | — | 12000 |
| `clearDockerTasks()` | DELETE | `tasks` | — | 12000 |

Unwrapping: `list(raw, ["tasks", "list"])`.

#### `waitForDockerTask(id: string, options: DockerTaskWaitOptions = {})` — polling loop

- `timeoutMs = options.timeoutMs ?? 10 * 60 * 1000` (600000 ms).
- `intervalMs = Math.max(500, options.intervalMs ?? 1200)` — floor of 500 ms, default 1200 ms.
- `startedAt = Date.now()`; `lastTask` remembers the most recent poll result.
- `while (Date.now() - startedAt < timeoutMs)`:
  1. `throwIfAborted(options.signal)`.
  2. `task = await getDockerTask(id, options.signal)` (GET `tasks/{id}`, 12000 ms per poll).
  3. `lastTask = task`; `options.onProgress?.(task)` — fires on **every** poll, including the terminal one.
  4. `status = String(preferredTaskScalar(task, ["status", "state"]) ?? "").trim().toLowerCase()`.
  5. Success set `["completed", "complete", "success", "succeeded"]` → **return `task`**.
  6. Failure set `["failed", "error", "cancelled", "canceled"]` → `detail = preferredTaskScalar(task, ["error", "message", "output", "msg"])`; `throw new Error(String(detail || `Docker 任务 ${status}`))` — e.g. `Docker 任务 failed` when no detail.
  7. `await waitForDockerPoll(intervalMs, options.signal)` — interruptible sleep; an abort during the sleep rejects with `AbortError` / `"Request cancelled"`.
- On timeout: `status = lastTask ? String(preferredTaskScalar(lastTask, ["status", "state"]) ?? "") : ""` (**not** trimmed/lower-cased here), then
  `throw new Error(`Docker 任务等待超时（任务 ID：${id}${status ? `，状态：${status}` : ""}），任务可能仍在后台执行`)`.
- The elapsed check happens **before** each poll, so a task is polled at least once and the loop can overshoot `timeoutMs` by up to one request + one interval.
### 5.13 System, config, registry

| Function | Method | Path + query | Body | Timeout |
| --- | --- | --- | --- | --- |
| `getDockerInfo(input?: DockerSignalInput)` | GET | `info` | — | 12000 |
| `getDockerVersion(input?: DockerSignalInput)` | GET | `version` | — | 12000 |
| `getDockerDiskUsage(input?: DockerSignalInput)` | GET | `disk-usage` | — | 12000 |
| `getDockerMonitorStatus(input?: DockerSignalInput)` | GET | `monitor/status` | — | 12000 |
| `getDockerSelfContainerInfo(input?: DockerSignalInput)` | GET | `self-container` | — | 12000 |
| `getDockerConfig(input?: DockerSignalInput)` | GET | `config` | — | 12000 |
| `updateDockerConfig(data: LuckyRecord)` | POST | `config` | `data` verbatim | 12000 |
| `getDockerLogs(pageSize = 200, page = 1, input?: DockerSignalInput)` | GET | `logs?pageSize={pageSize}&page={page}` | — | 12000 |
| `getDockerRegistryMirrors(input?: DockerSignalInput)` | GET | `registry/mirrors` | — | 12000 |
| `addDockerRegistryMirror(mirror: string)` | POST | `registry/mirrors` | `{"mirror": mirror}` | 12000 |
| `removeDockerRegistryMirror(mirror: string)` | DELETE | `registry/mirrors` | `{"mirror": mirror}` — **JSON body on a DELETE** | 12000 |

### 5.14 `getDockerOverview(input?: DockerSignalInput)` — fan-out aggregate

`signal = resolveDockerSignal(input)`. Six requests run **concurrently** via `Promise.all`, each wrapped in `optionalDockerRequest(..., signal)` so a single failure yields `undefined` instead of rejecting (unless the signal aborted, which rethrows):
`getDockerInfo(signal)`, `listDockerContainers(signal)`, `listDockerImages(signal)`, `listDockerComposeProjects(signal)`, `listDockerNetworks(signal)`, `listDockerVolumes(signal)`.

Then `throwIfAborted(signal)`.
If **all six** are falsy → `throw new Error("Docker 总览接口均不可用")`.

Derivations:
- `info = findRecord(infoRaw ?? {}, ["info", "dockerInfo", "data", "result"])` — falls back to the whole payload.
- `containers = containersResult?.items ?? []`; `images = imagesResult?.items ?? []`.
- `fallbackContainers = findScalar(info, ["Containers", "containers"])`; `fallbackImages = findScalar(info, ["Images", "images"])`.
- `fallbackContainerCount = Number(fallbackContainers)`; `fallbackImageCount = Number(fallbackImages)`.
- `imageSize = images.reduce((total, image) => total + (Number(findScalar(image, ["Size", "size", "VirtualSize", "virtualSize"])) || 0), 0)`.

Returned object (plain object, **not** a Lucky envelope — no `ret`):
```ts
{
  info,                                  // LuckyRecord
  containers,                            // LuckyListItem[]
  containersAvailable: Boolean(containersResult),
  containerCount: containersResult ? containers.length
    : (fallbackContainers === undefined || !Number.isFinite(fallbackContainerCount)) ? undefined : fallbackContainerCount,
  imageCount: imagesResult ? images.length
    : (fallbackImages === undefined || !Number.isFinite(fallbackImageCount)) ? undefined : fallbackImageCount,
  imageSize: imagesResult ? imageSize : undefined,
  composeCount: composeResult?.items.length,   // number | undefined
  networkCount: networksResult?.items.length,
  volumeCount: volumesResult?.items.length,
}
```
Swift note: `containerCount`, `imageCount`, `imageSize`, `composeCount`, `networkCount`, `volumeCount` are all optional — model them as `Int?` / `Double?` and keep the "unavailable vs zero" distinction.
### 5.15 `getDockerMaintenanceStatus(input?: DockerSignalInput)`

`signal = resolveDockerSignal(input)`. Seven requests are created **eagerly** (all in flight before any await), keyed in this exact order:

| Result key | Request |
| --- | --- |
| `labels` | `getDockerLabels(signal)` → GET `labels` |
| `containerGroups` | `getDockerContainerGroups(signal)` → GET `container-groups` |
| `collapsedStates` | `getDockerContainerGroupCollapsedStates(signal)` → GET `container-groups/collapsed/states` |
| `orderMapping` | `getDockerContainerOrderMapping(signal)` → GET `containers/order-mapping` |
| `imageUpgrades` | `getDockerImageUpgradeStatus("", signal)` → GET `images/upgrade-status` (no query) |
| `composeBackup` | `getDockerComposeBackupStatus(signal)` → GET `compose/backup/status` |
| `volumeBackup` | `getDockerVolumeBackupStatus(signal)` → GET `volumes/backup/status` |

`results = await Promise.allSettled(...)`, then `throwIfAborted(signal)`.
Return type `Record<string, LuckyRecord>`: fulfilled entries carry the response envelope; rejected entries become `{ error: reason instanceof Error ? reason.message : "接口请求失败" }`. Never throws for individual failures.

### 5.16 `pruneDocker(data: LuckyRecord)` — with a dangling-filter compatibility fallback

1. Happy path: `return await callDockerApi("prune", "POST", data)` — POST `prune`, body is `data` verbatim, 12000 ms.
2. On error, rethrow immediately unless **all three** hold:
   - `error instanceof Error`, **and**
   - `/invalid filter\s+['"]?dangling/i.test(error.message)` (case-insensitive; the quote character is optional), **and**
   - `data.images === true`.
3. Fallback path:
   - `remaining = { ...data, images: false }`.
   - `hasOtherCleanup = ["containers", "networks", "volumes", "build_cache"].some(key => remaining[key] === true)`.
   - `system = hasOtherCleanup ? await callDockerApi("prune", "POST", remaining) : {}` — a second POST `prune` only when something else still needs pruning.
   - `images = await pruneUnusedDockerImages()` (see §4: lists images, scans usage, then force-deletes the unused set with concurrency 4).
   - Return `{ ret: 0, msg: "已使用兼容模式清理未使用镜像", system, images }`.

## 6. Verbatim user-facing messages produced inside this module

| Message | Origin |
| --- | --- |
| `不支持的容器文件操作：{operation}` (with `空` substituted for an empty operation) | `runDockerContainerFileOperation` client-side validation |
| `请求失败` | `runDockerBatch` fallback when the caught value is not an `Error` |
| `Docker 任务 {status}` | `waitForDockerTask`, terminal failure state without a detail field |
| `Docker 任务等待超时（任务 ID：{id}，状态：{status}），任务可能仍在后台执行` | `waitForDockerTask` timeout (the `，状态：{status}` clause is omitted when the status string is empty) |
| `Docker 总览接口均不可用` | `getDockerOverview` when all six sub-requests failed |
| `接口请求失败` | `getDockerMaintenanceStatus` when a rejection reason is not an `Error` |
| `已使用兼容模式清理未使用镜像` | `pruneDocker` fallback result `msg` |
| `未知镜像` | `pruneUnusedDockerImages` placeholder in `skipped`, one per image with no usable id |
| `Request cancelled` (`error.name = "AbortError"`) | `throwIfAborted` and `waitForDockerPoll` |
| `Unable to read Docker containers` | `scanUnusedDockerImages` container-list failure |
| `Unable to determine image usage safely` | `scanUnusedDockerImages` unusable/ambiguous container rows |
| `Unable to map image IDs to container references` | `scanUnusedDockerImages` default image-index error |
## 7. Behaviour a Swift port must reproduce

**Binary downloads (`responseType: "blob"`, 4 endpoints)** — `downloadDockerContainerFile`, `exportDockerContainer`, `downloadDockerComposeBackup`, `exportDockerVolume`. All use a 600000 ms timeout and rely on `luckyFetch`'s blob branch: `Accept: application/octet-stream, application/json;q=0.8, text/plain;q=0.6`, small (≤ 1 MiB) bodies that happen to parse as JSON are treated as an envelope instead of a file, error bodies ≤ 64 KiB become the error message, and the success payload carries `contentType`, `filename` (from `Content-Disposition`, `filename*=UTF-8''` preferred and percent-decoded) and `byteLength`.

**Multipart uploads (`FormData`, 6 entry points)** — `uploadDockerContainerFile`, `uploadDockerComposeBackup`, `restoreDockerCompose`, `uploadDockerVolumeBackup`, `importDockerVolume`, plus `buildDockerImageFromZip` / `loadDockerImage` when passed `FormData`. The body must be sent as-is with **no** explicit `Content-Type` so the boundary is generated. Timeouts: 600000 ms except `loadDockerImage` (300000 ms).

**JSON bodies on DELETE (4 endpoints)** — `removeDockerComposeBackup`, `removeDockerVolumeBackup`, `removeDockerRegistryMirror`, and `runDockerContainerFileOperation("delete", ...)`. `URLSession` allows this, but the body must not be dropped. By contrast `removeDockerContainer`, `removeDockerContainerGroup` and `removeDockerImage` put their arguments in the **query string**.

**Polling loops** — `waitForDockerTask` only (600000 ms budget, `max(500, 1200)` ms interval, `onProgress` per poll, interruptible sleep). Everything else is one-shot.

**Batching / concurrency** — `refreshDockerContainerStats` (batches of 6, sequential batches, progress after each batch); `runDockerBatch` (4 concurrent workers over a shared cursor, progress after every item, cooperative `isCancelled` check before consuming each item) used by `removeDockerImages`, `checkDockerImagesUpgrade` and `pruneUnusedDockerImages`; `getDockerOverview` (6 parallel, failures tolerated); `getDockerMaintenanceStatus` (7 parallel via `allSettled`).

**Progressive callbacks** — `refreshDockerContainerStats(onProgress)`, `removeDockerImages(onProgress)`, `checkDockerImagesUpgrade(onProgress)`, `scanUnusedDockerImages(onProgress)`. Each emits a snapshot (copied arrays) and the terminal value is also returned from the function. In Swift these map naturally onto `AsyncStream` or an escaping `@Sendable` closure that must be callable from a task context.

**Abort handling** — three distinct shapes: (a) `DockerSignalInput` = `AbortSignal | { signal?: AbortSignal }`, resolved by `resolveDockerSignal`; (b) `DockerContainerInput` = `LuckyListItem[] | { items?, signal? } | AbortSignal`, resolved by `resolveDockerContainerInput`; (c) a bare `signal?: AbortSignal` parameter (`checkDockerImageUpgrade`, `getDockerImageUpgradeStatus`, `getDockerImageContainers`, `createDockerCompose`, `checkDockerImagesUpgrade`, `scanUnusedDockerImages`, `refreshDockerContainerStats`). Cancellation is checked before work starts, between batches, and between polls; a swallowed per-item error is rethrown when the signal is aborted. Swift equivalent: `Task.checkCancellation()` at the same points.

**Query-string encoding** — insertion order is preserved, `undefined`/`null`/`""` are dropped, `false` and `0` are **kept** and rendered as `false` / `0`, non-strings go through `JSON.stringify` before `encodeURIComponent`. Non-obvious consequences: `removeDockerContainer(id)` sends `?force=false&remove_volumes=false`; `listDockerImages` sends `?all=false`; `getDockerComposeContainers(name)` sends no query at all.

**Cache-buster** — every request URL gets `_=<nonce>` appended (`&` if a query already exists), where the nonce is `String(Date.now()).slice(0, -1)` followed by `(digit sum) % 8`.

**Response unwrapping** — six list endpoints use `list()`/`findArray()` with the key arrays in §4. `findArray` restarts its BFS per candidate key (so key priority beats depth), matches keys case-insensitively, and additionally follows arrays found under `data` / `result` / `response` / `payload`. A Swift port needs the same tolerant traversal over a `JSONValue` tree; a fixed `Codable` shape will not reproduce it.
## 8. Timeout matrix (ms)

| Timeout | Functions |
| --- | --- |
| 10000 | `getDockerContainerLiveStats` |
| 12000 (default) | everything not listed below |
| 15000 | `getAllDockerContainerStats` |
| 45000 | `checkDockerImageUpgrade` (and therefore `checkDockerImagesUpgrade`) |
| 60000 | `checkDockerContainerUpgrade` |
| 120000 | `runDockerComposeAction` for `down`/`start`/`stop`/`restart` |
| 300000 | `editDockerContainer`, `commitDockerContainer`, `copyDockerContainer`, `upgradeDockerContainer`, `switchDockerContainerVersion`, `importDockerImage`, `loadDockerImage`, `upgradeDockerImageContainers`, `runDockerComposeAction("up")` |
| 600000 | `runDockerContainerFileOperation` for the four (de)compress operations, `uploadDockerContainerFile`, `downloadDockerContainerFile`, `exportDockerContainer`, `buildDockerImage`, `pullDockerImageSync`, `pushDockerImage`, `buildDockerImageFromGit`, `buildDockerImageFromZip`, `pullDockerImageWithBackup`, `backupDockerCompose`, `uploadDockerComposeBackup`, `downloadDockerComposeBackup`, `restoreDockerComposeBackup`, `restoreDockerCompose`, `backupDockerVolume`, `uploadDockerVolumeBackup`, `exportDockerVolume`, `importDockerVolume`, `restoreDockerVolumeBackup` |
| 600000 (loop budget, not a request timeout) | `waitForDockerTask` |

## 9. Alphabetical index of the 123 exported callables

`addDockerRegistryMirror`, `backupDockerCompose`, `backupDockerImageTag`, `backupDockerVolume`, `buildDockerImage`, `buildDockerImageFromGit`, `buildDockerImageFromZip`, `callDockerApi`, `cancelDockerComposeBackup`, `cancelDockerVolumeBackup`, `checkDockerContainerUpgrade`, `checkDockerImageUpgrade`, `checkDockerImagesUpgrade`, `clearDockerComposeBackups`, `clearDockerImageUpgradeStatus`, `clearDockerTasks`, `commitDockerContainer`, `copyDockerContainer`, `createDockerCompose`, `createDockerContainer`, `createDockerContainerGroup`, `createDockerNetwork`, `createDockerVolume`, `discoverDockerCompose`, `dismissDockerImageUpgrade`, `downloadDockerComposeBackup`, `downloadDockerContainerFile`, `editDockerContainer`, `exportDockerContainer`, `exportDockerVolume`, `getAllDockerContainerStats`, `getDockerComposeBackupStatus`, `getDockerComposeContainers`, `getDockerComposeContainersForCron`, `getDockerComposeLogs`, `getDockerConfig`, `getDockerContainer`, `getDockerContainerComposeConfig`, `getDockerContainerGroupCollapsedStates`, `getDockerContainerGroupCount`, `getDockerContainerGroups`, `getDockerContainerLiveStats`, `getDockerContainerLogs`, `getDockerContainerOrderMapping`, `getDockerContainerProcesses`, `getDockerContainerStats`, `getDockerDiskUsage`, `getDockerImage`, `getDockerImageContainers`, `getDockerImageFilesystem`, `getDockerImageHistory`, `getDockerImageTags`, `getDockerImageUpgradeStatus`, `getDockerInfo`, `getDockerLabelContainers`, `getDockerLabels`, `getDockerLogs`, `getDockerMaintenanceStatus`, `getDockerMonitorStatus`, `getDockerOverview`, `getDockerRegistryMirrors`, `getDockerSelfContainerInfo`, `getDockerTask`, `getDockerVersion`, `getDockerVolumeBackupStatus`, `importDockerImage`, `importDockerVolume`, `listDockerComposeBackups`, `listDockerComposeProjects`, `listDockerContainers`, `listDockerImages`, `listDockerNetworks`, `listDockerTasks`, `listDockerVolumeBackups`, `listDockerVolumes`, `loadDockerImage`, `pruneDocker`, `pullDockerImage`, `pullDockerImageSync`, `pullDockerImageWithBackup`, `pushDockerImage`, `readDockerComposeConfig`, `readDockerComposeDockerfile`, `readDockerComposeFile`, `refreshDockerContainerStats`, `removeDockerComposeBackup`, `removeDockerContainer`, `removeDockerContainerGroup`, `removeDockerContainerLabel`, `removeDockerImage`, `removeDockerImages`, `removeDockerNetwork`, `removeDockerRegistryMirror`, `removeDockerSavedDigest`, `removeDockerTask`, `removeDockerVolume`, `removeDockerVolumeBackup`, `renameDockerContainer`, `reorderDockerContainerGroups`, `restoreDockerCompose`, `restoreDockerComposeBackup`, `restoreDockerVolumeBackup`, `runDockerComposeAction`, `runDockerContainerAction`, `runDockerContainerFileOperation`, `scanUnusedDockerImages`, `searchDockerImages`, `setDockerContainerGroup`, `setDockerContainerGroupCollapsed`, `setDockerContainerLabel`, `switchDockerContainerVersion`, `tagDockerImage`, `updateDockerComposeConfig`, `updateDockerComposeDockerfile`, `updateDockerConfig`, `updateDockerContainerGroup`, `updateDockerContainerOrderMapping`, `upgradeDockerContainer`, `upgradeDockerImageContainers`, `uploadDockerComposeBackup`, `uploadDockerContainerFile`, `uploadDockerVolumeBackup`, `waitForDockerTask`.
