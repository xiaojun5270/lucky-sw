# Docker 屏幕 · 行为规格 (1:1 SwiftUI 移植用)

Sources:
- `C:\Users\xiaoj\Desktop\lucky\app\docker.tsx` (3951 lines; this document covers **L2053–L3951** exhaustively, plus symbols
  resolved from L1–L2052 that are directly rendered by that range)
- `C:\Users\xiaoj\Desktop\lucky\src\components\docker-overview.tsx` (1051 lines; covered in full)

All colour names below are semantic keys of `useAppTheme()` (`colors.primary`, `colors.primarySoft`, `colors.success`,
`colors.successBg`, `colors.danger`, `colors.dangerBg`, `colors.warning`, `colors.warningBg`, `colors.cyan`, `colors.cyanBg`,
`colors.text`, `colors.subtext`, `colors.card`, `colors.mutedCard`, `colors.muted`, `colors.border`, `colors.rowBorder`,
`colors.shadow`, `colors.disabled`, `colors.page`, `colors.mode`). Literal `#fff` is used for text/icons on `colors.primary`.

---

## 1. Screen shell, views, tabs

`DockerView = "containers" | "images" | "compose" | "networks" | "volumes" | "tasks" | "overview" | "settings" | "logs"`

`tabs` (order is the tab-bar order; `[key, 中文标签, icon]`):

| key | label | icon |
|---|---|---|
| `containers` | `容器` | Container |
| `images` | `镜像` | Image |
| `compose` | `Compose` | Workflow |
| `networks` | `网络` | Network |
| `volumes` | `数据卷` | Database |
| `tasks` | `任务` | Activity |
| `overview` | `总览` | Gauge |
| `settings` | `设置` | Settings2 |
| `logs` | `日志` | FileText |

`dockerListViews = ["containers","images","compose","networks","volumes","tasks","logs"]`
→ `isDockerListView = dockerListViews.includes(view)`.

`<Page>` props: `title="Docker"`, `subtitle="容器、镜像与 Compose 管理"`, `icon=Container`, `safeTop={false}`,
`contentMaxWidth = view === "overview" ? 1120 : 820`, `scrollable={!isDockerListView}`, `showHeader={!isDockerListView}`,
`refreshing={pageRefreshing}`, `onRefresh={refreshDockerView}`.

`pageRefreshing = active.isFetching || (view === "settings" && maintenance.isFetching)`.

Initial state: `view = requestedView ?? "containers"`, `search = requestedSearch ?? ""`, `dockerLogPage = 1`, `output = ""`.

---

## 2. Queries, gating flags, refresh intervals (all numeric constants)

Gating flags (`isScreenFocused` = navigation focus, `appIsActive` = AppState active):
- `overviewActive = view === "overview" && isScreenFocused && appIsActive`
- `containerStatsActive = (view === "overview" || view === "containers") && isScreenFocused && appIsActive`
- `dockerLogsActive = view === "logs" && isScreenFocused && appIsActive`

| query | key | enabled when | staleTime | refetchInterval | retry |
|---|---|---|---|---|---|
| containers | `["docker","containers"]` | `view==="containers"` | — | — | — |
| iconLibrary | `["iconlib","icons"]` | `view==="containers"` | `30*60*1000` (30 min) | — | — |
| images | `["docker","images"]` | `view==="images"` | — | — | — |
| compose | `["docker","compose"]` | `view==="compose"` | — | — | — |
| networks | `["docker","networks"]` | `view==="networks"` | — | — | — |
| volumes | `["docker","volumes"]` | `view==="volumes"` | — | — | — |
| tasks | `["docker","tasks"]` | `view==="tasks"` | — | — | — |
| overview | `["docker","overview"]` | `overviewActive` | `30_000` | `60_000` | — |
| containerStats | `["docker","container-stats"]` | `containerStatsActive` | `3_000` | `5_000` | `false` |
| liveContainerStats | `["docker","container-stats-live"]` | `liveStatsNeeded` | `10_000` | `15_000` | `false` |
| config | `["docker","config"]` | `view==="settings"` | — | — | — |
| mirrors | `["docker","mirrors"]` | `view==="settings"` | — | — | — |
| maintenance | `["docker","maintenance"]` | `view==="settings"` | — | — | — |
| logs | `["docker","logs",dockerLogPage]` | `dockerLogsActive` | — | `15000` | — |

All intervals have `refetchIntervalInBackground: false`.

`logs` query calls `getDockerLogs(200, dockerLogPage, signal)` → **page size 200**.
`composeLogs()` calls `getDockerComposeLogs(name, { tail: 200 })` → **tail 200**.

`liveStatsNeeded = containerStatsActive && (Boolean(containerStats.error) || (containerStats.isSuccess &&
runningContainerCount > cachedContainerStatRows.length))` — i.e. the expensive per-container live-stats sweep only runs
when the cheap bulk endpoint failed or returned fewer rows than there are running containers.

`active` = the query matching the current view (`containers/images/compose/networks/volumes/tasks/overview/logs`, else `config`).
`source` = `active.data?.items` for the six list views, `[]` for anything else.

---

## 3. Derived state / selectors

- `searchableSource = source.map(item => ({ item, text: JSON.stringify(item).toLowerCase() }))`
- `filtered = searchableSource.filter(({text}) => !word || text.includes(word)).map(({item}) => item)`
  where `word = deferredSearch.trim().toLowerCase()` — **search is a whole-record JSON substring match**, not field-scoped.
- `dockerLogLines = lines(logs.data)` (flattens log payloads into `string[]`).
- `imageEntries = (images.data?.items ?? []).map((item,i) => ({ item, id: keyOf(item,i), references: imageReferences(item),
  searchText: searchText(item) }))`
- `visibleImageEntries` = `imageEntries` filtered by the same deferred search word against `searchText`.
- `imageIdSet = new Set(imageEntries.map(e => e.id))`
- `validSelectedImageIds = selectedImageIds.filter(id => imageIdSet.has(id))`
- `selectedImageSet = new Set(validSelectedImageIds)`
- `visibleImageIds = visibleImageEntries.map(e => e.id)`
- `allVisibleImagesSelected = visibleImageIds.length > 0 && visibleImageIds.every(id => selectedImageSet.has(id))`
- `imageSelectionBusy = mutation.isPending || unusedImageScanChecking`
- `imageActionBusy = imageSelectionBusy || imageUpgradeChecking`
- `containerStatsSource = liveStatsNeeded ? [containerStats.data, liveContainerStats.data, progressiveContainerStats]
  : [containerStats.data]` (an **array** is passed to `dockerStatRows`, which deep-walks it)
- `containerStatRows = liveStatsNeeded ? dockerStatRows(containerStatsSource, statsContainerItems ?? []) : cachedContainerStatRows`
- `containerStatsByKey`: `Map<string, DockerStatRow>` where **each row is inserted twice** — under `row.key` and under `row.name`.
- Effect: whenever `imageIdSet` changes → bump `unusedImageScanRequestRef`, abort in-flight scan, prune `selectedImageIds`
  down to still-existing ids.
- Effect: leaving the `images` view resets selection mode / selected ids.

Local UI state: `editor?`, `composeCreatorOpen`, `composeCreateProgress?`, `detail?`, `imageSelectionMode`,
`selectedImageIds: string[]`, `imageUpgradeChecking`, `unusedImageScanChecking`,
`unusedImageScanProgress?: {completed,total}`, `imageDeleteProgress?: {completed,total}`,
`containerMenu?: {key,name,running,paused}`, `imageMenu?: {key,name}`, `imageToolsOpen`, `dockerUpload?`,
`output: unknown`, `localError: string`, `localNotice: string`, `progressiveContainerStats?`.

---

## 4. String helpers used by the rendered rows (resolved from L493–L699)

```ts
pick(item, keys, fallback = "")      // first key whose value is string|number → String(v);
                                     // array → v.map(String).join(", "); else fallback
keyOf(item, index) = pick(item, ["Id","ID","id","Name","name","Key","key"], String(index))
searchText(item)   = JSON.stringify(item).toLowerCase()  (throws → "")
imageReferences(item)                // scans ["RepoTags","Tags","repoTags","tags","Name","name"],
                                     // arrays as-is / strings split on ",", trims,
                                     // drops anything matching /<none>/i, de-dupes
bytes(value)                         // units ["B","KB","MB","GB","TB"], base 1024,
                                     // 0/NaN → "--", index 0 → 0 decimals, else 2 decimals
compactDockerBytes(value, available) // !available → "N/A"; value>0 → bytes(value); else "0 B"
```

`containerStatus(item, running, paused)` — produces the badge text on container rows:
1. `paused` → `已暂停`
2. `raw = pick(item, ["Status","status","State","state"], running ? "运行中" : "已停止")`
3. `!running` → `/exit|stop|dead/i.test(raw) ? "已停止" : raw`
4. `duration = raw.match(/Up\s+(.+?)(?:\s+\(|$)/i)?.[1]`; if none → `运行中`
5. else localise: `seconds?`→`秒`, `minutes?`→`分钟`, `hours?`→`小时`, `days?`→`天`, `weeks?`→`周`, `months?`→`个月`
   (each `.replace` is **first-match only**), then return `` `运行: ${localized}` ``.

`imagePushValue(name)` → takes `name.split(",")[0].trim()`; if `lastIndexOf(":") > lastIndexOf("/")`
→ `{ image: ref.slice(0,lastColon), tag: ref.slice(lastColon+1) || "latest" }`,
else `{ image: ref === "<none>" ? "" : ref, tag: "latest" }`.

`pickComposeField(item, keys)` → first key that is a non-blank trimmed string, or a number → `String(n)`, else `""`.
`composePayload(item)` →
```ts
{ project_name: pickComposeField(item, ["name","Name","project_name","projectName","ProjectName"]),
  project_path: pickComposeField(item, ["path","Path","project_path","projectPath","ProjectPath","working_dir","WorkingDir"]) }
```

`composeProjectError(error, projectPath)` — if the message matches
`/目录不存在|directory\s+(?:does not exist|not found)|no such (?:file|directory)/i`, replace it with:
`Lucky 服务无法访问项目目录：${projectPath}。请将宿主机 Compose 目录按相同绝对路径读写挂载到 Lucky 容器。`
Fallback message when the error is not an `Error`: `Compose 操作失败`.

`nested(payload, keys)` — BFS over the payload for the first case-insensitive key match whose value is a plain object.
`composeConfigText(payload)` — extracts the Compose/Dockerfile text out of the response envelope.

---

## 5. Row-level sub-components (resolved from L734–L872)

### 5.1 `ContainerArtwork({ item, icons, running, size = 44 })`
- `icon = containerIcon(item, icons)`; `external = /^(https?:|data:|file:)/i.test(icon)`.
- Remote URL when not external: `${baseUrl без trailing "/"}/api/iconlib/icon?path=${encodeURIComponent(icon)}`,
  sent with header `{"Lucky-Admin-Token": token}` (omitted when external or no token).
- Container box: `width=size`, `height=size`, `borderRadius = max(10, round(size*0.26))`, centred.
- **Fallback** (no icon *or* image load failed): background `running ? colors.primarySoft : colors.mutedCard`,
  glyph `Container` at `round(size*0.45)`, colour `running ? colors.primary : colors.disabled`.
- **Image** case: background `colors.mutedCard`, `overflow: hidden`, image `contentFit="contain"`,
  `cachePolicy="memory-disk"`, `transition=120`ms, image frame `size-6` square.
- `failed` resets to `false` whenever the URI changes.
- Used at `size={48}` in the containers list.

### 5.2 `ContainerStatsGrid({ stats?: DockerStatRow })`
Three tiles, each tile holds two metrics side-by-side. Outer: `row`, `flexWrap`, `gap 6`.
Tile: `flexGrow 1, flexShrink 1, flexBasis 145, minWidth 132, minHeight 54, padding 8, borderRadius 12,
backgroundColor colors.mutedCard`, `row`, centred vertically.
Metric cell: `flex 1, paddingHorizontal 4`, second cell gets `borderLeftWidth 1 / borderLeftColor colors.rowBorder`, `gap 4`.
Label row: icon `size 12, strokeWidth 2.2` + label `colors.subtext, fontSize 10, lineHeight 12, fontWeight "600"`, centred, `gap 4`.
Value: `colors.text, fontSize 11, lineHeight 14, fontWeight "700", tabular-nums, textAlign center`, `numberOfLines 1`,
`adjustsFontSizeToFit`, `minimumFontScale 0.75`, `width "100%"`.

| tile | metric 1 | metric 2 |
|---|---|---|
| 1 | `CPU` · icon Cpu · colors.primary | `内存` · icon MemoryStick · colors.success |
| 2 | `下载` · icon Download · colors.cyan | `上传` · icon Upload · colors.warning |
| 3 | `读取` · icon HardDriveDownload · colors.subtext | `写入` · icon HardDriveUpload · colors.subtext |

Values: CPU = `stats.hasCpu ? stats.cpu.toFixed(1)+"%" : "-"`;
memory = `hasMemoryPercent ? memoryPercent.toFixed(1)+"%" : hasMemory ? compactDockerBytes(memory,true) : "-"`;
the other four = `compactDockerBytes(value ?? 0, hasX === true)` → so a missing metric renders `N/A`, a present zero renders `0 B`.

### 5.3 `IconButton({ icon, label, color, disabled = false, fluid = false, basis = 88, onPress })`
`flexGrow/flexShrink = fluid ? 1 : 0`, `flexBasis = fluid ? basis : "auto"`, `minWidth 64`, `minHeight 42`,
`paddingHorizontal 10`, `borderRadius 12`, `borderWidth 1 / colors.border`, `backgroundColor colors.mutedCard`,
row + centred, `gap 5`, `opacity = disabled ? 0.5 : pressed ? 0.65 : 1`.
Icon `size 16` in `color`; label `color`, `fontSize 11`, `fontWeight "700"`, `numberOfLines 1`. `accessibilityLabel = label`.

### 5.4 `ContainerCommandButton({ icon, label, color, onPress })`
`flex 1`, `minHeight 42`, `borderRadius 12`, `borderWidth 1 / colors.border`, `backgroundColor colors.mutedCard`,
row + centred, `gap 5`, `opacity pressed ? 0.55 : 1`, `transform scale(pressed ? 0.985 : 1)`.
Icon `size 15`; label `fontSize 12`, `fontWeight "700"`, `numberOfLines 1`.

---

## 6. Navigation chrome (L2434–L2477)

### `renderDockerNavigation(includePageHeader: boolean)` → `<View style={{gap:16}}>`
1. If `includePageHeader`: `<PageHeader title="Docker" subtitle="容器、镜像与 Compose 管理" icon={Container}
   refreshing={pageRefreshing} onRefresh={refreshDockerView} />`
2. `<ResponsiveTabBar tabs={tabs} value={view} onChange={selectDockerView} />`
3. If `localError`: `<ErrorState message={localError} />`
4. If `localNotice`: notice pill — `minHeight 40, paddingHorizontal 12, borderRadius 10,
   backgroundColor colors.successBg, justifyContent center`; text `colors.success, fontSize 12, fontWeight "700"`.
5. If `active.error`: `<ErrorState message={active.error.message} retry={() => active.refetch()} />`
6. If `!containerStatRows.length && liveStatsNeeded && liveContainerStats.error && (view==="overview"||view==="containers")`:
   `<ErrorState message="容器统计暂时不可用" retry={() => { containerStats.refetch(); liveContainerStats.refetch(); }} />`
7. If `view ∈ {containers,images,compose,networks,volumes,tasks}`:
   `<SearchField value={search} onChangeText={setSearch} placeholder={`搜索${tabs.find(([k])=>k===view)?.[1] ?? ""}`} />`
   → placeholders are exactly `搜索容器`, `搜索镜像`, `搜索Compose`, `搜索网络`, `搜索数据卷`, `搜索任务`
   (no space between `搜索` and the label).

### `renderDockerListHeader(content)`
`<View style={{gap:16, paddingBottom:16}}>{renderDockerNavigation(true)}{content}</View>` — used as every FlatList's
`ListHeaderComponent`, so the header/tab-bar/search scroll with the list.

### `refreshDockerView()`
`active.refetch()`; if `view ∈ {overview, containers}` → `containerStats.refetch()` and (if `liveStatsNeeded`)
`liveContainerStats.refetch()`; if `view === "settings"` → `mirrors.refetch()` + `maintenance.refetch()`.

### `selectDockerView(key)`
`setView(key)`, `setSearch("")`, `setOutput("")`; if `key === "logs"` also `setDockerLogPage(1)`.

### Confirmation dialog primitive `danger(title, message, action)`
`Alert.alert(title, message, [{ text: "取消", style: "cancel" }, { text: "继续", style: "destructive", onPress: action }])`
→ **every** confirmation in this screen uses the buttons `取消` / `继续`. Swift port: two-button alert, destructive on 继续.

### Shared FlatList config (all six list views + logs)
`keyboardShouldPersistTaps="handled"`, `removeClippedSubviews={Platform.OS==="android"}`,
`style={{flex:1,width:"100%"}}`, `contentContainerStyle={{ paddingBottom: 98, flexGrow: data.length ? 0 : 1 }}`,
`ItemSeparatorComponent` = 12 px spacer (logs view has none).
`initialNumToRender`/`maxToRenderPerBatch`: containers 8, images 8, compose 6, networks 8, volumes 8, tasks 10, logs 30.
`windowSize`: 7 everywhere except logs (9).

---

## 7. Detail / download flows (L2036–L2072, L2314–L2410)

`detailRequestRef` is a monotonically-increasing request id; **every** async detail write is guarded by
`detailRequestRef.current === requestId`, so stale responses are dropped.

- `closeDetail()` → bump `detailRequestRef`, `imageUpgradeAbortRef.current?.abort()`, `setDetail(undefined)`.
- `openDetail(title, request)` → `setDetail({title, loading:true})`; success → `{title, value}`;
  failure → `{title, error: message ?? "读取详情失败"}`.
- `downloadDockerResource(title, fallbackName, request, nativePath?, nativeMethod = "GET")`
  → `setDetail({ title, loading:true, status: "正在下载" })`.
  On native (`Platform.OS !== "web"`) **and** `nativePath` present → `downloadDockerPathToDevice(nativePath, fallbackName, nativeMethod)`;
  otherwise → `saveDockerBinary(await request(), fallbackName)`. Failure message fallback `下载失败`.
- `inspect(kind, key)` — titles: `container → 容器详情`, `image → 镜像详情`, `task → 任务详情`.
- `containerLogs(key)` → `setOutput(await getDockerContainerLogs(key))`, `setDockerLogPage(1)`, `setView("logs")`.
  Failure → `localError = message ?? "读取日志失败"`.
- `composeLogs(name)` → clears `localError`/`localNotice`, `setOutput(await getDockerComposeLogs(name,{tail:200}))`,
  `setDockerLogPage(1)`, `setView("logs")`. Failure → `读取 Compose 日志失败`.
- `editComposeConfig(projectPath)` → read + `composeConfigText`; if empty text throw `接口未返回 Compose 配置内容`;
  opens editor `{ type:"compose-config", title:"编辑 Compose 配置", key: projectPath,
  value: { project_path, content } }`. Errors pass through `composeProjectError(error, projectPath)`.
- `editComposeDockerfile(projectPath)` → empty text throws `接口未返回 Dockerfile 内容`; editor
  `{ type:"compose-dockerfile", title:"编辑 Dockerfile", key: projectPath, value:{ project_path, content } }`;
  failure → `读取 Dockerfile 失败`.
- `editContainer(key)` → `getDockerContainer(key)`, editor `{ type:"container-edit", title:"编辑容器", key,
  value: nested(result, ["container","data"]) }`; failure → `读取容器配置失败`.
- `updateContainer(key, name)` → `checkDockerContainerUpgrade(key)`, `value = {...nested(result,
  ["config","upgrade","result","data"])}` with `ret` and `msg` **deleted**; editor
  `{ type:"container-upgrade", title: `更新容器 ${name}`, key, value }`; failure → `检查容器更新失败`.

---

## 8. Image batch-selection flows (L2073–L2239)

- `toggleImageSelection(id)` — no-op while `imageActionBusy`; toggles membership in `selectedImageIds`.
- `toggleImageSelectionMode()` — no-op while `mutation.isPending || imageUpgradeChecking`. If an unused-image scan is
  running, bump `unusedImageScanRequestRef` + abort it. Toggles mode; **leaving** the mode clears `selectedImageIds`.
- `toggleVisibleImageSelection()` — no-op if `imageActionBusy` or no visible ids. Starts from the current selection
  pruned to existing ids; if *all* visible ids are already selected → remove them all, else → add them all.
- `selectUnusedImages()` — guarded by `imageActionBusy || unusedImageScanRunningRef.current || !visibleImageIds.length`.
  Sets `unusedImageScanProgress = {completed:0, total: visibleImageIds.length}`, clears error/notice, runs
  `scanUnusedDockerImages(visibleImageIds, onProgress, signal)` with an `AbortController`.
  Progress callback keeps `{completed: Number(progress.completedCount)||0, total: Number(progress.totalCount)||total}`.
  Result → `unusedIds = result.unused.map(String).filter(id => imageIdSet.has(id))`, `usedCount`, `failedCount`.
  `setSelectedImageIds(unusedIds)`.
  - If `!unusedIds.length && !usedCount && failedCount` → `localError = firstFailure || "未能确认镜像使用情况"`
    (firstFailure = `String(result.failed[0].error ?? "")`).
  - Else → `localNotice = `已选择 ${unusedIds.length} 个未使用镜像，${usedCount} 个正在使用${failedCount ? `，${failedCount} 个无法确认` : ""}``
  - Catch → `localError = message ?? "检查镜像使用情况失败"`.
  Finally: clear running flag, clear controller, `setUnusedImageScanChecking(false)`, `setUnusedImageScanProgress(undefined)`.
- `detectImageUpgrades()` — guarded by `imageActionBusy || imageUpgradeRunningRef.current`.
  `targets = imageEntries.filter(e => selectedImageSet.has(e.id))`;
  `references = [...new Set(targets.map(e => e.references[0]).filter(Boolean))]`  ← **only the first tag of each image**.
  If `references.length === 0` → `localError = validSelectedImageIds.length ? "所选镜像没有可检测的标签" : "请先选择需要检测的镜像"`.
  Title: `` `检测镜像升级 · ${references.length} 个主标签` ``.
  Initial detail: `{ title, loading:true, status: `正在检测 0/${references.length}`,
  value: { completedCount:0, totalCount: references.length, checkedCount:0, failedCount:0, inProgress:true } }`.
  Progress → `status: `正在检测 ${completed}/${total}``, `loading: completed < total`, `value: progress`.
  Then `{title, value: checked, loading:true, status:"正在读取升级状态"}`, then
  `getDockerImageUpgradeStatus("", signal)` → `{title, value:{...checked, imageUpgrades}}`;
  status read failure → `{title, value:{...checked, statusError: message ?? "读取升级状态失败"}}`.
  Whole-flow failure → `{title, error: message ?? "检测镜像升级失败"}`.
  Finally: invalidate `["docker","maintenance"]`.
- `showImageUpgradeStatus()` — title `镜像升级状态`, `status "正在读取升级状态"`,
  result `{ title, value: { imageUpgrades } }`, failure `读取升级状态失败`.
- `removeSelectedImages()` — no-op while `imageActionBusy`; if nothing valid selected →
  `localError = "请先选择要删除的镜像"`. Otherwise confirm:
  title `批量删除镜像`, message `` `确定删除已选择的 ${n} 个镜像？正在使用的镜像会自动跳过。` ``
  → `mutate({ type:"images-remove-batch", value:{ ids: validSelectedImageIds } })`.

---

## 9. File pickers (L2240–L2313)

### `chooseDockerArchive(type: "image-build-zip" | "image-load")`
MIME filter: `image-build-zip` → `["application/zip","application/x-zip-compressed"]`;
`image-load` → `["application/x-tar","application/gzip","application/x-gzip","application/octet-stream"]`.
`copyToCacheDirectory: true`, `multiple: false`. Cancel → silent return. Stores
`dockerUpload = { uri, name, mimeType, file }`, then opens:

| type | editor title | initial `value` |
|---|---|---|
| `image-build-zip` | `从 ZIP 构建镜像` | `{ file_name: asset.name, file_uri: asset.uri, tag: "", dockerfile: "Dockerfile", build_args: {}, no_cache: false }` |
| `image-load` | `加载镜像归档` | `{ file_name: asset.name, file_uri: asset.uri }` |

Failure → `localError = message ?? "选择文件失败"`.

### `chooseDockerUpload(type, key, title, fields)`
`type ∈ {"container-file-upload","compose-backup-upload","compose-restore","volume-backup-upload","volume-import"}`.
MIME filter: `container-file-upload` → `"*/*"`; all others →
`["application/gzip","application/x-gzip","application/x-tar","application/octet-stream"]`.
Special case: for `volume-import` with a blank `fields.volume_name`, derive it from the file name:
`asset.name.replace(/(?:\.tar\.gz|\.tgz)$/i, "").replace(/-backup-\d{8}-\d{6}$/i, "")`.
Then `setEditor({ type, title, key, value: { ...nextFields, file_name: asset.name, file_uri: asset.uri } })`.
Failure → `localError = message ?? "选择上传文件失败"`.

Call sites and their `fields`:
| type | key | title | fields |
|---|---|---|---|
| `container-file-upload` | container id | `` `上传文件 · ${containerMenu.name}` `` | `{ path: "/" }` |
| `compose-backup-upload` | project name | `` `上传 Compose 备份 · ${name}` `` | `{ project_name: name }` |
| `compose-restore` | project name | `` `恢复 Compose 配置 · ${name}` `` | `{ target_path: payload.project_path, project_name: name, auto_start: true, config_file_name: "" }` |
| `volume-backup-upload` | volume name | `` `上传数据卷备份 · ${name}` `` | `{}` |
| `volume-import` | `""` | `导入数据卷` | `{ volume_name: "", driver: "local" }` |

Closing the `DockerFormEditor` clears `dockerUpload` when `editor.type` is any of
`["image-build-zip","image-load","container-file-upload","compose-backup-upload","compose-restore","volume-backup-upload","volume-import"]`.

---

## 10. View: `containers` (L2493–L2614)

Header content (inside `renderDockerListHeader`):
1. `<SectionHeader icon={Container} title="容器" meta={`${filtered.length} 项`} />`
2. Primary CTA: `height 46, borderRadius 12, backgroundColor colors.primary`, row centred, `gap 7`;
   `Plus` `#fff` `size 17` + text `创建容器` (`#fff`, `fontWeight "800"`).
   → opens editor `{ type:"container-create", title:"创建容器", value:{ name:"", image:"", config:{} } }`.

Data: `filtered`; `keyExtractor = keyOf(item, index)`; `extraData = containerStatRows`.
Empty state (only when `!containers.isLoading`): `<EmptyState message="暂无容器" icon={Container} />`.

Per-row derivation:
```
key         = keyOf(item, index)
state       = dockerContainerState(item)
paused      = state === "paused"
running     = state === "running" || paused          // ← paused counts as running
name        = pick(item, ["Names","Name","name"], key.slice(0,12))
displayName = name.replace(/^\/+/, "") || name
stats       = containerStatsByKey.get(key) ?? containerStatsByKey.get(displayName)
```

Card: `borderRadius 18, borderWidth 1 / colors.border, backgroundColor colors.card, padding 14, gap 12`,
shadow `colors.shadow`, `shadowOpacity` = 0.055 on ios/web else 0, `shadowRadius 12`, `shadowOffset {0,4}`,
`elevation 2` on android.

Row 1 — pressable (`accessibilityLabel = `打开容器 ${displayName} 操作菜单``, opens `containerMenu`
`{key, name, running, paused}`): `minHeight 54`, row, `gap 11`, `opacity pressed ? 0.62 : 1`.
- `<ContainerArtwork item icons={iconLibrary.data ?? []} running size={48} />`
- Text column (`flex 1, gap 6`):
  - `displayName` — `colors.text, fontSize 15, lineHeight 19, fontWeight "800"`, `numberOfLines 1`, `width "100%"`.
  - Status badge — `alignSelf flex-start, maxWidth "100%", minHeight 24, paddingHorizontal 8, borderRadius 8`,
    background `running ? colors.successBg : colors.mutedCard`, row, `gap 5`; 6×6 dot `borderRadius 3`
    coloured `running ? colors.success : colors.disabled`; text `containerStatus(item, running, paused)` in
    `running ? colors.success : colors.subtext`, `fontSize 10, lineHeight 13, fontWeight "600"`, `numberOfLines 1`.
- Trailing affordance: `34×34, borderRadius 11, backgroundColor colors.mutedCard`, centred `Ellipsis colors.subtext size 18`.

Row 2 — `<ContainerStatsGrid stats={stats} />`.
Row 3 — 1 px divider `colors.rowBorder`.
Row 4 — command buttons (`row, gap 6`), 3 buttons; the first is state-dependent:

| condition | icon | label | colour | action |
|---|---|---|---|---|
| `paused` | Play | `恢复` | colors.success | `mutate({type:"container-unpause", key})` — **no confirm** |
| `!running` | Play | `启动` | colors.success | `mutate({type:"container-start", key})` — **no confirm** |
| else | CircleStop | `停止` | colors.danger | confirm `确认停止` / `` `停止容器 ${name}？` `` → `{type:"container-stop", key}` |
| always | RotateCw | `重启` | colors.primary | confirm `确认重启` / `` `重启容器 ${name}？` `` → `{type:"container-restart", key}` |
| always | UploadCloud | `更新` | colors.cyan | `updateContainer(key, displayName)` (opens `container-upgrade` editor) |

Note the stop/restart confirmations interpolate `name` (raw, may keep a leading `/`), not `displayName`.

---

## 11. View: `images` (L2616–L2871)

### 11.1 Header
1. `<SectionHeader icon={Image} title="镜像列表" meta={`${visibleImageEntries.length} 项`} />`
2. Row (`gap 8`) of two `flex 1, height 44, borderRadius 12` buttons:
   - `拉取` — filled `colors.primary`, `UploadCloud #fff size 16`, label `#fff` `fontWeight "800"`.
     → editor `{ type:"image-pull", title:"拉取镜像", value:{ image:"", tag:"latest", architecture:"" } }`
   - `构建` — outline `borderWidth 1 / colors.primary`, `Wrench colors.primary size 16`, label `colors.primary`.
     → editor `{ type:"image-build", title:"构建镜像", value:{} }`
3. `镜像高级工具` — `height 44, borderRadius 12, borderWidth 1 / colors.border, backgroundColor colors.card`,
   `Wrench colors.text size 16`, label `colors.text fontWeight "800"`, `opacity pressed ? 0.6 : 1`,
   `accessibilityLabel="打开镜像高级工具"` → `setImageToolsOpen(true)`.
4. Row (`gap 8`) of two `flex 1, height 44, borderRadius 12` buttons:
   - Upgrade button — `borderWidth 1 / colors.primary`, `backgroundColor colors.primarySoft`,
     `disabled = imageActionBusy`, `opacity = imageActionBusy ? 0.45 : pressed ? 0.62 : 1`.
     Leading: `ActivityIndicator colors.primary size small` while `imageUpgradeChecking`, else `RefreshCw colors.primary size 16`.
     Label: `imageUpgradeChecking ? "处理中" : validSelectedImageIds.length ? "检测所选" : "升级状态"`.
     `accessibilityLabel = validSelectedImageIds.length ? `检测已选择的 ${n} 个镜像升级` : "查看镜像升级状态"`.
     Action: `validSelectedImageIds.length ? detectImageUpgrades() : showImageUpgradeStatus()`.
   - Selection-mode toggle — border `imageSelectionMode ? colors.primary : colors.border`,
     background `imageSelectionMode ? colors.primarySoft : colors.card`,
     `disabled = mutation.isPending || imageUpgradeChecking`, `opacity` `0.45` when disabled else `pressed ? 0.62 : 1`.
     `ListChecks` in `imageSelectionMode ? colors.primary : colors.text`, `size 16`;
     label `imageSelectionMode ? "退出批量" : "批量操作"`; `accessibilityState.selected = imageSelectionMode`.
5. When `imageSelectionMode` — batch panel: `padding 10, borderRadius 14, borderWidth 1 / colors.border,
   backgroundColor colors.mutedCard, gap 8`.
   - Title text `` `已选择 ${validSelectedImageIds.length} 项` `` — `colors.text, fontSize 12, fontWeight "700"`.
   - Row (`gap 8`) of two `flex 1, height 44, paddingHorizontal 10, borderRadius 11, backgroundColor colors.card` buttons:
     - Select-all — `accessibilityRole="checkbox"`, `disabled = !visibleImageIds.length || imageActionBusy`,
       `opacity 0.45` when disabled. `ListChecks colors.primary size 15`; label
       `allVisibleImagesSelected ? "取消全选" : "全选"` (`colors.primary, fontSize 12, fontWeight "700"`).
       `accessibilityLabel = allVisibleImagesSelected ? "取消选择当前显示的全部镜像" : "选择当前显示的全部镜像"`.
     - Unused scan — `disabled` same condition; leading `ActivityIndicator` while `unusedImageScanChecking`
       else `PackageSearch colors.primary size 15`; label =
       `unusedImageScanChecking ? (unusedImageScanProgress ? `${completed}/${total}` : "检查中") : "选择未使用"`.
       `accessibilityLabel = unusedImageScanChecking ? "正在检查未使用镜像" : "选择当前显示的未使用镜像"`.
   - Delete-selected — `width "100%", height 44, paddingHorizontal 10, borderRadius 11`,
     background `validSelectedImageIds.length ? colors.dangerBg : colors.muted`,
     `disabled = !validSelectedImageIds.length || imageActionBusy`,
     `opacity = imageActionBusy && !imageDeleteProgress ? 0.45 : 1`.
     Leading: `ActivityIndicator colors.danger` when `imageDeleteProgress` else
     `Trash2` in `validSelectedImageIds.length ? colors.danger : colors.disabled` `size 15`.
     Label: `imageDeleteProgress ? `删除中 ${completed}/${total}` : "删除所选"`, colour
     `validSelectedImageIds.length ? colors.danger : colors.disabled`, `fontSize 12, fontWeight "700"`.
     `accessibilityLabel = `删除已选择的 ${n} 个镜像``.

### 11.2 Image rows
Data `visibleImageEntries`; `keyExtractor = entry.id`;
`extraData = `${imageSelectionMode}:${validSelectedImageIds.join(",")}:${imageActionBusy}``.
Empty (when `!images.isLoading`): `<EmptyState message="暂无镜像" icon={Image} />`.

Per row: `name = pick(item, ["RepoTags","Tags","Name"], "<none>")`, `key = entry.id`,
`selected = selectedImageSet.has(key)`. Wrapped in `<Panel>`.

Header line: `minHeight 48`, row, `gap 10`.
- If `imageSelectionMode`: 44×44 checkbox hit area (`opacity 0.45` when `imageActionBusy`, `disabled` likewise),
  inner box `24×24, borderRadius 8, borderWidth 1.5`, border `selected ? colors.danger : colors.border`,
  background `selected ? colors.danger : colors.card`, tick `Check #fff size 15 strokeWidth 2.6` when selected.
  `accessibilityRole="checkbox"`, `accessibilityLabel = `选择镜像 ${name}``.
- `<IconTile icon={Image} color={colors.warning} background={colors.warningBg} size={38} iconSize={19} />`
- Text column: name — `colors.text, fontSize 14, lineHeight 18, fontWeight "800"`, `numberOfLines 2`;
  subtitle — `` `${key.slice(0,16)} · ${bytes(item.Size)}` ``, `colors.subtext, fontSize 11, marginTop 3`.

When **not** in selection mode: 1 px `colors.rowBorder` divider, then a wrapping row (`gap 7`) of four `fluid` IconButtons:

| icon | label | colour | action |
|---|---|---|---|
| Search | `详情` | colors.text | `inspect("image", key)` → detail titled `镜像详情` |
| Pencil | `标记` | colors.primary | editor `{ type:"image-tag", title:"添加镜像标签", key, value:{ repository:"", tag:"latest" } }` |
| Ellipsis | `更多` | colors.cyan | `setImageMenu({ key, name })` |
| Trash2 | `删除` | colors.danger | confirm `确认删除` / `` `删除镜像 ${name}？` `` → `mutate({ type:"image-remove", key: name !== "<none>" ? name.split(",")[0] : key })` |

In selection mode the action row is hidden entirely.

---

## 12. View: `compose` (L2873–L3171)

Header:
1. `<SectionHeader icon={Workflow} title="Compose 项目" meta={`${filtered.length} 项`} />`
2. Wrapping row (`gap 8`) of two buttons, each `flexGrow 1, flexBasis 150, height 46, borderRadius 12`:
   - `创建 Compose` — filled `colors.primary`, `Plus #fff size 17`, `disabled = mutation.isPending`,
     `opacity = mutation.isPending ? 0.45 : pressed ? 0.7 : 1`. On press: `mutation.reset()`, clear `localError`
     and `localNotice`, `setComposeCreateProgress(undefined)`, `setComposeCreatorOpen(true)`.
   - `扫描项目` — `borderWidth 1 / colors.primary`, `backgroundColor colors.primarySoft`, `Search colors.primary size 17`,
     `opacity pressed ? 0.65 : 1` → editor `{ type:"compose-discover", title:"发现 Compose 项目", value:{ scan_path:"" } }`.

Row identity: `payload = composePayload(item)`;
`key = [payload.project_name, payload.project_path].filter(Boolean).join(":") || keyOf(item, index)`;
`name = payload.project_name || key`. Same expression is used for `keyExtractor`.
Empty (when `!compose.isLoading`): `<EmptyState message="暂无 Compose 项目" icon={Workflow} />`.

Card (`<Panel>`): header row (`gap 9`) with `<IconTile icon={Workflow} size={40} iconSize={20} />` (default tile colours),
`name` in `colors.text fontWeight "800"`, and `payload.project_path` in `colors.subtext, fontSize 11`, `numberOfLines 1`.

Action grid — a single wrapping row (`gap 7`) of **16** `fluid` IconButtons (default `basis 88`), every one
`disabled={mutation.isPending}`, in this exact order:

| # | icon | label | colour | confirm | result |
|---|---|---|---|---|---|
| 1 | Play | `启动` | success | — | `{type:"compose-start", value: payload}` |
| 2 | CircleStop | `停止` | danger | `确认停止` / `` `停止 Compose 项目 ${name}？` `` | `{type:"compose-stop", value: payload}` |
| 3 | RotateCw | `重启` | primary | — | `{type:"compose-restart", value: payload}` |
| 4 | FileText | `日志` | cyan | — | `composeLogs(name)` |
| 5 | Save | `备份` | warning | `确认备份` / `` `备份 Compose 项目 ${name}？` `` | `{type:"compose-backup", value: payload}` |
| 6 | Archive | `备份列表` | text | — | `openDetail(`Compose 备份 · ${name}`, () => listDockerComposeBackups(name))` |
| 7 | Download | `下载备份` | cyan | — | editor `{type:"compose-backup-download", title:`下载 Compose 备份 · ${name}`, value:{ project_name: name, backup:"" }}` |
| 8 | Trash2 | `清空备份` | danger | `清空 Compose 备份` / `` `确定删除项目 ${name} 的全部备份吗？` `` | `{type:"compose-backups-clear", value:{ project_name: name }}` |
| 9 | Upload | `上传备份` | cyan | — | `chooseDockerUpload("compose-backup-upload", name, `上传 Compose 备份 · ${name}`, { project_name: name })` |
| 10 | RotateCw | `恢复备份` | warning | — | editor `{type:"compose-backup-restore", title:`恢复 Compose 备份 · ${name}`, value:{ project_name: name, backup:"" }}` |
| 11 | Trash2 | `删除备份` | danger | — | editor `{type:"compose-backup-remove", title:`删除 Compose 备份 · ${name}`, value:{ project_name: name, backup:"" }}` |
| 12 | CircleStop | `取消备份` | danger | `取消备份` / `` `取消 Compose 项目 ${name} 的备份任务？` `` | `{type:"compose-backup-cancel", value:{ project_name: name }}` |
| 13 | Pencil | `编辑配置` | primary | — | `editComposeConfig(payload.project_path)` |
| 14 | FileText | `读取文件` | text | — | editor `{type:"compose-read-file", title:`读取 Compose 文件 · ${name}`, value:{ project_path: payload.project_path, file_path:"docker-compose.yml" }}` |
| 15 | RotateCw | `恢复配置` | warning | — | `chooseDockerUpload("compose-restore", name, `恢复 Compose 配置 · ${name}`, { target_path: payload.project_path, project_name: name, auto_start: true, config_file_name: "" })` |
| 16 | FileText | `Dockerfile` | primary | — | `editComposeDockerfile(payload.project_path)` |

---

## 13. View: `networks` (L3173–L3253)

Header: `<SectionHeader icon={Network} title="Docker 网络" meta={`${filtered.length} 项`} />` plus one filled CTA
(`height 46, borderRadius 12, colors.primary`, `Plus #fff size 17`, label `创建网络` `#fff` `fontWeight "800"`)
→ editor `{ type:"network-create", title:"创建网络", value:{ Name:"", Driver:"bridge", Options:{}, IPAM:{} } }`.

Empty (when `!networks.isLoading`): `<EmptyState message="暂无 Docker 网络" icon={Network} />`.

Row (`<Panel>`), single wrapping row `alignItems center, gap 10`:
- `<IconTile icon={Network} color={colors.cyan} background={colors.cyanBg} size={38} iconSize={19} />`
- `name = pick(item, ["Name","name"], keyOf(item,index))` in `colors.text fontWeight "800"`
- subtitle `` `${pick(item,["Driver"])} · ${pick(item,["Scope"])}` `` in `colors.subtext, fontSize 11`
  (both parts fall back to `""`, so a missing pair renders as a bare `" · "`)
- one non-fluid `IconButton` Trash2 `删除` colors.danger → confirm `确认删除` / `` `删除网络 ${name}？` ``
  → `{ type:"network-remove", key: keyOf(item,index) }`

---

## 14. View: `volumes` (L3255–L3442)

Header:
1. `<SectionHeader icon={Database} title="数据卷" meta={`${filtered.length} 项`} />`
2. `创建数据卷` — filled `colors.primary`, `height 46, borderRadius 12`, `Plus #fff size 17`
   → editor `{ type:"volume-create", title:"创建数据卷", value:{ Name:"", Driver:"local", DriverOpts:{}, Labels:{} } }`
3. `导入数据卷` — `minHeight 44, borderRadius 12, borderWidth 1 / colors.primary, backgroundColor colors.primarySoft`,
   `Upload colors.primary size 17` → `chooseDockerUpload("volume-import", "", "导入数据卷", { volume_name:"", driver:"local" })`

Empty (when `!volumes.isLoading`): `<EmptyState message="暂无数据卷" icon={Database} />`.

Row (`<Panel>`): `name = pick(item, ["Name","name"], keyOf(item,index))`.
Header line `minHeight 48`, row, `gap 10`:
- `<IconTile icon={Database} color={colors.warning} background={colors.warningBg} size={38} iconSize={19} />`
- name — `colors.text, fontSize 13, lineHeight 17, fontWeight "800"`, `numberOfLines 2`
- subtitle — `` `${pick(item,["Driver"],"local")} · ${pick(item,["Mountpoint"])}` ``,
  `colors.subtext, fontSize 11, lineHeight 15, marginTop 3`, `numberOfLines 2`
Then a 1 px `colors.rowBorder` divider and a wrapping row (`gap 7`) of **8** IconButtons, all `fluid` with `basis={120}`:

| # | icon | label | colour | confirm | result |
|---|---|---|---|---|---|
| 1 | Save | `备份` | primary | — | `{type:"volume-backup", key: name}` |
| 2 | Search | `备份列表` | text | — | `openDetail(`备份列表 · ${name}`, () => listDockerVolumeBackups(name))` |
| 3 | Download | `导出` | cyan | — | `downloadDockerResource(`导出数据卷 · ${name}`, `${name}.tar.gz`, () => exportDockerVolume(name), `/api/docker/volumes/export?name=${encodeURIComponent(name)}`)` |
| 4 | Upload | `上传备份` | cyan | — | `chooseDockerUpload("volume-backup-upload", name, `上传数据卷备份 · ${name}`, {})` |
| 5 | RotateCw | `恢复备份` | warning | — | editor `{type:"volume-restore", title:"恢复数据卷备份", key: name, value:{ backup:"" }}` |
| 6 | Trash2 | `删除备份` | danger | — | editor `{type:"volume-backup-remove", title:`删除数据卷备份 · ${name}`, key: name, value:{ backup:"" }}` |
| 7 | CircleStop | `取消备份` | danger | `取消备份` / `` `取消数据卷 ${name} 的备份任务？` `` | `{type:"volume-backup-cancel", key: name}` |
| 8 | Trash2 | `删除` | danger | `确认删除` / `` `删除数据卷 ${name}？` `` | `{type:"volume-remove", key: name}` |

Note: volume mutations key off the **name**, not `keyOf`.

---

## 15. View: `tasks` (L3444–L3524)

Header:
1. `<SectionHeader icon={Activity} title="后台任务" meta={`${filtered.length} 项`} />`
2. `清空任务` — `minHeight 44, borderRadius 12, borderWidth 1 / colors.danger, backgroundColor colors.dangerBg`,
   `Trash2 colors.danger size 16`, label `colors.danger fontWeight "800"`
   → confirm `清空任务` / `删除全部 Docker 任务记录？` → `{ type:"tasks-clear" }`

Empty (when `!tasks.isLoading`): `<EmptyState message="暂无后台任务" icon={Activity} />`.

Row (`<Panel>`), one wrapping row `alignItems center, gap 9`:
- `<IconTile icon={Activity} size={36} iconSize={18} />` (default tile colours)
- primary text `pick(item, ["Name","Type","Action"], keyOf(item,index))` — `colors.text fontWeight "800"`
- secondary text `pick(item, ["Status","state","Progress"])` — `colors.subtext, fontSize 11`
  (note the lowercase `state` in the middle of an otherwise capitalised list)
- IconButton Search `详情` colors.text → `inspect("task", key)` (detail title `任务详情`)
- IconButton Trash2 `删除` colors.danger → `{ type:"task-remove", key }` — **no confirmation**

---

## 16. View: `overview` (L3526–L3544)

Renders `<DockerOverviewDashboard>` (see §21) inside the scrollable page (not a FlatList) with:
```
data        = overview.data
active      = overviewActive
stats       = containerStatsSource
statsLoading= !containerStatRows.length && (containerStats.isLoading || (liveStatsNeeded && liveContainerStats.isLoading))
statsError  = !containerStatRows.length && liveStatsNeeded && liveContainerStats.error ? "容器统计暂时不可用" : undefined
onSelectView(nextView)      → setView(nextView); setSearch(""); setOutput("")
onSelectContainer(name)     → setView("containers"); setSearch(name); setOutput("")
```
`liveStatus` is **not** passed here, so the dashboard creates its own `useLuckyStatus(active)` websocket.
Tapping a ranking row therefore jumps to the containers tab pre-filtered by container name.

---

## 17. View: `settings` (L3546–L3696)

Vertical stack inside the scrollable page:
1. `<SectionHeader icon={Settings2} title="Docker 设置" />`
2. If `config.data`: `编辑设置` CTA — `height 46, borderRadius 12, colors.primary`, `Settings2 #fff size 17`,
   label `#fff fontWeight "800"` → editor `{ type:"config-save", title:"编辑 Docker 设置",
   value: nested(config.data, ["config","data"]) }`
3. If `maintenance.error`: `<ErrorState message={maintenance.error.message} retry={() => maintenance.refetch()} />`
4. `<SectionHeader icon={Activity} title="维护状态" meta={maintenance.isFetching ? "正在刷新" : "7 个接口"} />`
5. If `maintenance.data`, three panels:
   - **Panel `分组与标签`** (`<SectionHeader icon={Box} title="分组与标签" />`) with
     `<StructuredDataView value={{ labels, containerGroups, collapsedStates, orderMapping }} />` (taken from
     `maintenance.data`), then a row (`gap 8`) of three `flex 1, minHeight 44, borderRadius 12, borderWidth 1` buttons:
     | label | border / bg | icon | editor |
     |---|---|---|---|
     | `添加分组` | primary / primarySoft | Plus 15 | `{type:"group-create", title:"添加容器分组", value:{ Name:"", Key:"" }}` |
     | `编辑分组` | primary / card | Pencil 15 | `{type:"group-update", title:"编辑容器分组", value:{ Name:"", Key:"" }}` |
     | `删除分组` | danger / dangerBg | Trash2 15 | `{type:"group-remove", title:"删除容器分组", value:{ key:"" }}` |
     (labels `fontWeight "700"`, coloured to match the border)
   - **Panel `备份任务`** (`<SectionHeader icon={Database} title="备份任务" />`) with
     `<StructuredDataView value={{ composeBackup, volumeBackup }} />`
   - **Panel `镜像升级`** (`<SectionHeader icon={Image} title="镜像升级" />`) with
     `<StructuredDataView value={maintenance.data.imageUpgrades} />` and a `清除升级状态` button
     (`minHeight 44, borderRadius 12, backgroundColor colors.dangerBg`, `Trash2 colors.danger 15`,
     label `colors.danger fontWeight "700"`) → confirm `清除升级状态` / `确定清除全部镜像升级检查记录吗？`
     → `{ type:"upgrade-status-clear" }`
6. **Panel `Registry Mirrors`** — plain text heading `Registry Mirrors` (`colors.text fontWeight "800"`, no SectionHeader),
   `<StructuredDataView value={mirrors.data?.mirrors ?? mirrors.data?.list ?? []} />`, then a row (`gap 8`) of two
   `flex 1, minHeight 44, borderRadius 12, borderWidth 1` buttons:
   - `添加` — primary border / `colors.primarySoft`, `Plus colors.primary 15`
     → editor `{ type:"mirror-add", title:"添加镜像加速地址", value:{ mirror:"" } }`
   - `删除` — danger border / `colors.dangerBg`, `Trash2 colors.danger 15`
     → editor `{ type:"mirror-remove", title:"删除镜像加速地址", value:{ mirror:"" } }`
7. `清理未使用资源` — `minHeight 46, borderRadius 12, backgroundColor colors.dangerBg`,
   `ShieldAlert colors.danger size 17`, label `colors.danger fontWeight "800"` → editor
   `{ type:"prune", title:"清理 Docker 资源", value:{ containers:true, images:true, networks:true, volumes:false, build_cache:true } }`
   (note `volumes` defaults to **false**).

---

## 18. View: `logs` (L3698–L3762) — two distinct modes

### 18.1 `output` is truthy (container/compose logs just fetched)
A `ScrollView` (`flex 1`, `contentContainerStyle {paddingBottom:98, gap:16}`) containing
`renderDockerNavigation(true)`, `<SectionHeader icon={FileText} title="Docker 日志" />`,
and `<Panel><StructuredDataView value={output} /></Panel>`. No pagination controls in this mode.

### 18.2 `output` empty → paginated daemon log list
`FlatList` over `dockerLogLines` (from the `logs` query, page size 200).
`keyExtractor = `${index}-${line.slice(0,24)}``. `ListHeaderComponent = renderDockerListHeader(<SectionHeader icon={FileText}
title="Docker 日志" />)`. Empty (when `!logs.isLoading`): `<EmptyState message="暂无 Docker 日志" icon={FileText} />`.

Line renderer: selectable `Text`, `colors.text`, `fontFamily "monospace"`, `fontSize 10`, `lineHeight 17`,
`paddingHorizontal 12`, `paddingVertical 7`, `borderTopWidth = index ? 1 : 0` with `colors.rowBorder`,
`backgroundColor colors.card`. **No separator component** — rows butt against each other with the top border as divider.

Footer pager: `minHeight 60, paddingTop 16`, row centred, `gap 12`.
- Prev: `40×40, borderRadius 11`, background `dockerLogPage <= 1 ? colors.muted : colors.primarySoft`,
  `ChevronLeft` coloured `dockerLogPage <= 1 ? colors.disabled : colors.primary` `size 18`,
  `disabled = dockerLogPage <= 1 || logs.isFetching`, `accessibilityLabel="上一页 Docker 日志"`,
  action `setDockerLogPage(p => Math.max(1, p - 1))`.
- Centre label: `` `第 ${dockerLogPage} 页` `` — `colors.subtext, fontSize 12`.
- Next: same box; background/colour keyed on `dockerLogLines.length < 200`;
  `disabled = logs.isFetching || dockerLogLines.length < 200`, `accessibilityLabel="下一页 Docker 日志"`,
  action `setDockerLogPage(p => p + 1)`. **Threshold: a full page is exactly 200 lines.**

---

## 19. Overlays (L3764–L3947)

Render order at the end of the page: `DockerDetailViewer` → `ComposeCreateEditor` → `DockerFormEditor` →
`DockerActionSheet`(image tools) → `DockerActionSheet`(image menu) → `DockerActionSheet`(container menu).

### 19.1 `ComposeCreateEditor` wiring
- `busy = mutation.isPending && mutation.variables?.type === "compose-create"`
- `progress = composeCreateProgress`
- `error = mutation.isError && mutation.variables?.type === "compose-create" ? mutation.error.message : undefined`
- `close()`: if a `compose-create` mutation is in flight → just hide the sheet and set
  `localNotice = "Compose 创建任务正在后台执行"` (the task keeps running). Otherwise abort
  `composeCreateAbortRef`, clear it, clear progress, hide.
- `save(value)`: fresh `AbortController` (aborting any previous one) then
  ```
  mutate({ type: "compose-create", signal: controller.signal, value: {
    project_name: value.projectName, working_dir: value.workingDirectory,
    config_file_name: value.configFileName, compose_content: value.composeContent, build: value.build } })
  ```
  (`ComposeCreateValue` is camelCase in the form and snake_case on the wire.)

### 19.2 `DockerFormEditor` save routing (L3810–L3897)
`key={`${editor.type}-${editor.key ?? "new"}`}`, `busy = mutation.isPending`.
The `save(value)` handler intercepts these types **before** falling through to the generic mutation:

| editor.type | behaviour |
|---|---|
| `container-file-download` | `path = String(value.path ?? "").trim()`; blank → `localError = "请输入容器内文件路径"` and stay open. Else close, `fallbackName = path.split("/").filter(Boolean).pop() \|\| "container-file.bin"`, then `downloadDockerResource(`下载容器文件 · ${path}`, fallbackName, () => downloadDockerContainerFile(id, path), `/api/docker/containers/${enc(id)}/files/download?path=${enc(path)}`)` |
| `image-filesystem-view` | `path = String(value.path ?? "/").trim() \|\| "/"`; close, then `openDetail(`镜像文件系统 · ${path}`, () => getDockerImageFilesystem(imageId, path))` |
| `compose-discover` | `discoverDockerCompose(String(value.scan_path ?? ""))`, close, then `setDetail({ title: "Compose 扫描结果", value: result })` |
| `compose-read-file` | requires both `project_path` and `file_path`; blank → `localError = "请输入 Compose 项目路径和文件路径"`. Else close, `openDetail(`读取 Compose 文件 · ${filePath}`, () => readDockerComposeFile(projectPath, filePath))` |
| `compose-backup-download` | requires `project_name` + `backup`; blank → `localError = "请输入 Compose 项目名称和备份文件"`. Else close, `fallbackName = backup.split(/[\\/]/).filter(Boolean).pop() \|\| `${projectName}-backup.tar.gz``, then `downloadDockerResource(`下载 Compose 备份 · ${projectName}`, fallbackName, () => downloadDockerComposeBackup(projectName, backup), `/api/docker/compose/${enc(projectName)}/backups/download.tar.gz?backup=${enc(backup)}`)` |
| `compose-config` | `mutate({ type: "compose-config-save", value: { ...value, project_path: String(value.project_path ?? editor.key ?? "") } })` — **type is rewritten** |
| `compose-dockerfile` | `mutate({ type: "compose-dockerfile-save", value: { ...value, project_path: ... } })` — **type is rewritten** |
| `mirror-remove` | `mutate({ type: "mirror-remove", key: String(value.mirror ?? "") })` — the field becomes the `key`, no `value` |
| *anything else* | `mutate({ type: editor.type, key: editor.key, value })` |

So `container-file-download`, `image-filesystem-view`, `compose-discover`, `compose-read-file`,
`compose-backup-download`, `compose-config` and `compose-dockerfile` are **editor-only pseudo-types** that never reach
the mutation with their own name.

### 19.3 `DockerActionSheet` — image tools (`imageToolsOpen`)
`title="镜像高级工具"`, `subtitle="构建、导入与加载"`, 4 actions:

| icon | label | colour | action |
|---|---|---|---|
| GitBranch | `Git 构建` | primary | editor `{type:"image-build-git", title:"从 Git 构建镜像", value:{ git_url:"", branch:"main", dockerfile:"Dockerfile", tag:"", build_args:{}, no_cache:false }}` |
| Archive | `ZIP 构建` | warning | `chooseDockerArchive("image-build-zip")` |
| Download | `导入镜像` | cyan | editor `{type:"image-import", title:"导入镜像", value:{ source:"", repository:"", tag:"latest" }}` |
| Upload | `加载归档` | success | `chooseDockerArchive("image-load")` |

### 19.4 `DockerActionSheet` — image menu (`imageMenu`)
`title="镜像操作"`, `subtitle = imageMenu.name`, 5 actions:

| icon | label | colour | action |
|---|---|---|---|
| Archive | `镜像历史` | text | `openDetail(`镜像历史 · ${name}`, () => getDockerImageHistory(key))` |
| Tags | `查看标签` | primary | `openDetail(`镜像标签 · ${name}`, () => getDockerImageTags(key))` |
| Folder | `文件系统` | warning | editor `{type:"image-filesystem-view", title:"浏览镜像文件系统", key, value:{ path:"/" }}` |
| UploadCloud | `推送镜像` | cyan | editor `{type:"image-push", title:"推送镜像", key, value: imagePushValue(name)}` → `{image, tag}` |
| Trash2 | `删除镜像` | danger | confirm `确认删除` / `` `删除镜像 ${name}？` `` → `{type:"image-remove", key: name !== "<none>" ? name.split(",")[0] : key}` |

### 19.5 `DockerActionSheet` — container menu (`containerMenu`)
`title="容器操作"`, `subtitle = containerMenu.name`. First entry is conditional; the rest always show, in this order:

| # | icon | label | colour | action |
|---|---|---|---|---|
| 0 | Pause | `暂停容器` | warning | *only when* `running && !paused` → `{type:"container-pause", key}` (no confirm) |
| 1 | Search | `容器详情` | text | `inspect("container", key)` → detail `容器详情` |
| 2 | FileText | `查看日志` | cyan | `containerLogs(key)` (switches to the logs view with `output` set) |
| 3 | Folder | `管理文件` | warning | editor `{type:"container-files", title:"容器文件操作", key, value:{ operation:"list", path:"/" }}` |
| 4 | Download | `下载文件` | cyan | editor `{type:"container-file-download", title:"下载容器文件", key, value:{ path:"/" }}` |
| 5 | Upload | `上传文件` | warning | `chooseDockerUpload("container-file-upload", key, `上传文件 · ${name}`, { path:"/" })` |
| 6 | Archive | `导出容器` | warning | `downloadDockerResource(`导出容器 · ${name}`, `${name.replace(/^\/+/,"") \|\| "container"}.tar`, () => exportDockerContainer(key), `/api/docker/containers/${enc(key)}/export`, "POST")` |
| 7 | Activity | `查看进程` | cyan | `openDetail(`容器进程 · ${name}`, () => getDockerContainerProcesses(key))` |
| 8 | FileText | `Compose 配置` | text | `openDetail(`Compose 配置 · ${name}`, () => getDockerContainerComposeConfig(key))` |
| 9 | Pencil | `编辑配置` | primary | `editContainer(key)` → editor `container-edit` titled `编辑容器` |
| 10 | Box | `重命名` | primary | editor `{type:"container-rename", title:"重命名容器", key, value:{ name: containerMenu.name }}` |
| 11 | Copy | `复制容器` | primary | editor `{type:"container-copy", title:"复制容器", key, value:{ name: `${name.replace(/^\/+/,"")}-copy` }}` |
| 12 | Archive | `提交为镜像` | warning | editor `{type:"container-commit", title:"提交容器为镜像", key, value:{ repository:"", tag:"latest", author:"", comment:"", pause:true }}` |
| 13 | Tags | `设置标签` | primary | editor `{type:"container-label-set", title:"设置容器标签", key, value:{ label:"" }}` |
| 14 | Trash2 | `移除标签` | danger | confirm `移除标签` / `` `移除容器 ${name} 的标签？` `` → `{type:"container-label-remove", key}` |
| 15 | Layers | `设置分组` | primary | editor `{type:"container-group-set", title:"设置容器分组", key, value:{ container_name: name.replace(/^\/+/,""), group_key:"" }}` |
| 16 | GitBranch | `切换版本` | cyan | editor `{type:"container-version-switch", title:"切换容器版本", key, value:{ target_image_ref:"" }}` |
| 17 | Trash2 | `删除容器` | danger | confirm `确认删除` / `` `强制删除容器 ${name}？` `` → `{type:"container-remove", key}` |

`containerMenu.name` is the **raw** name (may retain a leading `/`); only entries 11/15 and the export filename strip it.

---

## 20. Complete mutation `type` index

The mutation is `useMutation({ mutationFn: async ({ type, key, value, signal }) => ... })` dispatched by a long
`type === "..."` ladder (L1556–L1826) with **53 explicit branches** plus **two prefix fall-throughs**:

```ts
if (type.startsWith("container-"))                       // L1603, AFTER all explicit container- branches
  return runDockerContainerAction(key ?? "", type.replace("container-", "") as "start");
if (type.startsWith("compose-")) {                       // L1760, AFTER all explicit compose- branches
  const projectPath = String(value?.project_path ?? "").trim();
  const projectName = String(value?.project_name ?? "").trim();
  if (!projectPath || !projectName) throw new Error("Compose 项目名称或路径缺失");
  try { return await runDockerComposeAction(type.replace("compose-", "") as "up"|"down"|"start"|"stop"|"restart",
    { ...value, project_path: projectPath, project_name: projectName }); }
  catch (error) { throw composeProjectError(error, projectPath); }
}
```

The fall-throughs are how `container-start` / `container-stop` / `container-restart` / `container-pause` /
`container-unpause` and `compose-start` / `compose-stop` / `compose-restart` are served — they have **no explicit
branch**. Net: **61 distinct `type` strings reach the mutation.** Grouped, with the payload each UI site sends:

**Containers (13 explicit + 5 via fall-through)** — `container-create` `{name:"",image:"",config:{}}` · `container-edit` (payload = `nested(detail,["container","data"])`) ·
`container-remove` (key only) · `container-rename` `{name}` · `container-copy` `{name}` · `container-commit`
`{repository,tag,author,comment,pause}` · `container-label-set` `{label}` · `container-label-remove` (key only) ·
`container-group-set` `{container_name,group_key}` · `container-version-switch` `{target_image_ref}` ·
`container-file-upload` `{path,file_name,file_uri}` · `container-files` `{operation,path}` ·
`container-upgrade` (payload = upgrade-check result minus `ret`/`msg`) · `container-start` · `container-stop` ·
`container-restart` · `container-pause` · `container-unpause` (last five: key only, no `value`).

**Images (10)** — `image-pull` `{image,tag,architecture}` · `image-remove` (key = first tag or id) ·
`images-remove-batch` `{ids:string[]}` · `image-tag` `{repository,tag}` · `image-build` `{}` ·
`image-build-git` `{git_url,branch,dockerfile,tag,build_args,no_cache}` ·
`image-build-zip` `{file_name,file_uri,tag,dockerfile,build_args,no_cache}` ·
`image-import` `{source,repository,tag}` · `image-load` `{file_name,file_uri}` · `image-push` `{image,tag}`.

**Compose (10 explicit + 3 via fall-through)** — `compose-create` `{project_name,working_dir,config_file_name,compose_content,build}` (+ `signal`) ·
`compose-start` / `compose-stop` / `compose-restart` (fall-through) and `compose-backup` (explicit) each send
`value = composePayload(item)` = `{project_name, project_path}` · `compose-config-save` `{content, project_path}` ·
`compose-dockerfile-save` `{content, project_path}` · `compose-backup-restore` `{project_name,backup}` ·
`compose-backup-remove` `{project_name,backup}` · `compose-backup-upload` `{project_name,file_name,file_uri}` ·
`compose-backup-cancel` `{project_name}` · `compose-backups-clear` `{project_name}` ·
`compose-restore` `{target_path,project_name,auto_start,config_file_name,file_name,file_uri}`.

**Networks (2)** — `network-create` `{Name,Driver:"bridge",Options:{},IPAM:{}}` · `network-remove` (key only).

**Volumes (8)** — `volume-create` `{Name,Driver:"local",DriverOpts:{},Labels:{}}` · `volume-remove` (key = name) ·
`volume-backup` (key = name) · `volume-restore` `{backup}` + key = name · `volume-backup-remove` `{backup}` + key = name ·
`volume-backup-upload` `{file_name,file_uri}` + key = name · `volume-backup-cancel` (key = name) ·
`volume-import` `{volume_name,driver,file_name,file_uri}`.

**Tasks / settings (10)** — `task-remove` (key only) · `tasks-clear` · `group-create` `{Name,Key}` ·
`group-update` `{Name,Key}` · `group-remove` `{key}` · `upgrade-status-clear` · `config-save` (whole config record) ·
`prune` `{containers,images,networks,volumes,build_cache}` · `mirror-add` `{mirror}` · `mirror-remove` (key = mirror string).

Mutation-side special behaviour observed in the dispatch ladder (L1828–L1930):
- `compose-create` and `images-remove-batch` drive their own progress state
  (`composeCreateProgress`, `imageDeleteProgress` `{completed,total}`) and are the only two that stream progress.
- `container-files` result is pushed into `output` (so the caller can inspect the listing).
- `volume-restore`, `tasks-clear`, `config-save`, `upgrade-status-clear` have bespoke post-success handling
  (cache invalidation / notice text).

---

# `src/components/docker-overview.tsx`

## 21. Data plumbing (L21–L621) — verbatim candidate key lists

Module constants: `emptyDockerInfo: LuckyRecord = {}`, `emptyDockerContainers: LuckyRecord[] = []`.

Local copies of `pick(item, keys, fallback = "")` and `bytes(value)` — identical semantics to docker.tsx
(units `["B","KB","MB","GB","TB"]`, base 1024, `0`/`NaN` → `"--"`, 0 decimals at index 0 else 2).

### 21.1 Generic probes
- `deepDockerValue(source, key)` — **breadth-first** walk (queue + `visited` set) over arrays/objects; at each record,
  returns the value of the first own key whose `toLowerCase()` equals `key.toLowerCase()`; otherwise enqueues all values.
- `dockerNumber(source, keys)` — for each key in order, `deepDockerValue`; a finite `number` wins; a `string` is
  comma-stripped and matched against `/-?\d+(?:\.\d+)?/` (first numeric substring). Returns `undefined` if nothing matched.
- `parseDockerBytes(value)` — finite `number` → as-is. String → trim, strip commas, match
  `/^(-?\d+(?:\.\d+)?)\s*([kmgtpe]?i?b)?/i`. Unit defaults to `"b"`. Powers:
  `{ b:0, kb:1, kib:1, mb:2, mib:2, gb:3, gib:3, tb:4, tib:4, pb:5, pib:5, eb:6, eib:6 }`.
  **Base is 1024 when the unit contains `i`, otherwise 1000.** Result `amount * base ** power`.
- `dockerValue(source, keys)` — first `deepDockerValue` that is neither `undefined` nor `null`.
- `dockerDirectValue(source, keys)` — case-insensitive lookup **on the top-level record only** (no recursion).
- `dockerChildRecord(source, keys)` — first own key (case-insensitive) whose value is a plain object (not an array).

### 21.2 `dockerCpuPercent(source)`
1. Direct: `dockerNumber(source, ["CPUPercent","cpuPercent","cpu_percent","CPUPerc","cpuPerc"])` → `Math.max(0, v)`.
2. Else Docker-engine style delta computation:
   - `cpuStats = dockerChildRecord(source, ["cpu_stats","cpuStats","CPUStats"])`
   - `previous = dockerChildRecord(source, ["precpu_stats","preCpuStats","PreCPUStats"])`
   - fallback lambda = `dockerNumber(source, ["CPUUsage","cpuUsage","cpu_usage","CPU","cpu"])`
   - `cpuUsage = dockerChildRecord(cpuStats, ["cpu_usage","cpuUsage","CPUUsage"])`,
     `previousUsage = dockerChildRecord(previous, ["cpu_usage","cpuUsage","CPUUsage"])`
   - `cpuDelta = total_usage(cpuUsage) - total_usage(previousUsage)` with keys `["total_usage","totalUsage","TotalUsage"]`
   - `systemDelta = system_cpu_usage(cpuStats) - system_cpu_usage(previous)` with keys
     `["system_cpu_usage","systemCpuUsage","SystemCPUUsage"]`
   - `perCpu = dockerValue(cpuUsage, ["percpu_usage","perCpuUsage","PercpuUsage"])`
   - `cpuCount = dockerNumber(cpuStats, ["online_cpus","onlineCpus","OnlineCPUs"]) ?? (Array.isArray(perCpu) ? perCpu.length : 1)`
   - `calculated = cpuDelta > 0 && systemDelta > 0 ? (cpuDelta/systemDelta) * Math.max(1, cpuCount) * 100 : undefined`
   - return `calculated ?? fallback()`  ← **note: the `Math.max(0,…)` clamp only applies to the direct branch.**

### 21.3 `dockerMemoryValues(source)` → `{ usage?, limit?, percent? }`
Usage candidates (via `dockerValue`, deep):
```
["MemoryUsage","memoryUsage","memory_usage","MemUsage","memUsage","mem_usage","Memory","memory","Mem","mem"]
```
Limit candidates:
```
["MemoryLimit","memoryLimit","memory_limit","MemLimit","memLimit","mem_limit"]
```
If the raw usage is a **string containing `/`** (e.g. `"12.5MiB / 1.95GiB"`), split on the first `/` and re-parse both halves
(usage / limit) via `parseDockerBytes`.

Fallback via `memoryStats = dockerChildRecord(source, ["memory_stats","memoryStats","MemoryStats"])`:
- if usage still undefined: `raw = dockerNumber(memoryStats, ["usage","Usage"])`,
  `detail = dockerChildRecord(memoryStats, ["stats","Stats"])`,
  `cache = dockerNumber(detail, ["total_inactive_file","inactive_file","cache","Cache"]) ?? 0`;
  `usage = cache > 0 && cache < raw ? raw - cache : raw`.
- if limit still undefined: `limit = dockerNumber(memoryStats, ["limit","Limit"])`.

Percent candidates (direct number probe):
```
["MemoryPercent","memoryPercent","memory_percent","MemPercent","memPercent","MemPerc","memPerc"]
```
else `usage/limit*100` when both known and `limit > 0`, else `undefined`.
Both `usage` and `percent` are clamped with `Math.max(0, …)`; `limit` is not clamped.

### 21.4 `dockerBytePair(value)`
String containing `/` → split on first `/`, `parseDockerBytes` each half. Array of length ≥ 2 → parse `[0]` and `[1]`.
Otherwise `[undefined, undefined]`.

### 21.5 `dockerIoValues(source)` → `{ networkRx, networkTx, blockRead, blockWrite }`
Combined pair from `dockerDirectValue(source, ["NetIO","netIO","net_io","NetworkIO","networkIO","network_io"])`.
Then explicit RX (top-level only):
```
["NetworkRx","NetworkRX","networkRx","network_rx","network_rx_bytes","NetworkInput","networkInput",
 "network_input","NetInput","netInput","net_input","RxBytes","rxBytes","rx_bytes"]
```
Explicit TX:
```
["NetworkTx","NetworkTX","networkTx","network_tx","network_tx_bytes","NetworkOutput","networkOutput",
 "network_output","NetOutput","netOutput","net_output","TxBytes","txBytes","tx_bytes"]
```
(each `?? combinedRx / combinedTx`.)

Per-interface aggregation via `networks = dockerChildRecord(source, ["networks","Networks","network","Network"])`
when either side is still undefined:
- direct keys on the `networks` object itself, matched case-insensitively against `["rx_bytes","rxbytes"]` /
  `["tx_bytes","txbytes"]`; seed `rx`/`tx` with those, and mark found.
- then **sum** `dockerNumber(entry, ["rx_bytes","rxBytes","RxBytes"])` / `["tx_bytes","txBytes","TxBytes"]` across every
  plain-object value of `networks` (on top of the seed). Assign only if the corresponding side was undefined and something
  was found.

Block I/O: combined pair from
```
["BlockIO","blockIO","blockIo","block_io","BlkIO","blkIO","DiskIO","diskIO","disk_io"]
```
Explicit read:
```
["BlockRead","blockRead","block_read","block_read_bytes","DiskRead","diskRead","disk_read",
 "BlockInput","blockInput","block_input","IORead","ioRead","io_read","ReadBytes","readBytes","read_bytes"]
```
Explicit write:
```
["BlockWrite","blockWrite","block_write","block_write_bytes","DiskWrite","diskWrite","disk_write",
 "BlockOutput","blockOutput","block_output","IOWrite","ioWrite","io_write","WriteBytes","writeBytes","write_bytes"]
```
Fallback via `blockStats = dockerChildRecord(source, ["blkio_stats","blkioStats","BlkioStats"])`:
prefer `dockerValue(blockStats, ["io_service_bytes_recursive","ioServiceBytesRecursive","IoServiceBytesRecursive"])`
when it is a non-empty array, else `dockerValue(blockStats, ["io_service_bytes","ioServiceBytes","IoServiceBytes"])`.
For each entry, `operation = pick(entry, ["op","Op","operation","Operation"]).toLowerCase()` and
`amount = dockerNumber(entry, ["value","Value"])`; sum into `read` when `operation === "read"`, `write` when `"write"`.

### 21.6 `hasDockerStatShape(record)` — the stat-record detector
Normalises every own key with `key.toLowerCase().replace(/[^a-z]/g, "")` (strips digits/underscores) and returns true if
**any** normalised key satisfies:
```
key === "cpu" || key === "memory" || key === "mem"
|| includes("cpupercent") || includes("cpuperc") || includes("cpuusage") || includes("cpustats")
|| includes("memoryusage") || includes("memusage") || includes("memorypercent") || includes("memperc")
|| includes("memorystats")
|| key === "networks" || key === "network" || includes("networkio") || includes("netio")
|| includes("networkrx") || includes("networktx") || key === "rxbytes" || key === "txbytes"
|| includes("blockio") || includes("blockread") || includes("blockwrite")
|| includes("diskread") || includes("diskwrite") || key === "readbytes" || key === "writebytes"
|| includes("blkiostats")
```

### 21.7 `collectDockerStats(source)` → `{ record, hint }[]`
Depth-limited DFS (`depth > 7` aborts), `visited` set, `wrapperKeys = new Set(["data","result","stats","list","containers"])`.
- arrays: recurse into each element with the **same** hint, `depth + 1`.
- objects: if `hasDockerStatShape(record)` → push `{record, hint}` and **stop descending**.
- otherwise `ownName = pick(record, ["Name","name","ContainerName","containerName"])`, and for each child key:
  `nextHint = ownName || (wrapperKeys.has(key.toLowerCase()) ? hint : key)`.
  This is how a `{ "<container-name>": { …stats… } }` map yields the container name as the hint.

### 21.8 `dockerContainerState(item)` (exported)
`type DockerContainerState = "running" | "paused" | "exited" | "created" | "other"`
```ts
state = [pick(item,["State","state"]), pick(item,["Status","status"])].join(" ").toLowerCase()
1. /paused/.test(state)                        → "paused"
2. /created/.test(state)                       → "created"
3. /exited|stopped|dead|removing/.test(state)  → "exited"
4. running = item.Running ?? item.running; normalized = typeof running === "string" ? trim().toLowerCase() : running
   normalized ∈ {true, 1, "true", "1"}   → "running"
   normalized ∈ {false, 0, "false", "0"} → "exited"
5. /running|active|\bup\b|restarting/.test(state) → "running"
6. otherwise                                   → "other"
```
Order matters: a `paused` container is reported as `paused`, never `running`; the textual regexes win over the
`Running` boolean.

`cleanDockerContainerName(value)` = `value.split(",")[0]?.trim().replace(/^\/+/, "") ?? ""`.

### 21.9 `DockerStatRow` (exported type)
```ts
type DockerStatRow = {
  key: string; name: string;
  cpu: number;           hasCpu: boolean;
  memory: number;        hasMemory: boolean;
  memoryPercent: number; hasMemoryPercent: boolean;
  networkRx: number;     hasNetworkRx: boolean;
  networkTx: number;     hasNetworkTx: boolean;
  blockRead: number;     hasBlockRead: boolean;
  blockWrite: number;    hasBlockWrite: boolean;
};
```
Every metric is a non-optional `number` (0 when absent) paired with a `hasX` flag — the Swift port must keep this
"value + presence" pairing because `0 B` and `N/A` render differently.

### 21.10 `dockerStatRows(source, containers)` (exported)
1. `containerInfo = containers.map((container, index) => ({ container, id, name }))` where
   `id = pick(container, ["Id","ID","id","Container","ContainerID","ContainerId","containerId"], String(index))`
   and `name = cleanDockerContainerName(pick(container, ["Names","Name","name","ContainerName","containerName"]))`.
2. For each `{record, hint}` from `collectDockerStats(source)`:
   - `rawId = pick(record, ["Id","ID","id","Container","ContainerID","ContainerId","containerId","container_id"])`
     (note the extra `"container_id"` compared with the container list above)
   - `rawName = cleanDockerContainerName(pick(record, ["Name","name","ContainerName","containerName"]))`
   - match against `containerInfo` if **any** holds:
     `rawId && (item.id.startsWith(rawId) || rawId.startsWith(item.id))` (prefix match either way — handles short ids) ‖
     `hint && (item.id.startsWith(hint) || hint.startsWith(item.id))` ‖
     `rawName && item.name === rawName` ‖
     `hint && item.name === cleanDockerContainerName(hint)`
   - **skip** the candidate entirely if the matched container's state is `"exited"` or `"created"`.
   - compute `cpu`, `memory`, `io`; **skip** if cpu, memory.usage and all four I/O values are `undefined`.
   - `name = match?.name || rawName || cleanDockerContainerName(hint) || `容器 ${index + 1}``  ← fallback UI string
   - `key = match?.id || rawId || hint || `${name}-${index}``
   - merge into `byKey`: for an existing entry, each metric is overwritten only when the new candidate *has* it
     (`hasX` values OR together, `name` keeps the first non-empty). Return `[...byKey.values()]`.

---

## 22. Overview sub-components

`formatPercent(value?, digits = 1)` → `undefined` or non-finite → `"--"`, else `` `${value.toFixed(digits)}%` ``.

### 22.1 `DockerGauge({ label, value?, color, digits = 1 })`
- `size = 94`, `radius = 34`, `circumference = 2πr`, `arc = circumference * 0.75` (a 270° gauge).
- `progress = value === undefined ? 0 : clamp(value, 0, 100)`.
- Track: `<Circle>` centred at `size/2`, `stroke = colors.muted`, `strokeWidth 8`, `strokeLinecap "round"`,
  `strokeDasharray = `${arc} ${circumference}``, `transform = rotate(135, cx, cy)`.
- Progress arc rendered only when `value !== undefined && progress > 0`: same geometry, `stroke = color`,
  `strokeDasharray = `${arc * (progress/100)} ${circumference}``, same 135° rotation.
- Centre label (absolutely positioned, `pointerEvents none`): `formatPercent(value, digits)` —
  `width 60`, `colors.text`, `fontSize 14`, `lineHeight 18`, `fontWeight "800"`, `textAlign center`,
  `adjustsFontSizeToFit`, `allowFontScaling={false}`, `minimumFontScale 0.65`, `numberOfLines 1`, `includeFontPadding false`.
- a11y: `role="progressbar"`, `label = `${label}使用率``, value `{min:0,max:100,now:progress,text:formatPercent(...)}`
  or `{ text: "暂无数据" }` when `value === undefined`.

### 22.2 `DockerResourceCard({ icon, iconBackground, title, color, primaryLabel, primaryValue, secondaryLabel, secondaryValue, gaugeValue?, digits? })`
Outer: `flexGrow 1, flexShrink 1, flexBasis 330, minWidth 260` wrapping a `<Panel>`.
Inner: `minHeight 116`, row, `gap 14`.
- Left column (`flex 1, gap 13`):
  - Title row (`gap 8`): `<IconTile icon color={color} background={iconBackground} size={32} iconSize={16} />`
    + title `colors.text, fontSize 15, fontWeight "800"`.
  - Metric block (`gap 8`), two rows (`row, gap 10`):
    - `primaryLabel` `colors.subtext fontSize 11` (flex 1) / `primaryValue` `colors.text fontSize 12 fontWeight "700"` (1 line)
    - `secondaryLabel` `colors.subtext fontSize 11` (flex 1) / `secondaryValue` in `color`, `fontSize 15, fontWeight "800"`
- Right: `<DockerGauge label={title} value={gaugeValue} color={color} digits={digits} />`

### 22.3 `DockerLiveResourceCards({ info, active, liveStatus? })`
`internalLive = useLuckyStatus(active && !liveStatus)`; `live = liveStatus ?? internalLive`;
`hasLiveData = active && live.connected && Boolean(live.data)`.
- `cpuCount = dockerNumber(info, ["NCPU","Ncpu","CPUCount","cpuCount","NumCPU"])`
- `totalMemory = (hasLiveData ? live.data?.totalMem : 0) || parseDockerBytes(dockerValue(info,
  ["MemTotal","memTotal","TotalMemory","totalMemory"]))`
- `cpuUsage = hasLiveData && Number.isFinite(live.data.usedCpu) ? live.data.usedCpu : undefined`
- `memoryUsage = hasLiveData ? live.data?.usedMem : undefined`
- `memoryPercent = memoryUsage !== undefined && totalMemory ? (memoryUsage/totalMemory)*100 : undefined`
- **`connectionValue = live.error ? "连接中断" : "连接中"`** — shown in place of a percentage while offline.

Layout: `row`, `flexWrap`, `gap 12`, two cards:

| card | icon | iconBackground | colour | primaryLabel / value | secondaryLabel / value | gauge | digits |
|---|---|---|---|---|---|---|---|
| `CPU` | Cpu | colors.primarySoft | colors.primary | `逻辑核心` / `cpuCount === undefined ? "--" : String(Math.round(cpuCount))` | `使用率 (%)` / `cpuUsage === undefined ? connectionValue : formatPercent(cpuUsage, 2)` | cpuUsage | 2 |
| `内存` | MemoryStick | colors.successBg | colors.success | `总可用内存` / `totalMemory ? bytes(totalMemory) : "--"` | `使用率 (%)` / `memoryPercent === undefined ? connectionValue : formatPercent(memoryPercent, 1)` | memoryPercent | 1 (default) |

### 22.4 `DockerSummaryItem({ icon, color, background, valueColor?, value, suffix?, label, badge?, width?, onPress })`
Pressable tile: `width`, `flexGrow/flexShrink = width === undefined ? 1 : 0`, `flexBasis = width ?? 132`,
`minWidth = width ?? 132`, `minHeight 72`, `padding 10`, `borderRadius 16`, `borderWidth 1 / colors.border`,
row, `alignItems center`, `gap 10`, background `pressed ? colors.mutedCard : colors.card`, `opacity pressed ? 0.72 : 1`,
shadow `colors.shadow`, `shadowOpacity = colors.mode === "dark" ? 0 : 0.04`, `shadowRadius 8`, `shadowOffset {0,3}`,
`elevation 1`. `accessibilityRole="button"`, `accessibilityLabel = `查看${label}``.
- Icon box: `38×38`, `borderRadius 10`, centred, `backgroundColor = background`; glyph `size 19`, `strokeWidth 2.2`, in `color`.
- Text column (`flex 1, gap 2`):
  - value row (`gap 4`): `value` in `valueColor ?? colors.text`, `fontSize 17`, `fontWeight "800"`, `numberOfLines 1`;
    optional `suffix` in `colors.subtext`, `fontSize 12`, `fontWeight "700"`.
  - `label` — `colors.subtext`, `fontSize 11`, `numberOfLines 1`.
  - optional `badge` pill — `alignSelf flex-start`, `paddingHorizontal 6`, `paddingVertical 3`, `borderRadius 7`,
    `backgroundColor colors.mutedCard`; text `colors.subtext`, `fontSize 10`, `fontWeight "700"`, `numberOfLines 1`.

### 22.5 `DockerStateChip({ label, value, color })`
`minHeight 32`, `paddingHorizontal 11`, `borderRadius 16`, `borderWidth 1 / colors.border`,
`backgroundColor colors.card`, row, `gap 6`. Contents: 6×6 dot (`borderRadius 3`, `backgroundColor = color`),
`label` in `colors.subtext fontSize 11`, `value` in `colors.text fontSize 11 fontWeight "800"`.

### 22.6 `DockerRankingCard({ title, color, rows, mode: "cpu"|"memory", emptyMessage, onSelectContainer })`
Outer: `flexGrow 1, flexShrink 1, flexBasis 360, minWidth 260` wrapping a `<Panel>`.
`memoryMax = Math.max(1, ...rows.map(r => r.memory))`.
- Head row: `minHeight 28`, row, `gap 8`;
  `<IconTile icon={mode === "cpu" ? Cpu : MemoryStick} color={color}
  background={mode === "cpu" ? colors.primarySoft : colors.successBg} size={32} iconSize={16} />`
  + `title` in `colors.text, fontSize 14, fontWeight "800"` (flex 1).
- When `rows.length` — column with `gap 0`:
  - Column headers (`minHeight 24`, row, `gap 10`): `#` (`width 18`, `colors.subtext`, `fontSize 9`, centred),
    `容器名称` (`flex 1`, `colors.subtext`, `fontSize 9`),
    `mode === "cpu" ? "使用率 (%)" : "内存占用"` (`minWidth 62`, `fontSize 9`, right-aligned).
  - One pressable per row: `minHeight 48`, `paddingVertical 6`, `borderTopWidth 1 / colors.rowBorder`, row, `gap 8`,
    `opacity pressed ? 0.65 : 1`, `accessibilityLabel = `查看容器 ${row.name}``, action `onSelectContainer(row.name)`.
    - rank number `index + 1` — `width 18`, `fontSize 11`, `fontWeight "800"`, centred; colour
      `index === 0 ? colors.danger : index === 1 ? colors.warning : colors.subtext`.
    - `row.name` — `flex 1`, **`colors.primary`**, `fontSize 12`, `fontWeight "700"`, `numberOfLines 1`.
    - Bar track: `flexBasis 70, flexShrink 1, minWidth 36, maxWidth 90, height 6, borderRadius 3,
      backgroundColor colors.muted, overflow hidden`; fill `width = `${clamp(bar,0,100)}%``, `height 6, borderRadius 3`.
      `bar = mode === "cpu" ? clamp(row.cpu,0,100) : row.hasMemoryPercent ? clamp(row.memoryPercent,0,100)
      : (row.memory / memoryMax) * 100`.
      `barColor` — cpu: `>= 80 → danger`, `>= 50 → warning`, else `primary`;
      memory: `memoryPercent >= 80 → danger`, `>= 60 → warning`, else `success`
      (**memory thresholds use `memoryPercent` even when the bar was scaled by `memoryMax`**).
    - Metric text: `minWidth 62`, `colors.subtext`, `fontSize 11`, `fontWeight "700"`, `tabular-nums`, right-aligned;
      `mode === "cpu" ? formatPercent(row.cpu, 1) : (row.memory > 0 ? bytes(row.memory) : "0 B")`.
- When empty: `minHeight 92` centred box with `emptyMessage` in `colors.subtext fontSize 12`.

---

## 23. `DockerOverviewDashboard` (L943–L1050)

```ts
type DockerOverviewTarget = "containers" | "images" | "compose" | "networks" | "volumes";

props: { data?, active: boolean, liveStatus?, stats?: unknown, statsLoading: boolean, statsError?: string,
         showHeader = true, showDockerSummary = true, showContainerInsights = true,
         onSelectView(view: DockerOverviewTarget), onSelectContainer(name: string) }
```
Local state: `summaryWidth` (measured via `onLayout`, floored).

Derived:
- `containers = data?.containers ?? []`
- `statRows = showContainerInsights ? dockerStatRows(stats, containers) : []`
- `cpuRows = statRows.filter(hasCpu).sort(desc by cpu).slice(0, 5)` — **top 5**
- `memoryRows = statRows.filter(hasMemory).sort(desc by memory).slice(0, 5)` — **top 5**
- `states` = per-`DockerContainerState` counts over `containers`
  (`{running:0,paused:0,exited:0,created:0,other:0}` seed).
- `imageAccent = colors.mode === "dark" ? "#ff6482" : "#d63384"`
- `imageBackground = colors.mode === "dark" ? "#4a1830" : "#fce7f3"`  ← the only hard-coded palette in the file
- `count(v) = v === undefined ? "--" : String(v)`
- `statusValue(v) = data?.containersAvailable ? String(v) : "--"`
- `rankingEmpty = statsError ? "容器统计暂不可用" : statsLoading ? "正在读取容器统计" : "暂无容器统计数据"`
  (note: `容器统计暂不可用` here vs. the screen-level `容器统计暂时不可用`)
- `summaryColumns = summaryWidth >= 700 ? 5 : summaryWidth >= 264 ? 2 : 1`
- `summaryItemWidth = summaryWidth ? Math.floor((summaryWidth - (summaryColumns - 1) * 8) / summaryColumns) : undefined`

Render order (a fragment; the parent supplies the outer stack spacing):
1. If `showHeader`: `<SectionHeader icon={Gauge} title="Docker 总览" />`
2. `<DockerLiveResourceCards info={data?.info ?? {}} active liveStatus />`
3. If `showDockerSummary`: measured `row / flexWrap / gap 8` container with **5** `DockerSummaryItem`s, all receiving
   `width={summaryItemWidth}`:

| order | icon | color | background | value | suffix | valueColor | badge | label | onPress |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Workflow | colors.subtext | colors.mutedCard | `count(data?.composeCount)` | — | — | — | `Compose` | `onSelectView("compose")` |
| 2 | Container | colors.primary | colors.primarySoft | `statusValue(states.running)` | `` ` / ${data.containerCount}` `` (undefined → none; note the leading space) | colors.success | — | `容器` | `onSelectView("containers")` |
| 3 | Image | `imageAccent` | `imageBackground` | `count(data?.imageCount)` | — | — | `imageSize === undefined ? undefined : imageSize > 0 ? bytes(imageSize) : "0 B"` | `镜像列表` | `onSelectView("images")` |
| 4 | Database | colors.success | colors.successBg | `count(data?.volumeCount)` | — | — | — | `数据卷` | `onSelectView("volumes")` |
| 5 | Network | colors.cyan | colors.cyanBg | `count(data?.networkCount)` | — | — | — | `网络` | `onSelectView("networks")` |

4. If `showContainerInsights`:
   - **State strip**: `padding 12, borderRadius 14, borderWidth 1 / colors.border, backgroundColor colors.mutedCard`,
     row + wrap + `alignItems center`, `gap 8`. Leading label `容器状态` (`marginRight 4`, `colors.text`,
     `fontSize 12`, `fontWeight "800"`), then chips:
     `运行中` = `statusValue(states.running)` / colors.success · `已暂停` = `statusValue(states.paused)` / colors.warning ·
     `已退出` = `statusValue(states.exited)` / colors.danger · `已创建` = `statusValue(states.created)` / colors.primary ·
     and **only when `states.other > 0`** → `其它` = `String(states.other)` / colors.subtext (raw count, not `statusValue`).
   - **Ranking row**: `row / flexWrap / gap 12` with
     `DockerRankingCard title="CPU 使用率前 5" color={colors.primary} rows={cpuRows} mode="cpu"` and
     `DockerRankingCard title="内存使用率前 5" color={colors.success} rows={memoryRows} mode="memory"`,
     both with `emptyMessage={rankingEmpty}` and `onSelectContainer`.

---

## 24. Verbatim Chinese string index

### 24.1 Page / tabs / headers
`Docker` · `容器、镜像与 Compose 管理` · `容器` · `镜像` · `Compose` · `网络` · `数据卷` · `任务` · `总览` · `设置` ·
`日志` · `镜像列表` · `Compose 项目` · `Docker 网络` · `后台任务` · `Docker 总览` · `Docker 设置` · `维护状态` ·
`分组与标签` · `备份任务` · `镜像升级` · `Registry Mirrors` · `Docker 日志` · `正在刷新` · `7 个接口` ·
meta pattern `` `${n} 项` ``

### 24.2 Search placeholders
`搜索容器` · `搜索镜像` · `搜索Compose` · `搜索网络` · `搜索数据卷` · `搜索任务`

### 24.3 Buttons / labels
`创建容器` · `恢复` · `启动` · `停止` · `重启` · `更新` · `拉取` · `构建` · `镜像高级工具` · `处理中` · `检测所选` ·
`升级状态` · `退出批量` · `批量操作` · `取消全选` · `全选` · `检查中` · `选择未使用` · `删除所选` · `详情` · `标记` ·
`更多` · `删除` · `创建 Compose` · `扫描项目` · `日志` · `备份` · `备份列表` · `下载备份` · `清空备份` · `上传备份` ·
`恢复备份` · `删除备份` · `取消备份` · `编辑配置` · `读取文件` · `恢复配置` · `Dockerfile` · `创建网络` ·
`创建数据卷` · `导入数据卷` · `导出` · `清空任务` · `编辑设置` · `添加分组` · `编辑分组` · `删除分组` ·
`清除升级状态` · `添加` · `清理未使用资源` · `第 N 页` (`` `第 ${dockerLogPage} 页` ``) ·
`已选择 N 项` (`` `已选择 ${n} 项` ``) · `删除中 c/t` (`` `删除中 ${completed}/${total}` ``)

### 24.4 Action-sheet titles / subtitles / items
`镜像高级工具` / `构建、导入与加载`; items `Git 构建` `ZIP 构建` `导入镜像` `加载归档`.
`镜像操作` / *image name*; items `镜像历史` `查看标签` `文件系统` `推送镜像` `删除镜像`.
`容器操作` / *container name*; items `暂停容器` `容器详情` `查看日志` `管理文件` `下载文件` `上传文件` `导出容器`
`查看进程` `Compose 配置` `编辑配置` `重命名` `复制容器` `提交为镜像` `设置标签` `移除标签` `设置分组` `切换版本`
`删除容器`.

### 24.5 Editor titles
`创建容器` · `编辑容器` · `更新容器 {name}` · `重命名容器` · `复制容器` · `提交容器为镜像` · `设置容器标签` ·
`设置容器分组` · `切换容器版本` · `容器文件操作` · `下载容器文件` · `拉取镜像` · `构建镜像` · `从 Git 构建镜像` ·
`从 ZIP 构建镜像` · `导入镜像` · `加载镜像归档` · `添加镜像标签` · `推送镜像` · `浏览镜像文件系统` ·
`发现 Compose 项目` · `编辑 Compose 配置` · `编辑 Dockerfile` · `读取 Compose 文件 · {name}` ·
`下载 Compose 备份 · {name}` · `恢复 Compose 备份 · {name}` · `删除 Compose 备份 · {name}` ·
`上传 Compose 备份 · {name}` · `恢复 Compose 配置 · {name}` · `创建网络` · `创建数据卷` · `导入数据卷` ·
`恢复数据卷备份` · `删除数据卷备份 · {name}` · `上传数据卷备份 · {name}` · `上传文件 · {name}` ·
`编辑 Docker 设置` · `添加容器分组` · `编辑容器分组` · `删除容器分组` · `添加镜像加速地址` · `删除镜像加速地址` ·
`清理 Docker 资源`

### 24.6 Detail viewer titles
`容器详情` · `镜像详情` · `任务详情` · `镜像升级状态` · `检测镜像升级 · {n} 个主标签` · `Compose 扫描结果` ·
`Compose 备份 · {name}` · `备份列表 · {name}` · `镜像历史 · {name}` · `镜像标签 · {name}` ·
`镜像文件系统 · {path}` · `容器进程 · {name}` · `Compose 配置 · {name}` · `读取 Compose 文件 · {path}` ·
`下载容器文件 · {path}` · `下载 Compose 备份 · {name}` · `导出数据卷 · {name}` · `导出容器 · {name}`
Detail status strings: `正在下载` · `正在检测 c/t` · `正在读取升级状态`

### 24.7 Confirmation dialogs (all use buttons `取消` / `继续`)
| title | message |
|---|---|
| `确认停止` | `停止容器 {name}？` |
| `确认重启` | `重启容器 {name}？` |
| `确认删除` | `删除镜像 {name}？` |
| `确认删除` | `删除网络 {name}？` |
| `确认删除` | `删除数据卷 {name}？` |
| `确认删除` | `强制删除容器 {name}？` |
| `确认停止` | `停止 Compose 项目 {name}？` |
| `确认备份` | `备份 Compose 项目 {name}？` |
| `清空 Compose 备份` | `确定删除项目 {name} 的全部备份吗？` |
| `取消备份` | `取消 Compose 项目 {name} 的备份任务？` |
| `取消备份` | `取消数据卷 {name} 的备份任务？` |
| `批量删除镜像` | `确定删除已选择的 {n} 个镜像？正在使用的镜像会自动跳过。` |
| `清空任务` | `删除全部 Docker 任务记录？` |
| `清除升级状态` | `确定清除全部镜像升级检查记录吗？` |
| `移除标签` | `移除容器 {name} 的标签？` |

### 24.8 Empty states
`暂无容器` · `暂无镜像` · `暂无 Compose 项目` · `暂无 Docker 网络` · `暂无数据卷` · `暂无后台任务` · `暂无 Docker 日志`
Ranking-card empties: `容器统计暂不可用` · `正在读取容器统计` · `暂无容器统计数据`
Gauge a11y empty: `暂无数据`

### 24.9 Errors / notices
`容器统计暂时不可用` · `读取详情失败` · `下载失败` · `选择文件失败` · `选择上传文件失败` · `读取日志失败` ·
`读取 Compose 日志失败` · `读取 Dockerfile 失败` · `读取容器配置失败` · `检查容器更新失败` ·
`接口未返回 Compose 配置内容` · `接口未返回 Dockerfile 内容` · `未能确认镜像使用情况` · `检查镜像使用情况失败` ·
`所选镜像没有可检测的标签` · `请先选择需要检测的镜像` · `请先选择要删除的镜像` · `读取升级状态失败` ·
`检测镜像升级失败` · `请输入容器内文件路径` · `请输入 Compose 项目路径和文件路径` ·
`请输入 Compose 项目名称和备份文件` · `Compose 操作失败` ·
`Lucky 服务无法访问项目目录：{projectPath}。请将宿主机 Compose 目录按相同绝对路径读写挂载到 Lucky 容器。`
Notices: `Compose 创建任务正在后台执行` ·
`已选择 {n} 个未使用镜像，{used} 个正在使用[，{failed} 个无法确认]`

### 24.10 Overview / stats labels
`CPU` · `内存` · `下载` · `上传` · `读取` · `写入` · `逻辑核心` · `总可用内存` · `使用率 (%)` · `内存占用` ·
`容器名称` · `#` · `容器状态` · `运行中` · `已暂停` · `已退出` · `已创建` · `其它` · `CPU 使用率前 5` ·
`内存使用率前 5` · `连接中` · `连接中断` · `容器 {n}` (unnamed stat row fallback)
Container badge strings: `已暂停` · `运行中` · `已停止` · `运行: {duration}` with units `秒` `分钟` `小时` `天` `周` `个月`
Accessibility strings: `打开容器 {name} 操作菜单` · `打开镜像高级工具` · `检测已选择的 {n} 个镜像升级` ·
`查看镜像升级状态` · `取消选择当前显示的全部镜像` · `选择当前显示的全部镜像` · `正在检查未使用镜像` ·
`选择当前显示的未使用镜像` · `删除已选择的 {n} 个镜像` · `选择镜像 {name}` · `上一页 Docker 日志` ·
`下一页 Docker 日志` · `查看{label}` · `查看容器 {name}` · `{title}使用率`
Placeholder value strings: `--` · `-` · `N/A` · `0 B` · `<none>`

## 25. Swift 移植注意事项 (structural surprises)

25.1 **`containerStatsByKey` double-keys every row.** Each `DockerStatRow` is inserted under *both*
`row.key` and `row.name`, so a Swift dictionary must accept two lookups per row and tolerate a name
colliding with another row's id. Lookup at render time tries `keyOf(item)` then the display name.

25.2 **`paused` counts as running in the container list.** `dockerContainerState` returns `paused`
as a distinct state for the status chips, but the containers view's "running" predicate treats
`paused` as running (a paused container still shows the stop/restart affordances).

25.3 **Search is a whole-record JSON substring match.** `searchText(record)` is
`JSON.stringify(record).toLowerCase()`; a query matches if that string contains the lowered query.
This means users can match on keys, nested values, ids, labels — anything in the payload. Do not
reimplement it as a field-list search.

25.4 **Seven editor-only pseudo-types never reach the mutation under their own name:**
`container-file-download`, `image-filesystem-view`, `compose-discover`, `compose-read-file`,
`compose-backup-download`, `compose-config`, `compose-dockerfile`. They only open a form. On save,
`compose-config` → `compose-config-save` and `compose-dockerfile` → `compose-dockerfile-save`;
`mirror-remove` moves `value.mirror` into the request's `key` and drops it from `value`.

25.5 **Log pagination has no total count.** The "next page" button is enabled purely on
`dockerLogLines.length < 200` being false — i.e. a full page implies more pages. Page size 200,
offset arithmetic only; there is no server-provided total.

25.6 **`parseDockerBytes` is base 1000 unless the unit contains `i`.** `kB/MB/GB/TB` → 1000^n,
`KiB/MiB/GiB/TiB` → 1024^n. Getting this wrong changes every displayed byte figure.

25.7 **Clamping is asymmetric.** `dockerCpuPercent` clamps to 0…100 only in the direct-percent
branch; the computed/derived branch is unclamped and can exceed 100 (multi-core CPU %).

25.8 **Ranking bars mix two scales.** The memory bar's *width* is scaled by `memoryMax` (largest
value in the list) but its *colour* comes from `memoryPercent` thresholds 80/60. The CPU bar uses
thresholds 80/50. So a bar can be full-width and still green.

25.9 **`DockerGauge` is a 270° arc.** `arc = circumference * 0.75`, stroke dash offset derived from
that, whole shape rotated `135°`. A naive 360° `Circle().trim` will look wrong.

25.10 **Two hard-coded hex colours.** `imageAccent` = `#ff6482` (dark) / `#d63384` (light) and
`imageBackground` = `#4a1830` (dark) / `#fce7f3` (light). Everything else is semantic theme keys;
these two must be branched on `colors.mode`.

25.11 **The `其它` (other) chip uses a raw count**, not the `statusValue` helper used by the other
four chips — so it does not get the same `--`/unavailable treatment.

25.12 **Leading space in the container tile suffix.** The string is `` ` / ${containerCount}` ``
(space, slash, space). Reproduce verbatim.

25.13 **Closing the Compose creator does not cancel it.** Dismissing mid-flight leaves the backend
task running and sets the notice `Compose 创建任务正在后台执行`.

25.14 **Volume mutations key off the volume *name*, not `keyOf(item)`** — unlike containers,
images and networks. Same for the volume backup-cancel confirmation.

25.15 **Every FlatList's `ListHeaderComponent` contains the whole nav chrome** (PageHeader, tab bar,
search field, view-specific toolbars). The header, tabs and search therefore scroll away with the
list. A SwiftUI `List`/`ScrollView` must put them inside the scroll content, not pinned.

25.16 **All async detail writes are double-guarded** by a monotonic request-id ref *and* an
`AbortController`; a late response whose id ≠ current ref is dropped silently (no error surfaced).
Ports need the same stale-response suppression or the detail sheet will flicker between payloads.

25.17 **`collectDockerStats` walks arbitrary JSON.** BFS/DFS to depth 7 through wrapper keys
`["data","result","stats","list","containers"]`, accepting any object that satisfies
`hasDockerStatShape`. The stats endpoint's shape is not fixed.

25.18 **Eight action types have no explicit dispatch branch.** `container-start/stop/restart/pause/unpause`
and `compose-start/stop/restart` are served only by the `type.startsWith(...)` fall-throughs at L1603
and L1760, which strip the prefix and pass the remainder as the action verb. A Swift `switch` over an
enum must model these explicitly, and must keep them *after* the specific cases (e.g. `container-remove`
would otherwise be swallowed by the prefix rule).

25.19 **The compose fall-through validates before dispatch** and throws `Compose 项目名称或路径缺失`
if either `project_path` or `project_name` is blank — and wraps every failure in
`composeProjectError(error, projectPath)`, which is what produces the long mount-hint message.

## 26. `onSuccess` cache-invalidation matrix (L1850–L1901)

Dispatched by prefix, first match wins. `invalidate(...)` pushes onto an `invalidations` array that is
flushed with `queryClient.invalidateQueries` at the end.

| condition | invalidates |
|---|---|
| `type === "container-files"` | *(nothing — file contents do not change list metadata)* |
| `type.startsWith("container-")` | `containers`, `container-stats`, `overview` |
| ↳ + `container-commit` \| `container-version-switch` | also `images` |
| ↳ + `container-label-set` \| `container-label-remove` \| `container-group-set` | also `maintenance` |
| `type.startsWith("image-")` \|\| `images-remove-batch` | `images`, `overview` |
| `type.startsWith("compose-")` | `compose`, `overview` |
| ↳ + `compose-create` | also `tasks`, `containers`, `images` |
| ↳ + `type.includes("backup")` | also `maintenance` |
| `type.startsWith("network-")` | `networks`, `overview` |
| `type.startsWith("volume-")` | `volumes`, `overview` |
| ↳ + `type.includes("backup")` \|\| `volume-restore` | also `maintenance` |
| `type.startsWith("task-")` \|\| `tasks-clear` | `tasks` |
| `type.startsWith("group-")` | `containers`, `overview`, `maintenance` |
| `type === "config-save"` | `config` |
| `type.startsWith("mirror-")` | `mirrors` |
| `type === "upgrade-status-clear"` | `maintenance` |
| *else* | `overview` |

All keys are `["docker", <name>]`. After the flush, `container-files` additionally writes its result
into `output`.
