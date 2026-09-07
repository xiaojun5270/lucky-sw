# Behavioural specification — `structured-form.tsx` + `tunnel-form.tsx`

Source of truth (React Native / TypeScript):

- `C:\Users\xiaoj\Desktop\lucky\src\components\structured-form.tsx` (352 lines)
- `C:\Users\xiaoj\Desktop\lucky\src\components\tunnel-form.tsx` (277 lines)

Supporting files read for colour roles, helpers and consumer context:

- `C:\Users\xiaoj\Desktop\lucky\src\lib\theme.ts` — `useAppTheme()` colour roles
- `C:\Users\xiaoj\Desktop\lucky\src\types\lucky.ts` — `LuckyRecord = Record<string, unknown>`
- `C:\Users\xiaoj\Desktop\lucky\src\services\tunnels.ts` — `record()`, `TunnelKind`, `TunnelCollection`
- `C:\Users\xiaoj\Desktop\lucky\app\tunnels\[kind].tsx` — the only consumer of `TunnelForm`
- `C:\Users\xiaoj\Desktop\lucky\scripts\check-tunnels.cjs` — executable contract tests for the form helpers

## Exported symbols

| File | Export | Signature |
| --- | --- | --- |
| structured-form.tsx | `StructuredForm` | component `({ value: LuckyRecord; onChange: (value: LuckyRecord) => void })` |
| structured-form.tsx | `StructuredDataView` | component `({ value: unknown; depth?: number })`, `depth` defaults to `0` |
| tunnel-form.tsx | `TunnelFormType` | type `TunnelKind \| TunnelCollection \| 'stun-settings'` = `'stun' \| 'cloudflared' \| 'frp' \| 'ingress' \| 'proxies' \| 'visitors' \| 'stun-settings'` |
| tunnel-form.tsx | `tunnelDefaults` | `(type: TunnelFormType, mode?: string) => LuckyRecord` |
| tunnel-form.tsx | `validateTunnelForm` | `(type: TunnelFormType, value: LuckyRecord) => LuckyRecord` — throws `Error` |
| tunnel-form.tsx | `updateTunnelFormValue` | `(type: TunnelFormType, value: LuckyRecord, key: string, next: unknown) => LuckyRecord` |
| tunnel-form.tsx | `TunnelForm` | component `({ type, value, onChange, disabled = false })` |

Private internals that must be reproduced in the port:

- structured-form.tsx: `labels`, `fieldLabel`, `isRecord`, `FieldHeader`, `NumericField`, `PrimitiveField`, `AddField`, `ArrayField`, `RecordFields`.
- tunnel-form.tsx: `Field`, `field()`, `port()`, `webhookDefaults`, `webhookFields()`, `fields()`, `get()`, `set()`, `optionLabels`, `FormField`.

---

## 1. Colour roles (`useAppTheme()`)

Chosen by `useColorScheme() === 'dark'`. Only roles referenced by these two files are listed.

| Role | Light | Dark |
| --- | --- | --- |
| `card` | `#ffffff` | `#1c1c1e` |
| `mutedCard` | `#f2f2f7` | `#2c2c2e` |
| `primary` | `#007aff` | `#0a84ff` |
| `primarySoft` | `#e5f1ff` | `#0b2f52` |
| `text` | `#1d1d1f` | `#f5f5f7` |
| `subtext` | `#6e6e73` | `#a1a1a6` |
| `border` | `#e1e1e6` | `#3a3a3c` |
| `rowBorder` | `#e5e5ea` | `#38383a` |
| `danger` | `#ff3b30` | `#ff453a` |
| `dangerBg` | `#fff0ef` | `#3d1412` |
| `disabled` | `#aeaeb2` | `#636366` |
| `placeholder` | `#8e8e93` | `#8e8e93` |

Literal `#fff` is hard-coded for the "添加" button label text (not a theme role).

---

## 2. `labels` — key → Chinese label map (verbatim, 85 entries, order as in source)

Lookup is **exact, case-sensitive, whole-key** (`labels[key]`). No dot-path handling, no
normalisation, no prefix matching. Note deliberate duplicate values for different casings
(`name`/`Name`, `driver`/`Driver`, `image`/`images`/`Images`, `tag`/`Labels`, `TaskName`/`DDNSTaskName`).

```ts
const labels: Record<string, string> = {
  name: "名称",
  Name: "名称",
  image: "镜像",
  tag: "标签",
  repository: "仓库",
  architecture: "架构",
  config: "配置",
  operation: "操作",
  path: "路径",
  content: "内容",
  project_name: "项目名称",
  project_path: "项目路径",
  scan_path: "扫描路径",
  working_dir: "工作目录",
  filename: "文件名",
  file_path: "文件路径",
  target_path: "目标路径",
  config_file_name: "配置文件名",
  auto_start: "恢复后自动启动",
  volume_name: "数据卷名称",
  driver: "驱动",
  Driver: "驱动",
  Options: "选项",
  IPAM: "IP 地址管理",
  DriverOpts: "驱动选项",
  Labels: "标签",
  backup: "备份文件",
  mirror: "镜像加速地址",
  containers: "容器",
  images: "镜像",
  networks: "网络",
  volumes: "数据卷",
  build_cache: "构建缓存",
  disk_usage: "磁盘使用情况",
  LayersSize: "镜像层大小",
  Images: "镜像",
  Containers: "关联容器",
  Created: "创建时间",
  Size: "占用空间",
  SharedSize: "共享空间",
  VirtualSize: "虚拟大小",
  ContainersRunning: "运行中容器",
  ContainersStopped: "已停止容器",
  DockerRootDir: "Docker 数据目录",
  labels: "容器标签",
  containerGroups: "容器分组",
  collapsedStates: "分组折叠状态",
  orderMapping: "容器排序映射",
  composeBackup: "Compose 备份",
  volumeBackup: "数据卷备份",
  imageUpgrades: "镜像升级状态",
  imageRef: "镜像标签",
  checked: "检测结果",
  checkedCount: "检测成功",
  completedCount: "已完成",
  totalCount: "总数",
  inProgress: "检测中",
  statusError: "状态读取错误",
  removed: "已删除镜像",
  removedCount: "删除成功",
  unused: "未使用镜像",
  unusedCount: "未使用数量",
  used: "使用中镜像",
  usedCount: "使用中数量",
  failed: "失败项目",
  failedCount: "失败数量",
  error: "请求错误",
  TaskName: "任务名称",
  DDNSTaskName: "任务名称",
  Enable: "启用",
  Records: "域名记录",
  DNSProvider: "DNS 服务商",
  Domain: "域名",
  Domains: "域名",
  Remark: "备注名称",
  AddFrom: "证书来源",
  CertFile: "证书文件",
  KeyFile: "私钥文件",
  ExtParams: "扩展参数",
  CertsInfo: "证书信息",
  NotBeforeTime: "生效时间",
  NotAfterTime: "到期时间",
  SyncInfo: "同步信息",
  SyncClients: "同步客户端",
  ACMEing: "正在签发",
};
```

### 2.1 `fieldLabel(key)` fallback

```ts
function fieldLabel(key: string) {
  if (labels[key]) return labels[key];
  return key.replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2");
}
```

Rules, in order:

1. If `labels` has a **truthy** value for the exact key, return it. (An empty-string entry would fall
   through; none exist today.)
2. Otherwise replace **every** `_` with a single space (global).
3. Then insert a space between every lowercase-letter→uppercase-letter boundary (global).
   `ServerAddr` → `Server Addr`; `TCPMux` → `TCPMux` (no lowercase before the uppercase run);
   `useEncryption` → `use Encryption`; `WebhookURL` → `Webhook URL`;
   `my_field_Name` → `my field Name`.
4. Digits are never separated: `ICMPV4Src` → `ICMPV4Src`; `http2Origin` → `http2Origin`.

Swift port note: apply step 2 before step 3, and use regex replacement (not word-boundary
capitalisation), so an already-spaced or all-caps key is left untouched.

### 2.2 `isRecord(value)`

```ts
function isRecord(value: unknown): value is LuckyRecord {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
```

Truthy + object + not array. Therefore `null` is **not** a record, and `Date`/class instances would
be treated as records. In the Swift port the JSON value model should be an enum
(`.object`, `.array`, `.string`, `.number`, `.bool`, `.null`), and `isRecord` == `case .object`.

---

## 3. `StructuredForm` — component tree

```
StructuredForm(value, onChange)
└── RecordFields(value, onChange, depth: 0)
    ├── for each (key, item) of Object.entries(value)   // insertion order, no sorting
    │   ├── item is object  → inline header row + RecordFields(item, depth + 1)
    │   ├── item is array   → ArrayField(name: key, value: item, depth: depth)   // NOTE: same depth
    │   └── otherwise       → PrimitiveField(name: key, value: item)
    └── AddField(existingKeys: Object.keys(value))
```

Key facts:

- **Entry order is the JSON insertion order.** There is no sorting, grouping, or key filtering in the
  editable form. (`StructuredDataView` *does* filter — see §7.)
- **No keys are hidden** by `StructuredForm`. The only hiding happens one level up, in
  `TunnelForm`, when it computes the `extra` record it feeds to `StructuredForm` (see §17).
- `ArrayField` receives `depth` **unchanged** from `RecordFields`; only `RecordFields` increments it.
  `depth` affects nothing except `RecordFields`' own padding/border (see §6).

---

## 4. Value-kind → control decision table (`StructuredForm`)

Evaluated top-down; first match wins. `name` is the object key, or `第 N 项` for array items.

| # | Test | Control | Notes |
| --- | --- | --- | --- |
| 1 | `isRecord(item)` (object, non-null, non-array) | **Nested object**: bold header row + recursive `RecordFields` in a bordered box | Header text `fieldLabel(key)`; trailing trash icon deletes the whole key |
| 2 | `Array.isArray(item)` | **Array editor** (`ArrayField`) | Header + one row per item + 5 "add item" buttons |
| 3 | `typeof item === "boolean"` | **Switch row** | Label + `Switch`, single line |
| 4 | `typeof item === "number"` | **Numeric text field** (`NumericField`) | `keyboardType="numeric"`; free-text draft + commit-on-blur. **Not** a stepper — no +/- buttons anywhere |
| 5 | `name` matches `/content\|script\|dockerfile\|forbidden\|indexnames\|paths\|command/i` | **Multiline text area**, `minHeight: 112` | Regex tested against the *key name*, case-insensitive, substring match |
| 5a | …and `name` also matches `/content\|script\|dockerfile\|command/i` | same, plus `fontFamily: "monospace"` | `forbidden`, `indexnames`, `paths` are multiline but **not** monospace |
| 6 | anything else (`string`, `null`, `undefined`, bigint, symbol…) | **Single-line text field**, `minHeight: 44` | Displayed value: `value === null \|\| value === undefined ? "" : String(value)` |

There is **no select / picker / segmented control in `StructuredForm`.** Enumerations are only
rendered as option chips by `TunnelForm.FormField` when a `Field` carries `options` (§15).

Multiline / monospace regexes verbatim:

```ts
const multiline = /content|script|dockerfile|forbidden|indexnames|paths|command/i.test(name);
// monospace only when multiline is true AND:
/content|script|dockerfile|command/i.test(name)
```

Because the match is a case-insensitive substring test, keys such as `CallScriptContent`,
`Dockerfile`, `ForbiddenPaths`, `IndexNames`, `command`, `Commands`, `paths`, `WebhookRequestBody`
(no — does not match) behave accordingly. Any key containing `path` **singular** does *not* match
(`paths` is required, with the `s`).

Type changes are **not** offered for existing values: once a key holds a string it stays a string
field; the only way to change a value's kind is to delete the key and re-add it via `AddField`.

Editing a text field always writes back a **string**; editing a numeric field always writes back a
**number**; a boolean switch always writes back a **bool**. `null`/`undefined` values are edited as
strings and become `""` on first keystroke, i.e. a `null` becomes `""` once touched.

---

## 5. Control visual specs (exact values)

### 5.1 `FieldHeader({ name, onRemove })`

| Property | Value |
| --- | --- |
| Container | row, `minHeight: 24`, `alignItems: center`, `gap: 8` |
| Label | `flex: 1`, colour `text`, `fontSize: 12`, `fontWeight: "700"`, content `fieldLabel(name)` |
| Remove button | rendered only when `onRemove` present: `28 × 28`, `borderRadius: 8`, centred, **no background** |
| Remove icon | lucide `Trash2`, `size: 14`, colour `danger` |
| Accessibility label | `` `删除${fieldLabel(name)}` `` |

### 5.2 `NumericField` (memoised)

Container: `View { gap: 6 }` → `FieldHeader` → `TextInput`.

| Property | Value |
| --- | --- |
| `minHeight` | `44` |
| `borderRadius` | `12` |
| `borderWidth` / colour | `1` / `border` |
| `backgroundColor` | `card` |
| text colour | `text` |
| `paddingHorizontal` / `paddingVertical` | `12` / `8` |
| `fontSize` | `12` |
| keyboard | `numeric` |
| `autoCapitalize` | `none` |
| `autoCorrect` | `false` |

State machine (must be reproduced exactly — it is what keeps typing `-`, `1.`, `1e` usable):

```ts
const [draft, setDraft] = useState(String(value));
const [focused, setFocused] = useState(false);
useEffect(() => { if (!focused) setDraft(String(value)); }, [focused, value]);

onFocus:      setFocused(true)
onChangeText: setDraft(text); if (/^-?\d+(?:\.\d+)?$/.test(text)) onChange(Number(text))
onBlur  ():   const parsed = Number(draft);
              if (draft.trim() && Number.isFinite(parsed)) onChange(parsed);
              else setDraft(String(value));      // revert
              setFocused(false)
```

- While focused, external `value` changes do **not** overwrite the draft.
- Live commit happens only for a strictly well-formed decimal (optional leading `-`, digits,
  optional `.` + digits). No exponent, no leading `+`, no leading `.`.
- On blur, a looser parse is used: any string `Number()` can turn into a finite number commits
  (so `" 12 "`, `"0x10"`, `"1e3"` commit on blur). Empty/whitespace or `NaN` reverts to the last
  committed value.

### 5.3 Boolean row (inside `PrimitiveField`)

| Property | Value |
| --- | --- |
| Container | row, `minHeight: 44`, `alignItems: center`, `gap: 12` |
| Label | `flex: 1`, colour `text`, `fontSize: 13`, `fontWeight: "600"`, `fieldLabel(name)` |
| Switch | `trackColor: { false: disabled, true: primary }` |
| Remove button | `32 × 32`, `borderRadius: 9`, centred, no background, `Trash2` `size: 14` colour `danger` |
| Accessibility label (remove) | `` `删除${fieldLabel(name)}` `` |

Note the label here is `fontSize 13 / weight 600`, **different** from `FieldHeader`'s `12 / 700`, and
the remove hit box is `32 × 32 / radius 9` instead of `28 × 28 / radius 8`.

### 5.4 String / multiline field (inside `PrimitiveField`)

Container: `View { gap: 6 }` → `FieldHeader(name, onRemove)` → `TextInput`.

| Property | Single-line | Multiline |
| --- | --- | --- |
| `minHeight` | `44` | `112` |
| `paddingVertical` | `8` | `10` |
| `paddingHorizontal` | `12` | `12` |
| `textAlignVertical` | `center` | `top` |
| `borderRadius` | `12` | `12` |
| `borderWidth` / colour | `1` / `border` | `1` / `border` |
| `backgroundColor` | `card` | `card` |
| text colour | `text` | `text` |
| `fontSize` | `12` | `12` |
| `fontFamily` | default | `monospace` when key matches `/content\|script\|dockerfile\|command/i`, else default |
| keyboard | `default` | `default` |
| `autoCapitalize` / `autoCorrect` | `none` / `false` | `none` / `false` |

No placeholder text is set. No character limit. `onChangeText` passes the raw string straight to
`onChange` (so the stored JSON value becomes a string).

### 5.5 `AddField` — collapsed state

Single full-width `Pressable`:

| Property | Value |
| --- | --- |
| `height` | `40` |
| `borderRadius` | `12` |
| `borderWidth` / colour | `1` / `border` |
| Layout | row, centred both axes, `gap: 6` |
| Icon | lucide `Plus`, `size: 15`, colour `primary` |
| Text | `添加字段`, colour `primary`, `fontSize: 12`, `fontWeight: "700"` |

No background fill (transparent over the parent).

### 5.6 `AddField` — expanded state

Container: `View { gap: 8, paddingTop: 8, borderTopWidth: 1, borderTopColor: rowBorder }`.

1. **Key name input**

| Property | Value |
| --- | --- |
| `height` | `44` (fixed, not `minHeight`) |
| `borderRadius` | `12` |
| `borderWidth` / colour | `1` / `border` |
| `backgroundColor` | **none** (transparent — differs from every other input) |
| text colour | `text` |
| `paddingHorizontal` | `11` (not 12) |
| placeholder | `字段名称`, colour `placeholder` |
| `autoCapitalize` | `none` |

2. **Duplicate warning** — shown when `existingKeys.includes(key.trim())`:
   `Text { color: danger, fontSize: 11 }` = `该字段已存在`.

3. **Kind chips** — `View { flexDirection: row, flexWrap: wrap, gap: 6 }`, options in this exact order:

| `kind` value | Chinese label | Initial JSON value on add |
| --- | --- | --- |
| `text` | `文本` | `""` (empty string) |
| `number` | `数字` | `0` |
| `switch` | `开关` | `false` |
| `object` | `对象` | `{}` |
| `list` | `列表` | `[]` |

Chip style: `paddingHorizontal: 10`, `height: 36`, `borderRadius: 10`, `borderWidth: 1`,
`borderColor: selected ? primary : border`, `backgroundColor: selected ? primarySoft : card`,
centred; label `fontSize: 11`, `fontWeight: "700"`, colour `selected ? primary : text`.
Default selection is `text`. Selection is single-choice, always one selected.

4. **Action row** — `View { flexDirection: row, gap: 8 }`

| Button | Style | Text |
| --- | --- | --- |
| Cancel | `flex: 1`, `height: 40`, `borderRadius: 12`, `borderWidth: 1` / `border`, centred | `取消`, colour `subtext`, `fontWeight: "700"` (no explicit fontSize) |
| Add | `flex: 1`, `height: 40`, `borderRadius: 12`, `backgroundColor: valid ? primary : disabled`, centred | `添加`, colour `#fff`, `fontWeight: "800"` |

`normalizedKey = key.trim()`; `duplicate = existingKeys.includes(normalizedKey)`;
`valid = normalizedKey && !duplicate`. The Add button is `disabled` when not valid.

Behaviour:

- **Cancel**: `setOpen(false); setKey("")`. The selected `kind` is **not** reset — it persists for the
  next time the sheet is opened.
- **Add**: `onAdd(normalizedKey, initial)` where `initial` comes from the table above, then
  `setOpen(false); setKey("")` (kind again retained). The parent does
  `onChange({ ...value, [key]: item })`, so the new key is appended **last** in insertion order; if
  the key already existed it would overwrite in place, but the duplicate guard prevents that.
- Keys are user-typed only — there is **no auto-generated key naming** (`newKey1`, `field_2`, …).
- Trailing/leading whitespace is stripped from the key before use.

---

## 6. `ArrayField` — array editor

Container: `View { gap: 9 }`.

1. `FieldHeader(name, onRemove)` — `onRemove` deletes the whole array key from the parent object.
2. One row per item.
3. A wrapping row of five "append" buttons.

### 6.1 Item row

```
View { flexDirection: row, alignItems: "flex-start", gap: 8 }
├── View { flex: 1 }
│   ├── isRecord(item)      → RecordFields(item, depth + 1)        // no label, bordered box
│   ├── Array.isArray(item) → ArrayField(name: `第 ${index+1} 项`, item, depth + 1)  // no onRemove
│   └── otherwise           → PrimitiveField(name: `第 ${index+1} 项`, item)         // no onRemove
└── Pressable  (delete this item)
```

Delete button:

| Property | Value |
| --- | --- |
| Size | `38 × 38` |
| `borderRadius` | `12` |
| `backgroundColor` | `dangerBg` (filled — unlike the header trash buttons) |
| `marginTop` | `0` when the item is an object or array, **`30`** when the item is a scalar |
| Icon | `Trash2`, `size: 15`, colour `danger` |
| Accessibility label | `删除列表项` (constant, not indexed) |

The `marginTop: 30` offset exists so the button lines up with the input rather than the
`FieldHeader` above it. Object/array items have no header of their own inside the row, hence `0`.

Nested items inside an array never render their own remove affordance (`onRemove` is omitted); the
row-trailing trash button is the only removal path. Nested **objects** inside an array *do* render
their own `AddField` (because `RecordFields` always appends one) and their own per-key remove
buttons.

### 6.2 Append buttons

`View { flexDirection: row, flexWrap: wrap, gap: 8 }`, five buttons in this exact order:

| Label | Appended value |
| --- | --- |
| `文本项` | `""` |
| `数字项` | `0` |
| `开关项` | `false` |
| `对象项` | `{}` |
| `列表项` | `[]` |

Source tuple list: `[['文本', ''], ['数字', 0], ['开关', false], ['对象', {}], ['列表', []]]`; the
button text is `` `${label}项` ``. Each append is `onChange([...value, item])` — always to the **end**.

Button style: `flexGrow: 1`, `flexBasis: 92`, `height: 40`, `borderRadius: 12`, `borderWidth: 1` /
`border`, row, centred, `gap: 5`; icon lucide `Plus` `size: 14` colour `primary`; text `fontSize: 11`,
`fontWeight: "700"`, colour `primary`. (`flexBasis: 92` + `flexGrow: 1` means roughly 3 per row on a
phone, stretched to fill.)

### 6.3 Stable item identity (must be ported)

```ts
const nextKeyRef  = useRef(0);
const itemKeysRef = useRef<string[]>([]);
while (itemKeysRef.current.length < value.length) itemKeysRef.current.push(`${name}-${nextKeyRef.current++}`);
if (itemKeysRef.current.length > value.length) itemKeysRef.current.length = value.length;
```

Each rendered row is keyed by `` `${name}-${n}` `` with a monotonically increasing `n` per array
instance. On remove, the key at that index is spliced out (`filter` by index) so surviving rows keep
their identity; on append, a fresh key is pushed. If the array shrinks from outside, surplus keys are
truncated from the tail.

Swift port: each row needs a persistent identity token (e.g. a `[UUID]` array kept in parallel with
the values, spliced identically) so `TextField` focus/draft state is not lost when a neighbour is
deleted. Using the array index as `id` would break the numeric-draft state.

### 6.4 Mutation semantics

| Operation | Implementation |
| --- | --- |
| Update item *i* | `value.map((entry, j) => j === i ? next : entry)` |
| Remove item *i* | `value.filter((_, j) => j !== i)` and splice the same index out of the key list |
| Append | `[...value, item]` |
| Reorder | **Not supported.** There is no drag handle, no move-up/move-down, no sorting anywhere in `StructuredForm` / `ArrayField`. |

---

## 7. `RecordFields` — object editor

```ts
<View style={{ gap: 12, padding: depth ? 12 : 0, borderWidth: depth ? 1 : 0,
               borderColor: colors.border, borderRadius: 14 }}>
```

| Depth | `padding` | `borderWidth` | `borderRadius` |
| --- | --- | --- | --- |
| `0` (root) | `0` | `0` | `14` (irrelevant with no border/bg) |
| `>= 1` | `12` | `1`, colour `border` | `14` |

Indentation is therefore **not** proportional to depth: every nested level adds a bordered box with
exactly `12` of padding on all sides, so visual inset accumulates at `12 pt` per level (plus the
`1 pt` border). There is no per-depth colour ramp and no background fill on the box.

Between-entry vertical rhythm: `gap: 12` inside `RecordFields`; each entry is wrapped in
`View { gap: 7 }` (label-to-control spacing for nested-object entries).

Nested-object entry header (case 1 of the decision table):

| Property | Value |
| --- | --- |
| Row | `flexDirection: row`, `alignItems: center`, `gap: 8` |
| Label | `flex: 1`, colour `text`, `fontSize: 12`, `fontWeight: "800"` (heavier than `FieldHeader`'s 700) |
| Remove | bare `Pressable` with **no size or radius styling** (icon-sized hit box), `Trash2` `size: 14` colour `danger` |
| Accessibility label | `` `删除${fieldLabel(key)}` `` |

Removal of a key: `const next = { ...value }; delete next[key]; onChange(next);` — remaining key
order is preserved. Re-adding the key later puts it at the end.

`AddField` is always rendered as the **last** child of every `RecordFields`, at every depth,
including objects nested inside arrays and empty objects. An empty object therefore renders as a
bordered box (if nested) containing only the `添加字段` button.

There is **no collapse/expand affordance anywhere in `StructuredForm`.** No chevrons, no disclosure
groups, no "collapsed" state. (`collapsedStates` in the `labels` map is a Docker data key, not a UI
feature of this component.) `TunnelForm` is the only place with expand/collapse (§16).

---

## 8. `StructuredDataView` — read-only tree

`({ value: unknown, depth = 0 })`. Three mutually exclusive branches, in this order.

### 8.1 Object branch — `isRecord(value)`

```ts
const entries = Object.entries(value).filter(([key]) => !["ret", "msg"].includes(key));
```

- **Hidden keys: `ret` and `msg`, at every depth** (the Lucky API envelope fields). Exact,
  case-sensitive. No other key is filtered.
- If `entries.length === 0` → `Text { color: subtext, fontSize: 12 }` = `暂无数据`.
  (This also fires for an object whose only keys were `ret`/`msg`.)
- Otherwise `View { gap: 9 }` containing `entries.slice(0, 200)`:

```ts
<View style={{ gap: 5,
               paddingLeft:      depth ? 10 : 0,
               borderLeftWidth:  depth ? 1  : 0,
               borderLeftColor:  colors.border }}>
  <Text style={{ color: subtext, fontSize: 11, fontWeight: "700" }}>{fieldLabel(key)}</Text>
  <StructuredDataView value={item} depth={depth + 1} />
</View>
```

| Depth | `paddingLeft` | left rule |
| --- | --- | --- |
| `0` | `0` | none |
| `>= 1` | `10` | `1 pt`, colour `border` |

So indentation is a flat `10 pt` + hairline rule per nesting level from level 1 onwards
(root children are flush, their children are inset 10, grandchildren 20, …).

- Overflow footer when `entries.length > 200`:
  `Text { color: subtext, fontSize: 11, textAlign: "center" }` =
  `` `仅显示前 200 个字段，共 ${entries.length} 个` `` → e.g. `仅显示前 200 个字段，共 350 个`.

### 8.2 Array branch — `Array.isArray(value)`

- Empty array → `Text { color: subtext, fontSize: 12 }` = `暂无项目`.
- Otherwise `View { gap: 8 }` containing `value.slice(0, 200)`, each item in a card:

```ts
<View style={{ gap: 5, padding: 10, borderRadius: 12, backgroundColor: colors.mutedCard }}>
  <Text style={{ color: subtext, fontSize: 10, fontWeight: "700" }}>{`第 ${index + 1} 项`}</Text>
  <StructuredDataView value={item} depth={depth + 1} />
</View>
```

Note the array item card ignores `depth` entirely (no left rule, no depth-varying padding) — it is
always `mutedCard` fill, `radius 12`, `padding 10`. Item index label is `fontSize: 10 / weight 700`,
i.e. one step smaller than object keys (`11`).

- Overflow footer when `value.length > 200`:
  `` `仅显示前 200 项，共 ${value.length} 项` `` — same style as the object footer
  (`subtext`, `11`, centred).

### 8.3 Scalar branch (everything else)

```ts
const text = typeof value === "boolean" ? (value ? "是" : "否")
           : value === null || value === undefined || value === "" ? "--"
           : String(value);
return <Text selectable style={{ color: colors.text, fontSize: 12, lineHeight: 18 }}>{text}</Text>;
```

| Input | Rendered |
| --- | --- |
| `true` | `是` |
| `false` | `否` |
| `null` | `--` |
| `undefined` | `--` |
| `""` | `--` |
| `0` | `0` (zero is **not** `--`) |
| number | `String(n)` — JS number formatting: `1e+21`, `0.1`, `-0`→`0`, `NaN`→`NaN`, `Infinity`→`Infinity` |
| any other string | verbatim, full length |

Text is **selectable** (long-press to copy). `fontSize: 12`, `lineHeight: 18`, colour `text`.

### 8.4 Explicit non-features of `StructuredDataView`

- **No JSON pretty-printing.** `JSON.stringify` is never called. Nested structures are always
  expanded into the label/card tree above; a scalar is always `String(value)`.
- **No string truncation.** Long strings wrap and render in full; there is no `numberOfLines`, no
  ellipsis, no "show more". The *only* truncation is the 200-entry / 200-item cap per container.
- **No collapse/expand**, no chevrons, no tap targets other than text selection.
- **No sorting or grouping** — insertion order, always.
- The 200 cap applies **per container**, independently at every depth.
- Recursion is unbounded; a cyclic object would recurse forever (real payloads are JSON, so acyclic).

---

## 9. Complete Chinese string inventory — `structured-form.tsx`

| String | Where |
| --- | --- |
| `删除` + `fieldLabel(name)` | accessibilityLabel of every per-field trash button (`FieldHeader`, boolean row, nested-object header) |
| `添加字段` | `AddField` collapsed button |
| `字段名称` | `AddField` key input placeholder |
| `该字段已存在` | `AddField` duplicate-key warning |
| `文本` / `数字` / `开关` / `对象` / `列表` | `AddField` kind chips |
| `取消` | `AddField` cancel button |
| `添加` | `AddField` confirm button |
| `文本项` / `数字项` / `开关项` / `对象项` / `列表项` | `ArrayField` append buttons |
| `第 N 项` | array item field label (`ArrayField`) and array item card header (`StructuredDataView`) — note the ASCII space after `第` and before `项` |
| `删除列表项` | accessibilityLabel of the array row delete button |
| `暂无数据` | `StructuredDataView`, object with no visible entries |
| `暂无项目` | `StructuredDataView`, empty array |
| `仅显示前 200 个字段，共 N 个` | `StructuredDataView` object overflow footer |
| `仅显示前 200 项，共 N 项` | `StructuredDataView` array overflow footer |
| `是` / `否` | boolean scalar rendering |
| `--` | null / undefined / empty-string scalar rendering |

Plus all 85 values of the `labels` map (§2).

---
---

# Part II — `tunnel-form.tsx`

## 10. `Field` model and helpers

```ts
type Field = {
  key: string;                    // dot-path, e.g. "Params.ServerAddr" or "Options.SafeMode"
  label: string;                  // Chinese label, shown verbatim
  type?: 'number' | 'switch' | 'lines' | 'multiline' | 'secret';   // undefined = plain text
  options?: string[];             // presence turns the control into option chips
  required?: boolean;
  min?: number;
  max?: number;
};

const field = (key, label, type?, extra: Partial<Field> = {}): Field => ({ key, label, type, ...extra });
const port  = (key, label, required = false) =>
  field(key, label, 'number', { min: required ? 1 : 0, max: 65535, required });
```

`port()` therefore always means: integer, `max 65535`, `min 1` if required else `min 0`.

Control mapping for `TunnelForm` (see §16 for pixel values):

| `Field` shape | Control |
| --- | --- |
| `type: 'switch'` | single-line label + `Switch`, `minHeight 46` |
| `options: [...]` (any `type`) | wrapping row of radio chips; `options` **wins over** `type` |
| `type: 'number'` | text input, `keyboardType: 'number-pad'` |
| `type: 'secret'` | text input, `secureTextEntry` until the eye toggle is tapped |
| `type: 'lines'` | multiline input; value is `string[]` joined/split on `\n` |
| `type: 'multiline'` | multiline input, plain string |
| `type: undefined` | single-line text input |

### 10.1 Dot-path accessors

```ts
function get(value: LuckyRecord, key: string): unknown {
  return key.split('.').reduce<unknown>((current, part) => record(current)[part], value);
}
function set(value: LuckyRecord, key: string, next: unknown): LuckyRecord {
  const [head, ...tail] = key.split('.');
  return { ...value, [head]: tail.length ? set(record(value[head]), tail.join('.'), next) : next };
}
```

`record(v)` (from `src/services/tunnels.ts`) = `v && typeof v === 'object' && !Array.isArray(v) ? v : {}`.
Consequences to reproduce: `get` on a missing path yields `undefined` without throwing; `set` on a
missing/ non-object intermediate silently replaces it with a fresh object. Nesting depth used in
practice is 2 (`Params.X`, `Options.X`, `originRequest.X`, `transport.X`, `natTraversal.X`).

---

## 11. `webhookDefaults` and `webhookFields()`

```ts
const webhookDefaults = {
  WebhookEnable: false, WebhookOnlyAddrChange: true, WebhookURL: '', WebhookMethod: 'post',
  WebhookHeaders: [], WebhookRequestBody: '',
  WebhookDisableCallbackSuccessContentCheck: true, WebhookSuccessContent: [],
  WebhookProxy: '', WebhookProxyAddr: '', WebhookProxyUser: '', WebhookProxyPassword: '',
  RetryCount: 0, RetryInterval: 500,
};
```

`webhookFields(value)` — dynamic, re-evaluated on every render:

If `!value.WebhookEnable` (falsy) → exactly one field:

| label | key | type |
| --- | --- | --- |
| `启用 Webhook` | `WebhookEnable` | switch |

Otherwise, in this exact order:

| # | label | key | type | options / limits | required |
| --- | --- | --- | --- | --- | --- |
| 1 | `启用 Webhook` | `WebhookEnable` | switch | | |
| 2 | `仅地址变更时通知` | `WebhookOnlyAddrChange` | switch | | |
| 3 | `Webhook 地址` | `WebhookURL` | text | | ✔ |
| 4 | `请求方法` | `WebhookMethod` | chips | `get`, `post`, `put`, `patch` | ✔ |
| 5 | `请求头` | `WebhookHeaders` | lines | | |
| 6 | `请求内容` | `WebhookRequestBody` | multiline | **only when `WebhookMethod !== 'get'`** | |
| 7 | `重试次数` | `RetryCount` | number | `0…10` | |
| 8 | `重试间隔（毫秒）` | `RetryInterval` | number | `500…10000`, **only when `Number(RetryCount) > 0`** | |
| 9 | `跳过响应内容检查` | `WebhookDisableCallbackSuccessContentCheck` | switch | | |
| 10 | `成功响应关键字` | `WebhookSuccessContent` | lines | **only when `!WebhookDisableCallbackSuccessContentCheck`** | ✔ |
| 11 | `代理类型` | `WebhookProxy` | chips | `''`, `http`, `https`, `socks5`, `dns` | |
| 12 | `代理地址` | `WebhookProxyAddr` | text | **only when `WebhookProxy` truthy**; `required` iff `WebhookProxy !== 'dns'` | conditional |
| 13 | `代理账号` | `WebhookProxyUser` | text | only when `WebhookProxy` truthy | |
| 14 | `代理密码` | `WebhookProxyPassword` | secret | only when `WebhookProxy` truthy | |

`webhookFields` is appended to the **non-advanced** field list of `stun` and `stun-settings` only.

---

## 12. `tunnelDefaults(type, mode?)` — verbatim payload shapes

The returned object **is** the payload that is later PUT/POSTed (after `validateTunnelForm`
coercion), so its keys are the exact wire keys. Fall-through order in the source is
`stun-settings → stun → cloudflared → frp → ingress → proxies → (else) visitors`.

### 12.1 `stun-settings`

```ts
{ EnableModule: true, GlobalStunServerList: [], ...webhookDefaults }
```

### 12.2 `stun` — top-level keys

```ts
{
  Key: '', Name: '', Enable: true, StunType: 'tcp4', DiaglogShowMode: 'simple', StunListenType: 'ip',
  ListenIP: '', ListenPort: 0, SpecifyNetworkInterface: '', NetworkInterfaceReg: '',
  UseGlobalStunServerList: true, StunServerList: ['stun.miwifi.com:3478'], TcpKeepAliveServerList: [],
  DisablePortForward: false, TargetAddressList: ['127.0.0.1'], TargetPort: 80,
  AutoOptionsFirewall: true, NatPMP: false, NatPMPGateway: '', UPnP: false, UPnPGawayIP: '',
  UPnPLocalPort: 0, UPnpLocalHost: '', UpnPDiyControlAPIUrl: '',
  StunHeartbeatInterval: 2300, StunTimeout: 3000, StunRetryInterval: 3000, StunAutoRetry: true,
  DisableStunAvalidCheck: false,
  AutoAddPubAddrWhiteList: false, LogLevel: 4, LogOutputToConsole: false,
  AccessLogMaxNum: 128, WebListShowLastLogMaxCount: 20,
  GlobalWebhook: false, CallScript: false, CallScriptContent: '',
  ...webhookDefaults,
  Options: { /* see 12.3 */ },
}
```

Note the upstream typos, which must be preserved on the wire: `DiaglogShowMode` (not `Dialog`),
`UPnPGawayIP` (not `Gateway`), `UPnpLocalHost` (lowercase `p`), `UpnPDiyControlAPIUrl`,
`DisableStunAvalidCheck` (not `Avail`), `SingleProxyMaxUDPReadTargetDatagoroutineCount`,
`SinglePortReceSpeedLimit` / `RuleReceSpeedLimit` (`Rece`, not `Receive`).

### 12.3 `stun` → `Options`

```ts
Options: {
  DisableSelfForwardingCheck: false,
  SingleProxyMaxTCPConnections: 256,
  SingleProxyMaxUDPReadTargetDatagoroutineCount: 32,
  UDPShortMode: false,
  SafeMode: 'blacklist',
  TCPListenTLS: false, TCPRelayTLS: false, TCPRelayTLSServerName: '',
  TCPRelayTLSInsecureSkipVerify: false,
  TCPStreamEncryptionSource: false, TCPStreamEncryptionAccept: false, TCPStreamEncryptionKey: '',
  SinglePortSpeedLimit: false, SinglePortSendSpeedLimit: 0, SinglePortReceSpeedLimit: 0,
  RuleSpeedLimit: false, RuleSendSpeedLimit: 0, RuleReceSpeedLimit: 0,
  UDPSessionTimeout: 30000,
  UDPPacketSourceEncryption: false, UDPPacketAcceptEncryption: false, UDPPacketEncryptionKey: '',
  UDPPacketSize: 1500,
}
```

`RuleSpeedLimit`, `RuleSendSpeedLimit`, `RuleReceSpeedLimit` have **no** UI field — they survive only
via the payload defaults (and, for `stun`, are never even reachable through 其他参数 because that
block is hidden for `stun`).

### 12.4 `cloudflared`

```ts
{
  Key: '', Remark: '', Enable: true, Type: mode ?? 'tunnel',
  Params: mode === 'access'
    ? { Hostname: '', URL: '', HeaderList: '', Destination: '', TokenId: '', TokenSecret: '',
        ConnectTo: '', UserAgent: '', NoTlsVerify: false }
    : { Token: '', EdgeIpVersion: 'auto', HaConnections: 4, Protocol: 'http2', EdgeBindAddress: '',
        ICMPV4Src: '', ICMPV6Src: '', NoTlsVerify: false, Network: 'tcp4', ListenIP: '127.0.0.1',
        ListenPort: 60000, CFApiToken: '', CFAccountId: '', CFTunnelId: '' },
}
```

`mode` selects the `Params` shape; the `tunnel` shape is the fallback for any `mode` other than
`'access'` (including `undefined`). `Network`, `ListenIP`, `ListenPort` in the tunnel shape have no UI
field (they reach 其他参数). Note `NoTlsVerify` (lowercase `ls`).

### 12.5 `frp`

```ts
{
  Key: '', Remark: '', Enable: true, Type: mode ?? 'client', Proxies: [], Visitors: [],
  Params: mode === 'server'
    ? { BindAddr: '0.0.0.0', BindPort: 7000, Token: '', ProxyBindAddr: '', KCPBindPort: 0,
        QUICBindPort: 0, VhostHTTPPort: 0, VhostHTTPSPort: 0, VhostHTTPTimeout: 60,
        TCPMuxHTTPConnectPort: 0, TCPMuxPassthrough: false, TCPMux: true,
        TCPMuxKeepaliveInterval: 60, TCPKeepalive: 7200, MaxPoolCount: 5, MaxPortsPerClient: 0,
        AllowPorts: '', HeartbeatTimeout: 90, UserConnTimeout: 10, TLSOnly: false,
        UDPPacketSize: 1500, DetailedErrorsToClient: true, DashboardPort: 0, DashboardUser: 'admin' }
    : { ServerAddr: '', ServerPort: 7000, User: '', AuthMethod: 'token', Token: '',
        AuthAdditionalScopes: [], Protocol: 'tcp', NatHoleStunServer: '', DialServerTimeout: 10,
        DialServerKeepalive: 7200, ConnectServerLocalIP: '', ProxyURL: '', PoolCount: 1,
        TCPMux: true, TCPMuxKeepaliveInterval: 60, HeartbeatInterval: 30, HeartbeatTimeout: 90,
        TLSEnable: true, TLSServerName: '', DisableCustomTLSFirstByte: true,
        TLSInsecureSkipVerify: false, UDPPacketSize: 1500, DNSServer: '', LoginFailExit: false,
        Start: [], Metadatas: {}, AdminPort: 0, AdminUser: 'admin',
        OIDCClientID: '', OIDCClientSecret: '', OIDCAudience: '', OIDCScope: '',
        OIDCTokenEndpointURL: '' },
}
```

`Proxies` / `Visitors` are always emitted (as `[]` for a new instance) but are **never** edited by
`TunnelForm` — they are explicitly excluded from 其他参数 and edited through separate
`proxies` / `visitors` editors. The consumer additionally deletes the lowercase runtime aliases
`proxies` / `visitors` before saving (`app/tunnels/[kind].tsx`).

### 12.6 `ingress` (cloudflared child)

```ts
{ hostname: '', path: '', service: 'http://127.0.0.1:80',
  originRequest: { noTLSVerify: false, originServerName: '', httpHostHeader: '', http2Origin: false } }
```

### 12.7 `proxies` (frp child)

```ts
{ name: '', type: 'tcp', disabled: false, localIP: '127.0.0.1', localPort: 80, remotePort: 8080,
  useEncryption: false, useCompression: false, proxyProtocolVersion: '', plugin: '',
  natTraversal: { disableAssistedAddrs: false } }
```

### 12.8 `visitors` (frp child, the `else` branch — also used for any unknown type)

```ts
{ name: '', type: 'stcp', disabled: false, serverName: '', secretKey: '', bindAddr: '127.0.0.1',
  bindPort: 8080, serverUser: '', transport: { useEncryption: false, useCompression: false },
  protocol: 'quic', keepTunnelOpen: false, maxRetriesAnHour: 8, minRetryInterval: 90,
  fallbackTo: '', fallbackTimeoutMs: 0 }
```

---

## 13. `fields(type, value, advanced)` — full schema

Order in the tables **is** render order. "cond" = the field is only present when the condition holds.
`record(value.Options)` is used for `Options.*` conditions (guards against a missing `Options`).

### 13.1 `stun-settings` (`advanced` → always `[]`)

| # | label | key | control | cond |
| --- | --- | --- | --- | --- |
| 1 | `启用 STUN 模块` | `EnableModule` | switch | |
| 2 | `全局 STUN 服务器` | `GlobalStunServerList` | lines | |
| 3… | *…all of `webhookFields(value)` (§11)* | | | |

### 13.2 `stun`, basic (`advanced = false`)

| # | label | key | control | limits / options | required | cond |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `规则名称` | `Name` | text | | ✔ | |
| 2 | `启用规则` | `Enable` | switch | | | *hidden by `TunnelForm` when `!value.Key`* |
| 3 | `配置模式` | `DiaglogShowMode` | chips | `simple`, `diy` | | |
| 4 | `穿透协议` | `StunType` | chips | `tcp4`, `udp4` | | |
| 5 | `监听端口（0 为自动）` | `ListenPort` | number | `0…65535` | | |
| 6 | `自动配置防火墙` | `AutoOptionsFirewall` | switch | | | |
| 7 | `UPnP` | `UPnP` | switch | | | |
| 8 | `UPnP 网关 IP` | `UPnPGawayIP` | text | | | `value.UPnP` |
| 9 | `UPnP 客户端本地 IP` | `UPnpLocalHost` | text | | | `value.UPnP` |
| 10 | `UPnP 控制接口地址` | `UpnPDiyControlAPIUrl` | text | | | `value.UPnP` |
| 11 | `NAT-PMP` | `NatPMP` | switch | | | |
| 12 | `NAT-PMP 网关` | `NatPMPGateway` | text | | | `value.NatPMP` |
| 13 | `映射的本地端口` | `UPnPLocalPort` | number | `0…65535` | | `(UPnP \|\| NatPMP) && DisablePortForward` |
| 14 | `仅获取公网地址` | `DisablePortForward` | switch | | | |
| 15 | `跳过 STUN 有效性检查` | `DisableStunAvalidCheck` | switch | | | `!DisablePortForward` |
| 16 | `目标地址` | `TargetAddressList` | lines | | ✔ | `!DisablePortForward` |
| 17 | `目标端口` | `TargetPort` | number | `1…65535` | ✔ | `!DisablePortForward` |
| 18 | `执行自定义脚本` | `CallScript` | switch | | | |
| 19 | `脚本内容` | `CallScriptContent` | multiline | | ✔ | `value.CallScript` |
| 20 | `使用全局 Webhook` | `GlobalWebhook` | switch | | | |
| 21… | *…all of `webhookFields(value)` (§11)* | | | | | |

### 13.3 `stun`, advanced / 定制模式 (`advanced = true`)

Rendered only when `value.DiaglogShowMode === 'diy'`, under the heading `定制模式参数`.

| # | label | key | control | limits / options | required | cond |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `IP 过滤模式` | `Options.SafeMode` | chips | `blacklist`, `globalblacklist`, `whitelist` | | |
| 2 | `公网地址自动加入白名单` | `AutoAddPubAddrWhiteList` | switch | | | `Options.SafeMode === 'whitelist'` |
| 3 | `监听方式` | `StunListenType` | chips | `ip`, `networkInterface` | | |
| 4 | `监听 IP（留空自动选择）` | `ListenIP` | text | | | `StunListenType === 'ip'` |
| 5 | `网卡名称` | `SpecifyNetworkInterface` | text | | | `StunListenType !== 'ip'` |
| 6 | `地址匹配表达式` | `NetworkInterfaceReg` | text | | | `StunListenType !== 'ip'` |
| 7 | `跳过自身转发检查` | `Options.DisableSelfForwardingCheck` | switch | | | |

**TCP block** — all present only when `!DisablePortForward && StunType === 'tcp4'`:

| # | label | key | control | limits / options | required | extra cond |
| --- | --- | --- | --- | --- | --- | --- |
| 8 | `单端口限速` | `Options.SinglePortSpeedLimit` | switch | | | |
| 9 | `单端口最大发送速度` | `Options.SinglePortSendSpeedLimit` | number | `30…1000000` | | `Options.SinglePortSpeedLimit` |
| 10 | `单端口最大接收速度` | `Options.SinglePortReceSpeedLimit` | number | `30…1000000` | | `Options.SinglePortSpeedLimit` |
| 11 | `单端口最大 TCP 连接数` | `Options.SingleProxyMaxTCPConnections` | number | `1…1024` | | |
| 12 | `来源启用 TLS` | `Options.TCPListenTLS` | switch | | | |
| 13 | `接收端启用 TLS` | `Options.TCPRelayTLS` | switch | | | |
| 14 | `跳过 TLS 证书校验` | `Options.TCPRelayTLSInsecureSkipVerify` | switch | | | `Options.TCPRelayTLS` |
| 15 | `TLS 转发服务域名` | `Options.TCPRelayTLSServerName` | text | | | `Options.TCPRelayTLS` |
| 16 | `来源流加密` | `Options.TCPStreamEncryptionSource` | switch | | | |
| 17 | `接收端流加密` | `Options.TCPStreamEncryptionAccept` | switch | | | |
| 18 | `流加密密钥` | `Options.TCPStreamEncryptionKey` | secret | | ✔ | `TCPStreamEncryptionSource \|\| TCPStreamEncryptionAccept` |

**UDP block** — all present only when `!DisablePortForward && StunType === 'udp4'`:

| # | label | key | control | limits / options | required | extra cond |
| --- | --- | --- | --- | --- | --- | --- |
| 19 | `UDP 会话超时（毫秒）` | `Options.UDPSessionTimeout` | number | `30…300000` | | |
| 20 | `单端口最大 UDP 会话数` | `Options.SingleProxyMaxUDPReadTargetDatagoroutineCount` | number | `0…32` | | |
| 21 | `UDP 数据包最大长度` | `Options.UDPPacketSize` | number | `1…65507` | | |
| 22 | `UDP 短连接模式` | `Options.UDPShortMode` | switch | | | |
| 23 | `来源数据包加密` | `Options.UDPPacketSourceEncryption` | switch | | | |
| 24 | `接收端数据包加密` | `Options.UDPPacketAcceptEncryption` | switch | | | |
| 25 | `数据包加密密钥` | `Options.UDPPacketEncryptionKey` | secret | | ✔ | `UDPPacketSourceEncryption \|\| UDPPacketAcceptEncryption` |

**Tail (always present in the advanced list):**

| # | label | key | control | limits / options | required | cond |
| --- | --- | --- | --- | --- | --- | --- |
| 26 | `使用全局 STUN 服务器` | `UseGlobalStunServerList` | switch | | | |
| 27 | `STUN 服务器` | `StunServerList` | lines | | ✔ | `!UseGlobalStunServerList` |
| 28 | `TCP 保活服务器` | `TcpKeepAliveServerList` | lines | | | `StunType === 'tcp4'` |
| 29 | `STUN 超时（毫秒）` | `StunTimeout` | number | `1000…10000` | | |
| 30 | `心跳检测间隔（毫秒）` | `StunHeartbeatInterval` | number | `1000…10000` | | |
| 31 | `穿透重试间隔（毫秒）` | `StunRetryInterval` | number | `1000…10000` | | |
| 32 | `穿透失败自动重试` | `StunAutoRetry` | switch | | | |
| 33 | `日志级别` | `LogLevel` | number | `0…6` | | |
| 34 | `日志输出到终端` | `LogOutputToConsole` | switch | | | |
| 35 | `最大访问日志数` | `AccessLogMaxNum` | number | `0…102400` | | |
| 36 | `页面显示最新日志数` | `WebListShowLastLogMaxCount` | number | `1…64` | | |

### 13.4 `cloudflared`, basic

| # | label | key | control | options | required | cond |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `实例名称` | `Remark` | text | | ✔ | |
| 2 | `启用实例` | `Enable` | switch | | | |
| 3 | `实例类型` | `Type` | chips | `tunnel`, `access` | | |
| 4 | `访问域名` | `Params.Hostname` | text | | ✔ | `Type === 'access'` |
| 5 | `本地监听地址` | `Params.URL` | text | | ✔ | `Type === 'access'` |
| 6 | `服务令牌 ID` | `Params.TokenId` | secret | | | `Type === 'access'` |
| 7 | `服务令牌密钥` | `Params.TokenSecret` | secret | | | `Type === 'access'` |
| 4′ | `隧道 Token` | `Params.Token` | secret | | ✔ | `Type !== 'access'` |
| 5′ | `边缘 IP 版本` | `Params.EdgeIpVersion` | chips | `auto`, `4`, `6` | | `Type !== 'access'` |
| 6′ | `连接协议` | `Params.Protocol` | chips | `auto`, `http2`, `quic` | | `Type !== 'access'` |
| 7′ | `连接数` | `Params.HaConnections` | number | `1…8` | | `Type !== 'access'` |
| last | `跳过源站 TLS 校验` | `Params.NoTlsVerify` | switch | | | *always* |

### 13.5 `cloudflared`, advanced

`Type === 'access'`:

| # | label | key | control |
| --- | --- | --- | --- |
| 1 | `请求头` | `Params.HeaderList` | multiline |
| 2 | `目标地址` | `Params.Destination` | text |
| 3 | `连接地址` | `Params.ConnectTo` | text |
| 4 | `User Agent` | `Params.UserAgent` | text |

otherwise (`tunnel`):

| # | label | key | control |
| --- | --- | --- | --- |
| 1 | `Cloudflare API Token` | `Params.CFApiToken` | secret |
| 2 | `账户 ID` | `Params.CFAccountId` | text |
| 3 | `隧道 ID` | `Params.CFTunnelId` | text |
| 4 | `边缘绑定地址` | `Params.EdgeBindAddress` | text |
| 5 | `ICMP IPv4 源地址` | `Params.ICMPV4Src` | text |
| 6 | `ICMP IPv6 源地址` | `Params.ICMPV6Src` | text |

### 13.6 `frp`, basic

| # | label | key | control | options | required | cond |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `实例名称` | `Remark` | text | | ✔ | |
| 2 | `启用实例` | `Enable` | switch | | | |
| 3 | `实例类型` | `Type` | chips | `client`, `server` | | |
| 4 | `监听地址` | `Params.BindAddr` | text | | | `Type === 'server'` |
| 5 | `监听端口` | `Params.BindPort` | number `1…65535` | | ✔ | `Type === 'server'` |
| 6 | `HTTP 虚拟主机端口` | `Params.VhostHTTPPort` | number `0…65535` | | | `Type === 'server'` |
| 7 | `HTTPS 虚拟主机端口` | `Params.VhostHTTPSPort` | number `0…65535` | | | `Type === 'server'` |
| 4′ | `服务器地址` | `Params.ServerAddr` | text | | ✔ | `Type !== 'server'` |
| 5′ | `服务器端口` | `Params.ServerPort` | number `1…65535` | | ✔ | `Type !== 'server'` |
| 6′ | `传输协议` | `Params.Protocol` | chips | `tcp`, `kcp`, `quic`, `websocket`, `wss` | | `Type !== 'server'` |
| 7′ | `认证方式` | `Params.AuthMethod` | chips | `token`, `oidc` | | `Type !== 'server'` |
| 8′ | `启用 TLS` | `Params.TLSEnable` | switch | | | `Type !== 'server'` |
| last | `认证 Token` | `Params.Token` | secret | | | *always* |

### 13.7 `frp`, advanced

`Type === 'server'`:

| # | label | key | control | limits |
| --- | --- | --- | --- | --- |
| 1 | `KCP 监听端口` | `Params.KCPBindPort` | number | `0…65535` |
| 2 | `QUIC 监听端口` | `Params.QUICBindPort` | number | `0…65535` |
| 3 | `允许端口范围` | `Params.AllowPorts` | text | |
| 4 | `管理面板端口` | `Params.DashboardPort` | number | `0…65535` |
| 5 | `管理面板账号` | `Params.DashboardUser` | text | |
| 6 | `管理面板密码` | `Params.DashboardPassword` | secret | **no default — key absent until edited** |
| 7 | `强制 TLS` | `Params.TLSOnly` | switch | |

otherwise (`client`):

| # | label | key | control | limits |
| --- | --- | --- | --- | --- |
| 1 | `用户标识` | `Params.User` | text | |
| 2 | `NAT 穿透 STUN 服务器` | `Params.NatHoleStunServer` | text | |
| 3 | `连接代理 URL` | `Params.ProxyURL` | text | |
| 4 | `DNS 服务器` | `Params.DNSServer` | text | |
| 5 | `TLS 服务名` | `Params.TLSServerName` | text | |
| 6 | `跳过 TLS 证书校验` | `Params.TLSInsecureSkipVerify` | switch | |
| 7 | `心跳间隔（秒）` | `Params.HeartbeatInterval` | number | `min 1`, **no max** |
| 8 | `心跳超时（秒）` | `Params.HeartbeatTimeout` | number | `min 1`, **no max** |
| 9 | `OIDC 客户端 ID` | `Params.OIDCClientID` | text | |
| 10 | `OIDC 客户端密钥` | `Params.OIDCClientSecret` | secret | |
| 11 | `OIDC 令牌地址` | `Params.OIDCTokenEndpointURL` | text | |
| 12 | `OIDC Audience` | `Params.OIDCAudience` | text | |
| 13 | `OIDC Scope` | `Params.OIDCScope` | text | |

### 13.8 `ingress`

basic:

| # | label | key | control | required |
| --- | --- | --- | --- | --- |
| 1 | `域名（留空为兜底规则）` | `hostname` | text | |
| 2 | `路径表达式` | `path` | text | |
| 3 | `后端服务` | `service` | text | ✔ |
| 4 | `跳过源站 TLS 校验` | `originRequest.noTLSVerify` | switch | |

advanced:

| # | label | key | control |
| --- | --- | --- | --- |
| 1 | `源站 TLS 服务名` | `originRequest.originServerName` | text |
| 2 | `源站 Host` | `originRequest.httpHostHeader` | text |
| 3 | `源站 HTTP/2` | `originRequest.http2Origin` | switch |
| 4 | `连接超时（例如 30s）` | `originRequest.connectTimeout` | text (**no default**) |

### 13.9 `proxies`

`proxyType = String(value.type ?? 'tcp')`. basic:

| # | label | key | control | options / limits | required | cond |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `代理名称` | `name` | text | | ✔ | |
| 2 | `代理类型` | `type` | chips | `tcp`, `udp`, `http`, `https`, `stcp`, `xtcp`, `sudp`, `tcpmux` | | |
| 3 | `停用代理` | `disabled` | switch | | | |
| 4 | `本地地址` | `localIP` | text | | | |
| 5 | `本地端口` | `localPort` | number | `1…65535` | ✔ | |
| 6 | `远端端口` | `remotePort` | number | `1…65535` | ✔ | `type ∈ {tcp, udp}` |
| 7 | `自定义域名` | `customDomains` | lines | (**no default**) | | `type ∈ {http, https, tcpmux}` |
| 8 | `子域名` | `subdomain` | text | (**no default**) | | `type ∈ {http, https, tcpmux}` |
| 9 | `访问密钥` | `secretKey` | secret | | ✔ | `type ∈ {stcp, xtcp, sudp}` |

advanced:

| # | label | key | control | options |
| --- | --- | --- | --- | --- |
| 1 | `加密` | `useEncryption` | switch | |
| 2 | `压缩` | `useCompression` | switch | |
| 3 | `Proxy Protocol` | `proxyProtocolVersion` | chips | `''`, `v1`, `v2` |
| 4 | `带宽限制（例如 1MB）` | `bandwidthLimit` | text (**no default**) | |
| 5 | `插件` | `plugin` | chips | `''`, `http_proxy`, `socks5`, `static_file`, `unix_domain_socket`, `http2https`, `https2http`, `https2https`, `tls2raw` |

### 13.10 `visitors` (the `else` branch)

basic:

| # | label | key | control | options / limits | required |
| --- | --- | --- | --- | --- | --- |
| 1 | `访问者名称` | `name` | text | | ✔ |
| 2 | `访问类型` | `type` | chips | `stcp`, `xtcp`, `sudp` | |
| 3 | `停用访问者` | `disabled` | switch | | |
| 4 | `服务端代理名称` | `serverName` | text | | ✔ |
| 5 | `访问密钥` | `secretKey` | secret | | ✔ |
| 6 | `本地监听地址` | `bindAddr` | text | | |
| 7 | `本地监听端口` | `bindPort` | number | `1…65535` | ✔ |

advanced:

| # | label | key | control | options |
| --- | --- | --- | --- | --- |
| 1 | `加密` | `transport.useEncryption` | switch | |
| 2 | `压缩` | `transport.useCompression` | switch | |
| 3 | `保持隧道连接` | `keepTunnelOpen` | switch | |
| 4 | `服务端用户` | `serverUser` | text | |
| 5 | `穿透协议` | `protocol` | chips | `quic`, `kcp` |

Note `visitors` defaults also contain `maxRetriesAnHour`, `minRetryInterval`, `fallbackTo`,
`fallbackTimeoutMs` with no field — they surface in 其他参数.

---

## 14. `validateTunnelForm(type, value)` — coercion + validation

```ts
const activeFields =
  type === 'stun'          ? [...fields(type, value, false), ...(value.DiaglogShowMode === 'diy' ? fields(type, value, true) : [])]
: type === 'stun-settings' ? fields(type, value, false)
:                            [...fields(type, value, false), ...fields(type, value, true)];
```

For every field in order, reading `v = get(result, f.key)` from the **progressively updated** result:

1. **required** — throws when
   `f.required && (v == null || !String(v).trim() || (Array.isArray(v) && !v.some(x => String(x).trim())))`
   Message: `` `请填写${f.label}` `` → e.g. `请填写规则名称`, `请填写目标地址`, `请填写实例名称`.
   Note `String([])` is `''` so an empty required `lines` array fails; `String([' '])` is `' '` → fails;
   `[' ', 'a']` passes.
2. **number** — only when `f.type === 'number' && v !== undefined`. Throws when
   `v === '' || !Number.isInteger(Number(v)) || (min !== undefined && n < min) || (max !== undefined && n > max)`.
   Message:
   ```ts
   `${f.label}范围无效${f.min !== undefined ? `（${f.min}${f.max !== undefined ? `～${f.max}` : ' 起'}）` : ''}`
   ```
   → `目标端口范围无效（1～65535）`, `日志级别范围无效（0～6）`, `心跳间隔（秒）范围无效（1 起）`.
   Full-width `～` (U+FF5E) between min and max; `（`/`）` are full-width brackets;
   the min-only form has a **half-width space** before `起`.
   On success the value is written back **as a `number`** (`result = set(result, f.key, n)`), so a
   text-entered `"8080"` becomes `8080`.
3. **lines** — unconditionally (even when `v` is `undefined`):
   `set(result, f.key, (Array.isArray(v) ? v : []).map(String).map(x => x.trim()).filter(Boolean))`
   → trims each line and drops empty lines; a non-array becomes `[]`. This **creates** the key if it
   was absent.

Cross-field checks, after the loop:

| Condition | Behaviour |
| --- | --- |
| `(type === 'stun' \|\| 'stun-settings') && result.WebhookEnable && (!String(result.WebhookURL ?? '').trim() \|\| !result.WebhookMethod)` | throw `请填写 Webhook 地址和请求方法` |
| `type === 'stun' && result.NatPMP && result.UPnP` | throw `NAT-PMP 和 UPnP 只能启用一项` |
| `type === 'frp' && ['kcp','quic'].includes(String(record(result.Params).Protocol))` | silently `set(result, 'Params.TCPMux', false)` |

Returns the coerced record. Validation is **not** live — it runs only when the consumer taps save
(or "测试 Webhook"). Verified behaviours from `scripts/check-tunnels.cjs`: `ListenPort: '0'` → `0`;
`TargetPort: '99999'` → range error; `TargetAddressList: [' ']` → `请填写目标地址`;
`StunTimeout: 0` passes in `simple` mode but throws in `diy` mode (because the advanced fields are
only active in `diy`); `Proxies` passes through untouched.

---

## 15. `optionLabels` — option value → Chinese chip label (verbatim, 15 entries)

```ts
const optionLabels: Record<string, string> = {
  '': '无',
  simple: '简易模式',
  diy: '定制模式',
  client: '客户端',
  server: '服务端',
  tunnel: 'Tunnel 隧道',
  access: 'Access 访问',
  auto: '自动',
  ip: 'IP 地址',
  networkInterface: '指定网卡',
  tcp4: 'TCP / IPv4',
  udp4: 'UDP / IPv4',
  blacklist: '黑名单',
  globalblacklist: '全局黑名单',
  whitelist: '白名单',
};
```

Rendered as `optionLabels[option] ?? option`. Un-mapped option values show raw: `get`, `post`, `put`,
`patch`, `http`, `https`, `socks5`, `dns`, `4`, `6`, `http2`, `quic`, `tcp`, `kcp`, `websocket`, `wss`,
`token`, `oidc`, `udp`, `stcp`, `xtcp`, `sudp`, `tcpmux`, `v1`, `v2`, `http_proxy`, `static_file`,
`unix_domain_socket`, `http2https`, `https2http`, `https2https`, `tls2raw`.
The empty-string option (`''`) is a real, selectable chip labelled `无` (used by `WebhookProxy`,
`proxyProtocolVersion`, `plugin`).

---

## 16. `updateTunnelFormValue(type, value, key, next)` — side-effecting setter

Every control change goes through this function (never a bare `set`).

**A. Instance-type switch** — `key === 'Type' && (type === 'frp' || type === 'cloudflared')`:

```ts
const defaults = tunnelDefaults(type, String(next));
return { ...value, Type: next, Params: { ...record(defaults.Params), ...record(value.Params) } };
```

The **existing** `Params` values win over the newly-selected mode's defaults, so switching
`client ⇄ server` or `tunnel ⇄ access` fills in the missing keys of the new shape while keeping
everything already entered (including keys that belong to the other shape). `Proxies`/`Visitors` and
all other top-level keys are untouched. Returns immediately — no STUN interlocks.

**B. Everything else** — `updated = set(value, key, next)`; if `type !== 'stun'`, return it.

**C. STUN interlocks** (`simple = updated.DiaglogShowMode !== 'diy'`, strict `next === true` tests):

| Changed key → `true` | Applied side effects |
| --- | --- |
| `AutoOptionsFirewall` | `DisablePortForward = false` |
| `UPnP` | `NatPMP = false`; **if `simple`** also `AutoOptionsFirewall = false`, `DisablePortForward = false` |
| `NatPMP` | `UPnP = false`; **if `simple`** also `AutoOptionsFirewall = false`, `DisablePortForward = false` |
| `DisablePortForward` | **only if `simple`**: `UPnP = false`, `NatPMP = false`, `AutoOptionsFirewall = false` |

Branches are `else if`, so at most one applies. Turning a switch **off** never triggers anything.
In `diy` mode the UPnP/NAT-PMP mutual exclusion still applies but the firewall / port-forward flags
are left alone (confirmed by `check-tunnels.cjs`).

---

## 17. `FormField` — visual spec

Label (shared by all variants): `Text { flex: 1, color: text, fontSize: 13, fontWeight: '600' }` with
content `` `${spec.label}${spec.required ? ' *' : ''}` `` — a **space + asterisk** suffix for required
fields, no colour change.

### 17.1 switch variant

`View { minHeight: 46, flexDirection: 'row', gap: 12, alignItems: 'center' }` → label → `Switch`
with `accessibilityLabel: spec.label`, `disabled`, `value: value === true` (strict — any non-`true`
value reads as off), `onValueChange: onChange`. No custom `trackColor` here (unlike
`StructuredForm`'s boolean row).

### 17.2 chips variant (`spec.options` present)

Outer `View { gap: 8 }` → label → `View { flexDirection: 'row', flexWrap: 'wrap', gap: 6 }`.
Each chip is a `Pressable`:

| Property | Value |
| --- | --- |
| `minHeight` | `40` |
| `padding` | `10` (all sides) |
| `borderRadius` | `10` |
| `borderWidth` / colour | `1` / `value === option ? primary : border` |
| `backgroundColor` | `value === option ? primarySoft : card` |
| Label | `Text { fontSize: 12, color: value === option ? primary : text }` (no weight override) |
| Content | `optionLabels[option] ?? option` |
| a11y | `accessibilityRole: 'radio'`, `accessibilityState: { checked: value === option }` |
| `disabled` | mirrors the form's `disabled` prop |

Selection compares with `===` against the raw option string, so a numeric `4` stored for
`Params.EdgeIpVersion` would render no chip as selected.

### 17.3 text variant (no `options`)

Outer `View { gap: 8 }` → label → input container
`View { flexDirection: 'row', alignItems: 'center', borderWidth: 1, borderColor: border, borderRadius: 12, backgroundColor: card }`
containing a `TextInput` and, for `secret`, a trailing eye button.

| `TextInput` property | Value |
| --- | --- |
| `flex` / `minWidth` | `1` / `0` |
| `minHeight` | `112` for `lines`/`multiline`, else `46` |
| `padding` | `12` (all sides) |
| text colour | `text` |
| `fontSize` / `lineHeight` | `13` / `19` |
| `value` | `Array.isArray(value) ? value.join('\n') : String(value ?? '')` |
| `onChangeText` | `next => onChange(spec.type === 'lines' ? next.split('\n') : next)` |
| `secureTextEntry` | `spec.type === 'secret' && !revealed` |
| `multiline` | `spec.type === 'lines' \|\| spec.type === 'multiline'` |
| `textAlignVertical` | `'top'` for lines/multiline, else `'center'` |
| `keyboardType` | `'number-pad'` for `number`, else `'default'` |
| `autoCapitalize` / `autoCorrect` | `'none'` / `false` |
| `editable` | `!disabled` |
| `accessibilityLabel` | `spec.label` (without the `*`) |

- **No placeholders anywhere in `TunnelForm`** — the only placeholder text in either file is
  `字段名称` in `StructuredForm.AddField`. Hints live inside labels instead, e.g.
  `监听端口（0 为自动）`, `监听 IP（留空自动选择）`, `域名（留空为兜底规则）`,
  `带宽限制（例如 1MB）`, `连接超时（例如 30s）`.
- `lines` round-trip: `string[]` ⇄ `\n`-joined text, split on every keystroke, so intermediate empty
  lines are preserved while typing and only cleaned up by `validateTunnelForm`.
- Numbers are stored as **strings** while typing (`onChange(next)` passes raw text) and only coerced
  to integers by `validateTunnelForm`.
- Secret eye toggle: `Pressable { padding: 12 }`, icon lucide `EyeOff` when revealed else `Eye`,
  `size: 18`, colour `subtext`; `accessibilityLabel` = `隐藏密钥` when revealed, `显示密钥` when not.
  `revealed` is local per-field state, default `false`, and is **not** disabled with the form.

---

## 18. `TunnelForm` — layout and section logic

Root: `View { gap: 15 }`. Local state: `advanced = false`, `extras = false` (both reset on remount).
Every change funnels through `change(key, next) => onChange(updateTunnelFormValue(type, value, key, next))`.

```ts
const fixedMode = type === 'stun' || type === 'stun-settings';

const baseFields = fields(type, value, false)
  .filter(spec => !(type === 'stun' && !value.Key && spec.key === 'Enable'));

const customFields         = type === 'stun' && value.DiaglogShowMode === 'diy' ? fields(type, value, true) : [];
const shownAdvancedFields  = !fixedMode && advanced ? fields(type, value, true) : [];
```

Render order:

1. `baseFields` → `FormField` each, keyed by `spec.key`.
   The `启用规则` switch is **hidden for a brand-new STUN rule** (`!value.Key`) — the consumer's save
   button then reads `创建并启用`.
2. If `customFields.length`: a divider block
   `View { paddingTop: 4, borderTopWidth: 1, borderTopColor: rowBorder }` containing
   `Text { color: text, fontSize: 14, fontWeight: '700', paddingTop: 12 }` = `定制模式参数`.
3. `customFields` → `FormField` each.
4. If `!fixedMode`: the advanced disclosure `Pressable`
   `{ minHeight: 44, flexDirection: 'row', alignItems: 'center', gap: 8 }` with lucide
   `ChevronUp` when expanded / `ChevronDown` when collapsed, `size: 17`, colour `primary`, and
   `Text { color: primary, fontSize: 13 }` = `高级设置`.
   → `stun` and `stun-settings` never show this toggle; STUN's advanced fields are reached only by
   switching `配置模式` to `定制模式`.
5. `shownAdvancedFields` → `FormField` each.
6. If `!fixedMode && advanced`: the extras disclosure
   `Pressable { minHeight: 44, justifyContent: 'center' }` with
   `Text { color: subtext, fontSize: 12 }` = `其他参数` collapsed / `收起其他参数` expanded.
   When `extras` is on, a `View { pointerEvents: disabled ? 'none' : 'auto' }` wraps a
   `StructuredForm` over the computed `extra` record.

### 18.1 The `extra` ("其他参数") record

```ts
const covered = new Set([...fields(type, value, false), ...fields(type, value, true)].map(f => f.key));
const extra = Object.fromEntries(
  Object.entries(value)
    .filter(([key]) => !covered.has(key) &&
      !['Key','ret','msg','Proxies','Visitors','proxies','visitors'].includes(key))
    .map(([key, item]) => [key,
      item && typeof item === 'object' && !Array.isArray(item)
        ? Object.fromEntries(Object.entries(record(item)).filter(([child]) => !covered.has(`${key}.${child}`)))
        : item]));
```

- `covered` holds the **dot-paths** of every field for the *current* value, both basic and advanced
  (so conditionally-hidden fields are only "covered" while their condition holds — flipping a
  condition off makes that key reappear under 其他参数).
- Excluded top-level keys, verbatim: `Key`, `ret`, `msg`, `Proxies`, `Visitors`, `proxies`, `visitors`.
- A nested object (e.g. `Params`, `Options`, `originRequest`, `transport`, `natTraversal`) is kept but
  **filtered to its uncovered children**; a fully-covered object still appears as an empty object
  (rendering as a bordered box with just `添加字段`).
- Arrays are passed through whole (no child filtering).
- Never shown for `stun` / `stun-settings` because of the `!fixedMode` gate.

### 18.2 Merging 其他参数 back into the value

```ts
onChange={next => {
  const merged = { ...value };
  for (const [key, previous] of Object.entries(extra)) {
    if (previous && typeof previous === 'object' && !Array.isArray(previous)) {
      const retained = { ...record(value[key]) };
      for (const child of Object.keys(record(previous))) delete retained[child];
      merged[key] = retained;                 // keep covered children, drop the previously-extra ones
    } else delete merged[key];                // scalars/arrays are removed, then re-added below
  }
  for (const [key, v] of Object.entries(next))
    merged[key] = v && typeof v === 'object' && !Array.isArray(v)
      ? { ...record(merged[key]), ...record(v) }   // re-merge edited children over the retained ones
      : v;
  onChange(merged);
}}
```

Net effect: keys the user deleted inside 其他参数 really disappear from the payload; keys that the
schema owns (`covered`) are never lost, even though they were filtered out of the sub-form; renamed
or newly added keys land at the end of the record.

---

## 19. Complete Chinese string inventory — `tunnel-form.tsx` (UI chrome only)

| String | Where |
| --- | --- |
| `定制模式参数` | STUN diy section heading |
| `高级设置` | advanced disclosure |
| `其他参数` / `收起其他参数` | extras disclosure (collapsed / expanded) |
| `显示密钥` / `隐藏密钥` | secret eye-toggle accessibility labels |
| ` *` suffix | required-field marker appended to the label |
| `请填写{label}` | required validation error |
| `{label}范围无效（{min}～{max}）` / `{label}范围无效（{min} 起）` | numeric validation error |
| `请填写 Webhook 地址和请求方法` | STUN webhook cross-check |
| `NAT-PMP 和 UPnP 只能启用一项` | STUN interlock cross-check |

All field labels and option labels are listed in §11, §13 and §15.

---

## 20. Consumer context (`app/tunnels/[kind].tsx`) — needed for a faithful port

- `tunnelTitles`: `stun` → `STUN 内网穿透`, `cloudflared` → `Cloudflared`, `frp` → `FRP 内网穿透`.
- `collectionTitles`: `ingress` → `域名路由`, `proxies` → `代理规则`, `visitors` → `访问者`.
- Editor titles: `新增{tunnelTitles[kind]}`, `编辑 {name}`, `STUN 全局设置`,
  `新增{collectionTitles[…]}`, `编辑规则`.
- The editor deep-copies the value (`JSON.parse(JSON.stringify(...))`) before handing it to
  `TunnelForm`, so the form is fully uncontrolled with respect to the list data.
- Save button label: `保存中` while pending, `创建并启用` for a new `stun` rule, else `保存`.
- `测试 Webhook` action appears for `stun` / `stun-settings` when `value.WebhookEnable`; it validates
  first, then posts only the keys matching `key.startsWith('Webhook') || key === 'RetryCount' || key === 'RetryInterval'`.
- STUN new-rule flow relies on `Enable` staying `true` from `tunnelDefaults` while its switch is hidden.

---

## 21. Porting checklist / gotchas

1. `StructuredForm` has **no** select, stepper, collapse, reorder, or key-hiding behaviour. Anything
   resembling those in the Swift port must come from `TunnelForm`'s `Field` schema instead.
2. Depth styling is flat, not proportional: `RecordFields` = `12` padding + `1` border per level from
   depth 1; `StructuredDataView` = `10` left padding + hairline rule per level from depth 1.
3. Array rows need stable identities (§6.3) or numeric drafts will jump between rows on delete.
4. `NumericField` needs the focused/draft/commit state machine, otherwise typing `-` or `1.` is
   impossible.
5. `fieldLabel` is exact-key lookup then two regex substitutions — do not "humanise" further.
6. `ret` / `msg` are stripped at **every** depth of `StructuredDataView`, not just the root.
7. Both 200-item caps are per container and produce distinct footer strings (个 vs 项).
8. Number fields in `TunnelForm` hold **strings** until save; `validateTunnelForm` is the only place
   that coerces, and it mutates a copy that becomes the request body.
9. `lines` fields are always rewritten (trim + drop empties) on save, creating the key if missing.
10. Fields with no entry in `tunnelDefaults` — `Params.DashboardPassword`, `bandwidthLimit`,
    `customDomains`, `subdomain`, `originRequest.connectTimeout` — must render as empty and only
    appear in the payload once edited (or, for `customDomains`, once save normalises it to `[]`).
11. Preserve upstream key typos exactly (§12.2); they are part of the wire contract.
12. `updateTunnelFormValue` must be the single write path — the interlocks and the `Type`-switch
    `Params` merge are behavioural, not cosmetic.
