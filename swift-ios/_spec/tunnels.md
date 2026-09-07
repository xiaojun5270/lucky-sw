# 内网穿透模块 1:1 行为规格（tunnels）

来源文件（React Native / Expo Router 实现）：

- `C:\Users\xiaoj\Desktop\lucky\app\tunnels\[kind].tsx` — 屏幕（列表 + 全部模态）
- `C:\Users\xiaoj\Desktop\lucky\src\services\tunnels.ts` — 服务层
- 依赖（本规格中一并固化，SwiftUI 侧必须复刻）：
  - `C:\Users\xiaoj\Desktop\lucky\src\components\tunnel-form.tsx` — 表单字段模式 / 默认值 / 校验
  - `C:\Users\xiaoj\Desktop\lucky\src\components\lucky-ui.tsx` — Page / PageHeader / Panel / IconTile / EmptyState / ErrorState / SearchField
  - `C:\Users\xiaoj\Desktop\lucky\src\components\structured-form.tsx` — StructuredDataView / StructuredForm
  - `C:\Users\xiaoj\Desktop\lucky\src\lib\lucky-fetch.ts` — HTTP 传输层
  - `C:\Users\xiaoj\Desktop\lucky\src\lib\theme.ts` — 语义色 token
  - `C:\Users\xiaoj\Desktop\lucky\src\lib\query-client.ts` — 查询默认值
  - `C:\Users\xiaoj\Desktop\lucky\app\(tabs)\manage.tsx` — 入口卡片（副标题与配色来源）

---

## 1. 路由与每种类型的配置映射

路由：`/tunnels/:kind`，路径参数 `kind`。导航栏（`app/_layout.tsx`）：`title: '内网穿透'`，`headerBackTitle: '返回'`。

参数校验：`isTunnelKind(kind)`，仅接受 `'stun' | 'cloudflared' | 'frp'`。不合法时渲染
`<Page title="内网穿透"><ErrorState message="不支持的穿透模块" /></Page>`（即页头标题「内网穿透」+ 错误卡「不支持的穿透模块」），不发起任何请求。

合法时渲染 `TunnelScreen`，且以 `key={kind}` 强制重建（切换 kind 时所有本地状态复位）。

### 1.1 每种类型的配置（逐字）

| 项 | stun | cloudflared | frp |
| --- | --- | --- | --- |
| 标题 `tunnelTitles[kind]` | `STUN 内网穿透` | `Cloudflared` | `FRP 内网穿透` |
| 图标 `icons[kind]`（lucide） | `Network` | `Cloud` | `Globe2` |
| 入口卡副标题（manage 页 `detail`） | `穿透规则与公网地址` | `隧道与域名路由` | `客户端、服务端与代理` |
| 入口卡图标色 / 底色 | 默认（`primary` / `primarySoft`） | `colors.warning` / `colors.warningBg` | `colors.cyan` / `colors.cyanBg` |
| 入口路由 | `/tunnels/stun` | `/tunnels/cloudflared` | `/tunnels/frp` |
| 列表接口 | `GET /api/stunrulelist` | `GET /api/cloudflared/list` | `GET /api/frp/list` |
| 单条读取 | `GET /api/stun/{key}`（解包 `rule`） | `GET /api/cloudflared/list/{key}`（解包 `instance`） | `GET /api/frp/list/{key}`（解包 `instance`） |
| 保存 | `POST/PUT /api/stunrule` | `POST/PUT /api/cloudflared/list` | `POST/PUT /api/frp/list` |
| 删除 | `DELETE /api/stunrule?key=` | `DELETE /api/cloudflared/list/{key}` | `DELETE /api/frp/list/{key}` |
| 启停 | `GET /api/stunrule/enable?key=&enable=` | `GET /api/cloudflared/list/{key}/{enable}` | `GET /api/frp/list/{key}/{enable}` |
| 排序 | `PUT /api/stun/ruleorderadjustment` | `PUT /api/cloudflared/orderadjustment` | `PUT /api/frp/orderadjustment` |
| 头部动作 | `新增` / `全局设置` / `NAT 检测` | `新增` / `模块日志` | `新增` / `模块日志` |
| 行内子集合 | 无（子集合请求会抛 `STUN 不支持此操作`） | `域名路由`（仅 `Type === 'tunnel'`） | `运行详情`；`Type === 'client'` 时另有 `代理规则`、`访问者` |
| 表单类型 `TunnelFormType` | `stun`（另有 `stun-settings`） | `cloudflared` | `frp` |

无「tabs / 分段控件」：本屏没有 segmented control，子集合通过行内按钮打开全屏模态。`PageHeader` 只传 `title` 与 `icon`，**不传 subtitle**（副标题仅存在于 manage 页入口卡）。

子集合标题映射 `collectionTitles`（逐字）：

```ts
{ ingress: '域名路由', proxies: '代理规则', visitors: '访问者' }
```

---

## 2. 语义色 token（本屏用到的部分，来自 `theme.ts`）

| 角色 | light | dark |
| --- | --- | --- |
| `page` | `#f5f5f7` | `#000000` |
| `card` | `#ffffff` | `#1c1c1e` |
| `mutedCard` | `#f2f2f7` | `#2c2c2e` |
| `muted` | `#e8e8ed` | `#3a3a3c` |
| `primary` | `#007aff` | `#0a84ff` |
| `primarySoft` | `#e5f1ff` | `#0b2f52` |
| `text` | `#1d1d1f` | `#f5f5f7` |
| `subtext` | `#6e6e73` | `#a1a1a6` |
| `border` | `#e1e1e6` | `#3a3a3c` |
| `rowBorder` | `#e5e5ea` | `#38383a` |
| `danger` | `#ff3b30` | `#ff453a` |
| `dangerBg` | `#fff0ef` | `#3d1412` |
| `success` | `#248a3d` | `#30d158` |
| `warning` | `#c93400` | `#ff9f0a` |
| `warningBg` | `#fff5e6` | `#3b290d` |
| `cyan` | `#0071a4` | `#64d2ff` |
| `cyanBg` | `#e9f7fc` | `#0c3040` |
| `disabled` | `#aeaeb2` | `#636366` |
| `placeholder` | `#8e8e93` | `#8e8e93` |

主题跟随系统 `useColorScheme()`。卡片阴影：`shadowColor #000000`、`shadowOpacity 0.055`（iOS/web）、`shadowRadius 12`、`shadowOffset (0,4)`。

---

## 3. 传输层契约（`luckyFetch`，所有服务函数都经过它）

- URL = `baseUrl`（去尾部 `/`）+ path，并追加 nonce 查询参数 `_`：
  `createLuckyRequestNonce(now)` = `String(now).slice(0, -1)` 再拼接「各位数字之和 % 8」；已有 `?` 时用 `&` 连接。
- 请求头：`Accept: application/json`；有 body 且非 FormData/Blob 时 `Content-Type: application/json`；有 token 时 `Lucky-Admin-Token: <token>`。
- 默认超时 `12000` ms；超时错误 `请求超时，请检查服务器连接`；外部 signal 取消 → `请求已取消`；`baseUrl` 为空 → `请输入 Lucky 服务地址`。
- 响应统一为 `{ ret, ... }` 信封：`ret` 缺失按 `0`；`204` 或 `content-length: 0` → `{ ret: 0 }`；`text/*`、`xml`、`yaml` → `{ ret: 0, data: <原始文本> }`。
- `HTTP 401` 或 `ret === -1` → 自动 `POST /api/login` 刷新 token 后重试一次；失败则结束会话并抛 `LuckyAuthError`（默认文案 `登录已失效，请重新登录`）。
- 其他失败：`throw new Error(payload.msg || \`请求失败（HTTP ${status}）\`)`。

> SwiftUI 侧：所有下列「HTTP 方法 + 路径」都要叠加上述 nonce、token 头、12 秒超时与信封解包。

---

## 4. 服务模块常量与解包辅助（`src/services/tunnels.ts`）

```ts
export type TunnelKind = 'stun' | 'cloudflared' | 'frp';
export type TunnelCollection = 'ingress' | 'proxies' | 'visitors';
export const tunnelTitles: Record<TunnelKind, string> = {
  stun: 'STUN 内网穿透', cloudflared: 'Cloudflared', frp: 'FRP 内网穿透',
};
```

| 导出 | 签名 | 行为 |
| --- | --- | --- |
| `isTunnelKind` | `(value: unknown) => value is TunnelKind` | 仅 `'stun'`/`'cloudflared'`/`'frp'` 为真 |
| `record` | `(value: unknown) => LuckyRecord` | 非空、`typeof === 'object'`、非数组 → 原值；否则 `{}` |
| `tunnelData` | `(payload, field) => LuckyRecord` | 候选源顺序 **`[payload, record(payload.data), record(payload.result)]`**；取首个 `source[field]` 为「非空非数组对象」者；全部失败 → `throw new Error('服务端未返回完整配置，请刷新后重试')` |
| `tunnelItems` | `(payload, field = 'list') => LuckyRecord[]` | 同样三个候选源；`Array.isArray(source[field])` → 过滤出「非空非数组对象」元素；`source[field] === null` → 返回 `[]`；全部失败 → `throw new Error('服务端未返回列表数据')` |
| `keyPath`（内部） | `(key: string) => string` | `!key.trim()` → `throw new Error('规则标识缺失，请刷新列表')`；否则 `encodeURIComponent(key)` |
| `query`（内部） | `(values) => string` | `URLSearchParams`，每个值 `String(value)` |
| `write`（内部） | `(path, 'POST'\|'PUT'\|'DELETE', value?)` | `value === undefined` 时不带 body，否则 `JSON.stringify(value)` |

---

## 5. 服务模块导出函数（逐条）

### 5.1 `listTunnels(kind: TunnelKind, signal?: AbortSignal)`

- `GET /api/stunrulelist`（kind = stun）
- `GET /api/{kind}/list`（cloudflared / frp）
- 返回 `{ items: tunnelItems(raw), raw }`，即列表解包字段固定为 **`list`**（候选源 `payload` → `payload.data` → `payload.result`）。`raw` 保留整个信封（屏幕用 `raw.ModuleEnable` 判断 STUN 模块开关）。
- 错误改写：捕获到的 `Error.message` 匹配正则 `/(?:404|Request URL .*not found)/i` 时，抛出
  `` `当前 Lucky 服务端未提供 ${tunnelTitles[kind]} 模块，请确认服务端版本和模块支持情况` ``
  （例：`当前 Lucky 服务端未提供 FRP 内网穿透 模块，请确认服务端版本和模块支持情况`）。其他错误原样上抛。

### 5.2 `getTunnel(kind: TunnelKind, key: string, signal?: AbortSignal)`

- `GET /api/stun/{encodeURIComponent(key)}`（stun）/ `GET /api/{kind}/list/{encodeURIComponent(key)}`
- `key` 为空白 → `规则标识缺失，请刷新列表`
- 解包字段：stun → **`rule`**；cloudflared / frp → **`instance`**（`tunnelData`，失败文案 `服务端未返回完整配置，请刷新后重试`）
- 后处理：
  - stun：`{ ...value, DiaglogShowMode: value.DiaglogShowMode || 'simple' }`
  - frp：`{ ...value, Proxies: value.Proxies ?? value.proxies ?? [], Visitors: value.Visitors ?? value.visitors ?? [] }`
  - cloudflared：原样返回

### 5.3 `saveTunnel(kind, value: LuckyRecord, editing: boolean)`

- `editing ? 'PUT' : 'POST'`
- stun → `/api/stunrule`；其他 → `/api/{kind}/list`
- 请求体：**整个 `value` 对象逐字 JSON 序列化**（键名即表单键名，见 §14/§18；屏幕在 frp 时先删除 `proxies`、`visitors` 两个小写别名）

### 5.4 `deleteTunnel(kind, key)`

- 先调用 `keyPath(key)` 做校验（空白 → `规则标识缺失，请刷新列表`）
- stun → `DELETE /api/stunrule?key={key}`（`key` 由 `URLSearchParams` 编码，非 `encodeURIComponent`）
- 其他 → `DELETE /api/{kind}/list/{encodeURIComponent(key)}`
- 无请求体

### 5.5 `enableTunnel(kind, key, enable: boolean)`

- 先 `keyPath(key)` 校验
- stun → `GET /api/stunrule/enable?key={key}&enable={String(enable)}`（`true` / `false` 字符串）
- 其他 → `GET /api/{kind}/list/{encodeURIComponent(key)}/{String(enable)}`
- 注意：**GET**，无 body

### 5.6 `reorderTunnels(kind, keys: string[])`

- `PUT /api/stun/ruleorderadjustment`（stun）/ `PUT /api/{kind}/orderadjustment`
- 请求体：**JSON 字符串数组**（如 `["k1","k3","k2"]`），即调整后的完整 Key 顺序

### 5.7 STUN 专属

| 函数 | 方法 / 路径 | 请求体 | 解包 |
| --- | --- | --- | --- |
| `getStunSettings(signal?)` | `GET /api/stun/configure` | — | `tunnelData(..., 'configure')`，失败 `服务端未返回完整配置，请刷新后重试` |
| `saveStunSettings(value)` | `PUT /api/stun/configure` | 整个 `value` | — |
| `testStunWebhook(key, value)` | `POST /api/stunrule/webhooktest?key={key \|\| '666'}` | 见 §13.2（仅 `Webhook*` + `RetryCount` + `RetryInterval` 键） | 调用方读 `Response` / `msg` |

`testStunWebhook` 的 `key` 兜底值是字符串 `'666'`（新建规则尚无 Key 时使用）。

### 5.8 日志

| 函数 | 方法 / 路径 |
| --- | --- |
| `getTunnelLogs(kind, key, page, signal?)` | `GET /api/{kind}/{encodeURIComponent(key)}/logs?pageSize=100&page={page}`；`key` 为空字符串时省略该段 → `GET /api/{kind}/logs?pageSize=100&page={page}`（模块级日志） |
| `getTunnelLastLogs(kind, key, signal?)` | `GET /api/{kind}/{encodeURIComponent(key)}/lastlogs`（`key` 必填，空白 → `规则标识缺失，请刷新列表`） |

查询串顺序固定为 `pageSize` 后 `page`；`pageSize` 常量 **100**。

### 5.9 `getFrpStatus(key, signal?)`

`GET /api/frp/{encodeURIComponent(key)}/status`（空白 key → `规则标识缺失，请刷新列表`）。

### 5.10 子集合（仅 cloudflared / frp）

`listTunnelChildren(kind: 'cloudflared' | 'frp', key, collection: TunnelCollection, signal?)`
- `GET /api/{kind}/{encodeURIComponent(key)}/{collection}`
- 解包字段：`collection === 'ingress' ? 'rules' : collection`
  即 ingress → **`rules`**，proxies → **`proxies`**，visitors → **`visitors`**（候选源仍是 `payload` / `payload.data` / `payload.result`；失败 `服务端未返回列表数据`）

`saveTunnelChild(kind, key, collection, value, previous?)`
- `previous ? 'PUT' : 'POST'`，路径 `/api/{kind}/{encodeURIComponent(key)}/{collection}`
- 请求体（逐字键名）：
  - 无 `previous`（新增）：`value` 本身
  - `ingress` 编辑：`{ oldHostname: previous.hostname ?? '', oldPath: previous.path ?? '', newRule: value }`
  - `proxies` 编辑：`{ oldName: previous.name, newProxy: value }`
  - `visitors` 编辑：`{ oldName: previous.name, newVisitor: value }`

`deleteTunnelChild(kind, key, collection, value)`
- `ingress` → `DELETE /api/{kind}/{key}/ingress?hostname={value.hostname ?? ''}&path={value.path ?? ''}`
- `proxies` / `visitors` → `DELETE /api/{kind}/{key}/{collection}/{encodeURIComponent(String(value.name ?? ''))}`（名称空白 → `规则标识缺失，请刷新列表`）
- 无请求体

### 5.11 `cloudflareDns(key, hostname, action: 'check' | 'create' | 'delete')`

基路径 `` `/api/cloudflared/${encodeURIComponent(key)}/cname/${action}` ``

| action | 方法 / 路径 | 请求体 |
| --- | --- | --- |
| `check` | `GET /api/cloudflared/{key}/cname/check?hostname={hostname}` | — |
| `create` | `POST /api/cloudflared/{key}/cname/create` | `{ "hostname": <hostname>, "proxied": true }` |
| `delete` | `DELETE /api/cloudflared/{key}/cname/delete?hostname={hostname}` | — |

### 5.12 `tunnelLogLines(value: unknown): string[]`（日志文本归一化）

递归规则，顺序严格：

1. `value == null` → `[]`
2. `typeof value === 'string'` → `value.split(/\r?\n/).filter(Boolean)`
3. `Array.isArray(value)` → `value.flatMap(tunnelLogLines)`
4. 对象且 `item.LogContent != null` → 单元素数组 `` [`${item.LogTime ?? ''} ${String(item.LogContent)}`.trim()] ``（时间与内容用一个空格连接后 trim）
5. 否则按候选键数组顺序取**第一个存在（`in` 判定，包含值为 null/undefined 的键）**的键并递归：

```ts
['logs', 'lastLogs', 'LastLogs', 'data', 'result', 'Response', 'message', 'output']
```

6. 都不匹配 → `[]`

---

## 6. 子组件与精确视觉结构

### 6.1 `Action`（本屏所有按钮的唯一形态）

Props：`{ icon: LucideIcon; label: string; onPress: () => void; disabled?: boolean; danger?: boolean = false }`

- 前景色 `color = danger ? colors.danger : colors.primary`
- 容器：`flexGrow: 1`、`flexBasis: 105`、`minHeight: 42`、`paddingHorizontal: 10`、`paddingVertical: 8`、`borderRadius: 12`、背景 `danger ? colors.dangerBg : colors.primarySoft`、横向排列、主轴/交叉轴居中、`gap: 6`
- 不透明度：`disabled ? 0.4 : pressed ? 0.6 : 1`
- 图标 `size 16`，文字 `fontSize 12`、`fontWeight '600'`、`flexShrink: 1`
- 无障碍：`accessibilityRole="button"`，`accessibilityLabel = label`
- 因 `flexBasis: 105` + 父容器 `flexWrap: 'wrap'` + `gap`，按钮组自动换行成网格

### 6.2 `ScreenModal`（全屏模态外壳）

Props：`{ title: string; close: () => void; children: ReactNode; footer?: ReactNode; busy?: boolean = false }`

- `Modal presentationStyle="fullScreen" animationType="slide" statusBarTranslucent navigationBarTranslucent`
- `onRequestClose`：`busy` 为真时**忽略**（不可返回关闭）
- 安全区容器背景 `colors.page`；`KeyboardAvoidingView` behavior：iOS `padding`，其他 `height`
- 内容容器：`flex: 1`、`width: '100%'`、`maxWidth: 820`、水平居中、`padding: 16`、`gap: 12`
- 标题行：`minHeight 44`、横向、`gap 12`；标题 `numberOfLines 2`、`flex: 1`、`fontSize 18`、`fontWeight '700'`、色 `text`
- 关闭按钮：`40×40`、`borderRadius 12`、背景 `mutedCard`、图标 `X size 20 color subtext`、`accessibilityLabel="关闭"`、`busy` 时禁用
- 滚动区：`keyboardShouldPersistTaps="handled"`、`keyboardDismissMode="interactive"`、内容 `gap 14`、`paddingBottom 16`
- `footer` 固定在滚动区下方

### 6.3 来自 `lucky-ui` 的组件（本屏使用的度量）

| 组件 | 关键度量 |
| --- | --- |
| `Page` | `title=tunnelTitles[kind]`、`safeTop={false}`、`scrollable={false}`、`showHeader={false}`；内容 `maxWidth 820`、`paddingHorizontal 16`、`paddingTop 14`、`paddingBottom 12`（非滚动）、`gap 16`；背景 `page` |
| `PageHeader` | `minHeight 48`、两端对齐、`gap 12`；左侧 `IconTile size 44 iconSize 22`；标题 `fontSize 26 / lineHeight 32 / fontWeight '800'`；副标题 `13/18 subtext`（本屏未传）；右侧刷新按钮 `42×42`、`borderRadius 13`、背景 `card`、`borderWidth 1 border`、图标 `RefreshCw size 19 strokeWidth 2.2 primary`，`refreshing` 时显示 `ActivityIndicator` 且不透明度 `0.55`，按下 `0.62` + `scale 0.96`，`accessibilityLabel="刷新"` |
| `Panel` | 背景 `card`、`borderWidth 1 border`、`borderRadius 18`、`padding 16`、`gap 12`、卡片阴影 |
| `IconTile` | 默认 `size 36`、`iconSize 18`、`borderRadius = max(9, round(size * 0.28))`、背景 `primarySoft`、图标色 `primary`、`strokeWidth 2.2` |
| `EmptyState` | 外层 `Panel`；内容居中、`paddingVertical 20`、`gap 10`；`IconTile size 42 iconSize 21`、图标色 `subtext`、底色 `mutedCard`；文字 `subtext` 居中（默认字号） |
| `ErrorState` | `padding 14`、`borderRadius 18`、边框与背景同为 `dangerBg`、`gap 10`；`IconTile TriangleAlert size 34 iconSize 17`、图标色 `danger`、底色 `card`；文案 `danger`、`lineHeight 19`；可选「重试」按钮：`minHeight 36`、`paddingHorizontal 12`、`borderRadius 12`、背景 `card`、`RefreshCw size 14`、文字 `重试` `fontWeight '700'` |
| `SearchField` | `height 46`、`borderRadius 14`、背景 `card`、`borderWidth 1 border`、`paddingHorizontal 12`、`gap 9`；`Search size 17 strokeWidth 2.1 subtext`；输入 `fontSize 15`、`paddingVertical 10`、`placeholderTextColor = placeholder`、`autoCapitalize="none"`、`autoCorrect={false}` |

---

## 7. 屏幕状态、查询与刷新策略

### 7.1 本地状态

| 状态 | 初值 | 说明 |
| --- | --- | --- |
| `foreground` | `AppState.currentState !== 'background'` | 监听 `AppState 'change'`，`state === 'active'` 才为真 |
| `search` | `''` | 搜索词 |
| `editor` | `undefined` | `Editor = { title, type: TunnelFormType, value, previous?, parent?, editing }` |
| `natOpen` | `false` | NAT 检测模态 |
| `detail` | `undefined` | `Detail = { mode: 'logs' \| 'status' \| TunnelCollection, item }` |
| `page` | `1` | 日志分页；`0` 表示「实时」（lastlogs） |
| `error` | `''` | 屏幕级错误 |
| `notice` | `''` | 屏幕级成功提示 |
| `loadingEditor` | `false` | 读取待编辑配置中 |
| `dnsResult` | `undefined` | DNS 检测结果（仅 ingress） |
| `requestRef` | `null` | 编辑器读取用 `AbortController`，卸载时 abort |

`active = useIsFocused() && foreground`。

### 7.2 列表查询

```
queryKey: ['tunnels', kind, 'list']
queryFn:  listTunnels(kind, signal)
enabled:  active
refetchInterval: (active && !editor) ? 5000 : false
refetchIntervalInBackground: false
```

### 7.3 详情查询

```
queryKey: ['tunnels', kind, detail?.mode, itemKey(detail?.item ?? {}), page]
enabled:  active && Boolean(detail) && !editor
refetchInterval: (active && detail && !editor && ((detail.mode === 'logs' && page <= 1) || detail.mode === 'status')) ? 5000 : false
refetchIntervalInBackground: false
```

`queryFn` 分支：
1. `!detail` → `{}`
2. `mode === 'logs'`：`page === 0 && key` → `getTunnelLastLogs(kind, key)`；否则 `getTunnelLogs(kind, key, page)`
3. `mode === 'status'` → `getFrpStatus(key)`
4. `kind === 'stun'` → `throw new Error('STUN 不支持此操作')`
5. 其他（子集合）→ `{ items: await listTunnelChildren(kind, key, mode) }`

### 7.4 全局查询默认值（`query-client.ts`）

`retry: 1`、`staleTime: 30_000`、`gcTime: 120_000`、`refetchOnWindowFocus: false`、`refetchOnReconnect: true`；焦点管理器与 `AppState` 绑定（非 web）。本屏未覆盖 `staleTime`。

### 7.5 失效与通用变更

- `invalidate()` = `queryClient.invalidateQueries({ queryKey: ['tunnels', kind] })`（同时作废列表与详情）
- `operation` mutation：`mutationFn: (run) => run()`；`onMutate` 清空 `error` 与 `notice`；`onSuccess` 置 `notice = '操作已完成'` 后 `await invalidate()`；`onError` 置 `error = e.message`
- `busy = operation.isPending || loadingEditor`

### 7.6 搜索过滤（客户端）

对每条记录取 `[item.Name, item.Remark, item.Type, item.StunType, item.PublicAddr]`，各自经 `text()` 转字符串后以单空格 `join(' ')`，`toLowerCase()` 后判断是否 `includes(search.trim().toLowerCase())`。

`text(value)` = `typeof value === 'string' || typeof value === 'number' ? String(value) : ''`。

### 7.7 其他取值辅助（屏幕内）

| 函数 | 定义（候选键顺序逐字） |
| --- | --- |
| `itemKey(item)` | `text(item.Key)` |
| `itemName(item)` | `text(item.Name ?? item.Remark ?? item.name) \|\| '未命名'` |
| `enabled(item)` | `item.Enable === true \|\| item.Enable === 1 \|\| item.Enable === 'true'` |

---

## 8. 列表结构（FlatList）

- `data = items`（过滤后），`keyExtractor = itemKey(item) || \`missing-${index}\``
- `initialNumToRender: 8`、`windowSize: 7`、`keyboardShouldPersistTaps="handled"`
- 内容容器：`gap: 12`、`paddingBottom: 24`

### 8.1 表头（`ListHeaderComponent`，外层 `gap: 14`）

顺序：

1. `PageHeader`：`title = tunnelTitles[kind]`、`icon = icons[kind]`、`refreshing = list.isFetching`、`onRefresh = list.refetch()`
2. `error` 非空 → `ErrorState`（无重试）
3. `list.error` → `ErrorState message={list.error.message} retry={list.refetch}`
4. `notice` 非空 → `Text` 色 `success`、`fontSize 12`
5. 仅 stun 且 `list.data?.raw.ModuleEnable === false`（严格等于 false）→ `Text` `STUN 模块未启用`，色 `warning`、`fontSize 13`
6. 动作行（横向 `flexWrap: 'wrap'`、`gap: 8`）：
   - `新增`（`Plus`），`disabled = busy` → `openEditor()`
   - stun → `全局设置`（`Settings2`）→ `openEditor(undefined, true)`；非 stun → `模块日志`（`FileText`）→ `openDetail('logs', {})`（空 item ⇒ 模块级日志，page 起始 1）
   - 仅 stun 追加 `NAT 检测`（`Network`）→ `setNatOpen(true)`
7. `SearchField`，`placeholder = '搜索名称、类型或公网地址'`
8. `loadingEditor` → `ActivityIndicator color={colors.primary}`

### 8.2 空态（`ListEmptyComponent`）

- `list.isLoading` → `ActivityIndicator color={colors.primary}`
- 否则若 `!list.error` → `EmptyState`，文案 `search ? '没有匹配的规则' : '暂无规则'`，图标 `icons[kind]`
- 若有 `list.error` → 不渲染空态（错误已在表头显示）

### 8.3 列表行（`Panel`，内部 `gap 12`）

行内派生值：
```
key    = itemKey(item)
index  = all.findIndex(row => itemKey(row) === key)   // all = 未过滤列表
params = record(item.Params)
```

**状态文本 `state` 派生规则（严格顺序）**
1. `typeof item.Running === 'boolean'` → `item.Running ? '运行中' : '未运行'`
2. 否则 `text(item.Status ?? item.State)`（候选键顺序 `Status` → `State`）
3. 上一步为空串 → `enabled(item) ? '已启用' : '已停用'`

**第一行**：横向、`alignItems center`、`gap 10`
- `IconTile icon={icons[kind]}`（默认 36/18）
- 中间列 `flex: 1, minWidth: 0`：
  - 名称 `itemName(item)`：`fontSize 15`、`fontWeight '700'`、色 `text`
  - 次行：模板 `` `${text(item.StunType)} ${state}` ``（非 stun 时 `StunType` 为空 ⇒ 以一个前导空格开头），`fontSize 12`、色 `subtext`、`marginTop 4`
- `Switch`：`value = enabled(item)`、`disabled = busy || !key`、`accessibilityLabel = \`启用 ${itemName(item)}\``、`onValueChange = value => operation.mutate(() => enableTunnel(kind, key, value))`

**摘要行**（`selectable`、`fontSize 12`、`lineHeight 18`、色 `subtext`），按 kind 逐字模板：

| kind | 模板 |
| --- | --- |
| stun | `` `${text(item.ListenIP) \|\| '自动监听'}:${text(item.ListenPort) \|\| '自动'} → ${Array.isArray(item.TargetAddressList) ? item.TargetAddressList.join(', ') : ''}:${text(item.TargetPort)}` `` |
| frp | `` `${text(item.Type) === 'server' ? '服务端' : '客户端'} · ${text(params.ServerAddr ?? params.BindAddr)}:${text(params.ServerPort ?? params.BindPort)}` `` |
| cloudflared | `text(item.Type) === 'access'` → `` `Access · ${text(params.Hostname)}` ``；否则字符串 `Cloudflare Tunnel` |

**公网地址行（仅 stun）**：`` `公网地址：${text(item.PublicAddr) || '等待穿透'}` ``，`selectable`、`fontSize 13`，色 `item.PublicAddr ? colors.success : colors.subtext`。

### 8.4 行动作（横向 `flexWrap: 'wrap'`、`gap: 7`，顺序严格如下）

| 顺序 | 标签 | 图标 | 出现条件 | 禁用条件 | 行为 / 载荷 |
| --- | --- | --- | --- | --- | --- |
| 1 | `编辑` | `Pencil` | 全部 | `busy \|\| !key` | `openEditor(item)`（先 `getTunnel`） |
| 2 | `日志` | `FileText` | 全部 | `busy \|\| !key` | `openDetail('logs', item)` → `page = 0`（实时） |
| 3 | `域名路由` | `Globe2` | `kind === 'cloudflared' && item.Type === 'tunnel'` | `busy \|\| !key` | `openDetail('ingress', item)` |
| 4 | `运行详情` | `Activity` | `kind === 'frp'` | `busy \|\| !key` | `openDetail('status', item)` |
| 5 | `代理规则` | `Network` | `kind === 'frp' && item.Type === 'client'` | `busy \|\| !key` | `openDetail('proxies', item)` |
| 6 | `访问者` | `Globe2` | `kind === 'frp' && item.Type === 'client'` | `busy \|\| !key` | `openDetail('visitors', item)` |
| 7 | `复制地址` | `Copy` | `kind === 'stun' && item.PublicAddr` | 无 | `operation.mutate(() => Clipboard.setStringAsync(text(item.PublicAddr)))` → 走成功路径，提示 `操作已完成` 并触发 invalidate |
| 8 | `上移` | `ArrowUp` | 全部 | `busy \|\| !key \|\| index <= 0` | `move(item, -1)` |
| 9 | `下移` | `ArrowDown` | 全部 | `busy \|\| !key \|\| index === all.length - 1` | `move(item, 1)` |
| 10 | `删除` | `Trash2`（`danger`） | 全部 | `busy \|\| !key` | `confirm(\`删除 ${itemName(item)}？\`, () => deleteTunnel(kind, key))` |

`move(item, direction)`：
1. `index = all.findIndex(key 相同)`，`target = index + direction`
2. `index < 0 || target < 0 || target >= all.length` → 静默返回
3. `keys = all.map(itemKey)`；任一为空 → `setError('列表中缺少规则标识，无法排序')` 并返回
4. 交换 `keys[index]` 与 `keys[target]`，`operation.mutate(() => reorderTunnels(kind, keys))`

### 8.5 确认对话框

```ts
function confirm(title, run) {
  Alert.alert(title, '此操作将修改服务器配置。', [
    { text: '取消', style: 'cancel' },
    { text: '确认', style: 'destructive', onPress: () => operation.mutate(run) },
  ]);
}
```

全部确认弹窗的正文都是 `此操作将修改服务器配置。`（含句号），按钮固定 `取消` / `确认`（确认为破坏性样式）。标题逐字清单：

| 场景 | 标题模板 |
| --- | --- |
| 删除规则/实例 | `` `删除 ${itemName(item)}？` `` |
| 删除子规则（ingress / proxies / visitors） | `删除此规则？` |
| 创建 CNAME | `` `创建 ${text(child.hostname)} 的 CNAME？` `` |
| 删除 CNAME | `` `删除 ${text(child.hostname)} 的 CNAME？` `` |

**不弹确认**的操作：启停开关、上移、下移、复制地址、DNS 检测、子规则「启用 / 停用」、保存（编辑器内）。

### 8.6 `openDetail` / `openEditor`

`openDetail(mode, item)`：清空 `error`、清空 `dnsResult`、`setPage(mode === 'logs' && itemKey(item) ? 0 : 1)`、`setDetail({ mode, item })`。

`openEditor(item?, settings = false)`：
1. `busy` → 直接返回；清空 `error`
2. 无 `item` 且非 `settings`（新增）→ `setEditor({ title: \`新增${tunnelTitles[kind]}\`, type: kind, value: tunnelDefaults(kind), editing: false })`，**不发请求**
3. 否则：新建 `AbortController`，abort 上一个，`setLoadingEditor(true)`；
   - `settings` → `getStunSettings(signal)`，标题 `STUN 全局设置`，`type = 'stun-settings'`
   - 否则 → `getTunnel(kind, itemKey(item), signal)`，标题 `` `编辑 ${itemName(item)}` ``，`type = kind`
   - 两者 `editing: true`
4. 失败且未被取消 → `setError(e.message ?? '读取配置失败')`（非 Error 时用 `读取配置失败`）
5. `finally` 复位 `loadingEditor`

### 8.7 `save(value)`（编辑器提交后的落库分派）

1. `editor.type === 'stun-settings'` → `saveStunSettings(value)`
2. `editor.type` ∈ `ingress` / `proxies` / `visitors`：
   - `kind === 'stun'` → `throw new Error('操作类型无效')`
   - 否则 `saveTunnelChild(kind, itemKey(editor.parent), editor.type, value, editor.previous)`
3. 否则（主实例）：`cleaned = { ...value }`；**`kind === 'frp'` 时删除 `cleaned.proxies` 与 `cleaned.visitors`**（运行时小写别名不得覆盖可编辑数组），再 `saveTunnel(kind, cleaned, editor.editing)`
4. 成功后 `setNotice('配置已保存')` 并 `void invalidate()`

---

## 9. 模态优先级

同一时刻只渲染一个模态，优先级严格为：

```
natOpen → NatDetector
else editor → EditorModal
else detail → 详情 ScreenModal
else 无
```

因此从详情模态里点「新增规则 / 编辑」时，详情模态被编辑器**替换**（详情查询同时因 `!editor` 条件停止轮询）；关闭编辑器后详情模态重新出现并恢复轮询。

---

## 10. 详情模态（logs / status / 子集合）

标题逐字模板：
```
`${detail.mode === 'logs' ? '日志' : detail.mode === 'status' ? '运行详情' : collectionTitles[detail.mode]} · ${itemKey(detail.item) ? itemName(detail.item) : tunnelTitles[kind]}`
```
（模块级日志无 Key，故标题右半为模块名，如 `日志 · Cloudflared`）

关闭：`setDetail(undefined)` 且 `setError('')`；`busy = operation.isPending`（进行中不可关闭）。

内容顺序：
1. `error` → `ErrorState`
2. `details.error` → `ErrorState` + 重试（`details.refetch`）
3. 动作行（`flexWrap`、`gap 8`）：
   - `刷新`（`RefreshCw`），`disabled = details.isFetching` → `details.refetch()`
   - 子集合模式追加 `新增规则`（`Plus`），`disabled = operation.isPending` → `setEditor({ title: \`新增${collectionTitles[mode]}\`, type: mode, value: tunnelDefaults(mode), parent: detail.item, editing: false })`
4. `details.isLoading` → `ActivityIndicator color={colors.primary}`
5. 按模式渲染主体（下方 10.1 / 10.2 / 10.3）

`isCollection = detail && ['ingress', 'proxies', 'visitors'].includes(detail.mode)`。

### 10.1 日志视图

- 行来源：`tunnelLogLines(details.data)`（§5.12）
- 无日志且非加载中且无错误 → `EmptyState message="暂无日志" icon={FileText}`
- 有日志 → 逐行 `Text selectable`，`fontSize 12`、`lineHeight 18`、色 `text`（**无搜索/过滤功能**，无高亮，无等宽字体设置）
- 分页行（横向、`alignItems center`、`gap 8`）：
  - 左按钮 `ArrowUp`，标签 `page === 1 && itemKey(detail.item) ? '最新日志' : '上一页'`，禁用条件 `page <= (itemKey(detail.item) ? 0 : 1) || details.isFetching` → `setPage(page - 1)`
  - 中间 `Text` 色 `subtext`，内容 `page === 0 ? '实时' : page`
  - 右按钮 `ArrowDown`，标签 `page === 0 ? '历史日志' : '下一页'`，禁用条件 `details.isFetching || (page > 0 && logLines.length < 100)` → `setPage(page + 1)`
- 语义：`page === 0` = `lastlogs` 实时视图（仅规则级，需要 Key），`page >= 1` = `logs?pageSize=100&page=N` 历史分页；`page <= 1` 时自动 5 秒轮询
- 模块级日志（无 Key）最小页码为 `1`，因此没有「实时」态

### 10.2 运行详情（仅 frp `status`）

`StructuredDataView value={record(details.data).status ?? record(details.data).data ?? {}}`（候选键顺序 `status` → `data`，都没有则空对象）。

`StructuredDataView` 渲染规则（需 1:1 复刻）：
- 对象：过滤掉键 `ret`、`msg`；无条目 → 文本 `暂无数据`（`subtext`、12）；每项为「键名标签（`subtext`、`fontSize 11`、`fontWeight '700'`）+ 递归值」，容器 `gap 9`；`depth > 0` 时 `paddingLeft 10` + 左边框 1（`border` 色）；超过 200 条截断并显示 `仅显示前 200 个字段，共 N 个`
- 数组：空 → `暂无项目`；每项包裹 `padding 10`、`borderRadius 12`、背景 `mutedCard`，标题 `第 N 项`（`fontSize 10`、`700`、`subtext`）；超过 200 项显示 `仅显示前 200 项，共 N 项`
- 布尔 → `是` / `否`；`null` / `undefined` / `''` → `--`；其他 → `String(value)`；文本 `selectable`、`fontSize 12`、`lineHeight 18`、色 `text`
- 键名标签本地化表（`labels`）中与本屏相关的项：`name/Name → 名称`、`Enable → 启用`、`Remark → 备注名称`、`path → 路径`、`Options → 选项`、`Labels → 标签`、`error → 请求错误`；未命中时 `key.replace(/_/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2')`

### 10.3 子集合视图

- 数据：`detailItems = Array.isArray(details.data?.items) ? details.data.items : []`
- 空且非加载中且无错误 → `EmptyState message="暂无规则" icon={Network}`
- 末尾若 `dnsResult` 存在 → `StructuredDataView value={dnsResult.status ?? dnsResult}`（候选 `status` → 整个对象）

### 10.4 子规则卡片（`Panel`）

React key：`` `${text(child.name ?? child.hostname)}:${text(child.path)}:${index}` ``

- 标题：`text(child.name ?? child.hostname) || '默认路由'`（候选键顺序 `name` → `hostname`），`fontSize 14`、`fontWeight '700'`、色 `text`
- 描述行（`selectable`、`fontSize 12`、`lineHeight 18`、`subtext`），按模式逐字：

| 模式 | 模板 |
| --- | --- |
| `ingress` | `` `${text(child.path) \|\| '/'} → ${text(child.service)}` `` |
| `proxies` | `` `${text(child.type).toUpperCase()} · ${text(child.localIP)}:${text(child.localPort)} → ${text(child.remotePort) \|\| text(child.serverName) \|\| '域名代理'}` `` |
| `visitors` | `` `${text(child.type).toUpperCase()} · ${text(child.bindAddr)}:${text(child.bindPort)} → ${text(child.serverName)}` `` |

- 动作行（`flexWrap`、`gap 7`），顺序：

| 顺序 | 标签 | 图标 | 条件 | 行为 |
| --- | --- | --- | --- | --- |
| 1 | `编辑` | `Pencil` | 全部 | `setEditor({ title: '编辑规则', type: mode, value: { ...tunnelDefaults(mode), ...child }, previous: child, parent: detail.item, editing: true })`（默认值兜底 + 服务端值覆盖） |
| 2 | `启用` / `停用` | `RefreshCw` | `mode !== 'ingress'` | 标签 `child.disabled ? '启用' : '停用'`；`operation.mutate(() => saveTunnelChild('frp', itemKey(detail.item), mode, { ...child, disabled: !child.disabled }, child))` — 注意 kind **硬编码为 `'frp'`**，且走「编辑」PUT 语义（带 `oldName`） |
| 3 | `删除` | `Trash2`（danger） | 全部 | `confirm('删除此规则？', () => deleteTunnelChild(kind, itemKey(detail.item), mode, child))` |
| 4 | `检测 DNS` | `Globe2` | `mode === 'ingress' && child.hostname` | `operation.mutate(async () => { setDnsResult(await cloudflareDns(itemKey(detail.item), text(child.hostname), 'check')); })` |
| 5 | `创建 DNS` | `Plus` | 同上 | `confirm(\`创建 ${text(child.hostname)} 的 CNAME？\`, () => cloudflareDns(key, hostname, 'create'))` |
| 6 | `删除 DNS` | `Trash2`（danger） | 同上 | `confirm(\`删除 ${text(child.hostname)} 的 CNAME？\`, () => cloudflareDns(key, hostname, 'delete'))` |

所有子规则按钮的 `disabled` 均为 `operation.isPending`（不含 `loadingEditor`）。

---

## 11. 编辑器模态 `EditorModal`

Props：`{ editor: Editor; save: (value) => Promise<unknown>; close: () => void }`

- 本地 `value` 初值 = `JSON.parse(JSON.stringify(editor.value))`（深拷贝，取消即丢弃）
- 本地 `error`、`result` 字符串
- 保存 mutation：`setError('')` → `save(validateTunnelForm(editor.type, value))`；成功 → `close()`；失败 → `setError(e.message)`
- Webhook 测试 mutation（§11.2）
- `busy = mutation.isPending || webhook.isPending`

结构（`ScreenModal` 内）：
1. `error` → `ErrorState`
2. `TunnelForm type={editor.type} value={value} onChange={setValue} disabled={busy}`
3. 当 `(editor.type === 'stun' || editor.type === 'stun-settings') && value.WebhookEnable` → `Action icon={Webhook} label="测试 Webhook" disabled={busy}`
4. `result` 非空 → `Text selectable`，`fontSize 12`、`lineHeight 18`、色 `text`

底部按钮（footer）：`height 48`、`borderRadius 12`、背景 `busy ? colors.disabled : colors.primary`、横向居中、`gap 8`；内容 `busy` 时 `ActivityIndicator color="#fff"`，否则 `Save size 17 color="#fff"`；文字白色 `fontWeight '700'`，文案：

```
mutation.isPending ? '保存中'
  : (editor.type === 'stun' && !editor.editing) ? '创建并启用'
  : '保存'
```

### 11.1 编辑器标题逐字

| 场景 | 标题 |
| --- | --- |
| 新增主实例 | `` `新增${tunnelTitles[kind]}` ``（`新增STUN 内网穿透` / `新增Cloudflared` / `新增FRP 内网穿透`，**无空格**） |
| 编辑主实例 | `` `编辑 ${itemName(item)}` `` |
| STUN 全局设置 | `STUN 全局设置` |
| 新增子规则 | `` `新增${collectionTitles[mode]}` ``（`新增域名路由` / `新增代理规则` / `新增访问者`） |
| 编辑子规则 | `编辑规则` |

### 11.2 Webhook 测试

```
1. text(value.WebhookURL).trim() 为空 → throw new Error('请先填写 Webhook 地址')
2. candidate = validateTunnelForm(editor.type, value)   // 完整校验，可抛出任意字段错误
3. payload = candidate 中「键名 startsWith('Webhook') 或 === 'RetryCount' 或 === 'RetryInterval'」的条目
4. testStunWebhook(text(value.Key), payload)   // POST /api/stunrule/webhooktest?key=<Key 或 '666'>
5. 成功 → setError('')，setResult(text(data.Response) || text(data.msg) || 'Webhook 请求成功')
6. 失败 → setError(e.message)
```

---

## 12. NAT 类型检测模态（仅 stun）

标题 `NAT 类型检测`。状态：`server`（初值 `'stun.miwifi.com:3478'`）、`lines: string[]`、`busy`、`socketRef`、`timerRef`。

结构（`ScreenModal`，无 footer）：
1. `TextInput`：`accessibilityLabel="STUN 服务器"`、`minHeight 46`、`borderRadius 12`、`padding 12`、`borderWidth 1` 色 `border`、文字色 `text`、`autoCapitalize="none"`、`autoCorrect={false}`、`editable={!busy}`
2. `Action icon={Network} label={busy ? '停止检测' : '开始检测'}`，按下时 `busy ? stop() : start()`
3. `lines` 逐行 `Text selectable`（`fontSize 12`、`lineHeight 18`、色 `text`）

`start()` 流程：
1. `stop()`；`setLines([])`
2. `!server.trim()` → `setLines(['请填写 STUN 服务器'])` 并返回
3. URL = `${luckySessionState.baseUrl.replace(/\/+$/, '')}/api/natdetect/ws`；协议 `https:` → `wss:`，否则 `ws:`
4. 查询参数顺序：`Lucky-Admin-Token`（会话 token）、`server`（trim 后）、`_`（`String(Date.now())`）
5. `setBusy(true)`，建立 `WebSocket`
6. `onmessage`：忽略非当前 socket；尝试 `JSON.parse`
   - 成功：追加 `text(data.log ?? data.result ?? data.error)`（候选键顺序 `log` → `result` → `error`），`filter(Boolean)` 去空，仅保留**最后 200 行**（`slice(-200)`）；若 `data.result || data.error` 为真 → `stop()`
   - 解析失败：追加 `String(event.data)`，同样 `slice(-200)`
7. `onerror`：追加 `检测连接失败，请检查服务端连接` 并 `stop()`
8. `onclose`：`stop()`
9. 超时定时器 `60000` ms：追加 `检测超时` 并 `stop()`
10. 构造异常：`setLines([e.message ?? '无法启动检测'])` 并 `stop()`

`stop()`：清除定时器、置空 `socketRef`、关闭 socket、`setBusy(false)`。关闭模态时先 `stop()` 再 `close()`；组件卸载时清理定时器与 socket。

---

## 13. `TunnelForm` 布局与控件

外层 `gap: 15`。渲染顺序：

1. **基础字段** = `fields(type, value, false)`，并过滤掉 `type === 'stun' && !value.Key && spec.key === 'Enable'`（新建 STUN 规则时隐藏「启用规则」）
2. **定制模式区块**（仅 `type === 'stun' && value.DiaglogShowMode === 'diy'`）：分隔线（`borderTopWidth 1`，色 `rowBorder`，`paddingTop 4`）+ 标题 `定制模式参数`（`fontSize 14`、`fontWeight '700'`、`paddingTop 12`、色 `text`），随后渲染 `fields(type, value, true)`
3. **高级设置开关**（仅 `type` 不是 `stun` / `stun-settings`）：`Pressable`，`minHeight 44`、`gap 8`；图标 `ChevronUp`（展开）/ `ChevronDown`（收起）`size 17` 色 `primary`；文字 `高级设置`（`fontSize 13`、色 `primary`）
4. 展开后渲染 `fields(type, value, true)`
5. 展开后再显示「其他参数」开关（`minHeight 44`、文字 `fontSize 12`、色 `subtext`，文案 `extras ? '收起其他参数' : '其他参数'`），打开后渲染 `StructuredForm`（§13.3）

`fixedMode = type === 'stun' || type === 'stun-settings'`（这两种没有「高级设置」/「其他参数」开关；stun 的高级字段由 `DiaglogShowMode = 'diy'` 控制）。

### 13.1 `FormField` 控件规格

| 控件类型 | 规格 |
| --- | --- |
| 标签 | `Text`，`flex: 1`、`fontSize 13`、`fontWeight '600'`、色 `text`；`required` 时文本后追加 `' *'` |
| `switch` | 行容器 `minHeight 46`、横向、`gap 12`；`Switch value={value === true}`、`accessibilityLabel = label` |
| 选项（`options`） | 竖排「标签 + 选项行」，`gap 8`；选项行 `flexWrap`、`gap 6`；每个选项 `Pressable accessibilityRole="radio" accessibilityState={{ checked }}`，`minHeight 40`、`padding 10`、`borderRadius 10`、`borderWidth 1`；选中 → 边框 `primary`、背景 `primarySoft`、文字 `primary`；未选中 → 边框 `border`、背景 `card`、文字 `text`；文字 `fontSize 12`，显示 `optionLabels[option] ?? option` |
| 文本 / 数字 / 多行 / 密钥 | 外框横向容器 `borderWidth 1` 色 `border`、`borderRadius 12`、背景 `card`；`TextInput` `flex: 1`、`minHeight` = 112（`lines` / `multiline`）否则 46、`padding 12`、`fontSize 13`、`lineHeight 19`、色 `text`；`autoCapitalize="none"`、`autoCorrect={false}`；`keyboardType = 'number-pad'`（number）否则 `default`；`secureTextEntry = type === 'secret' && !revealed`；`multiline`/`textAlignVertical: 'top'` 用于 `lines` 与 `multiline` |
| `lines` 值绑定 | 显示 `Array.isArray(value) ? value.join('\n') : String(value ?? '')`；输入变更时 `next.split('\n')` 存回数组 |
| `secret` 眼睛按钮 | `padding 12`，图标 `Eye` / `EyeOff` `size 18` 色 `subtext`；`accessibilityLabel = revealed ? '隐藏密钥' : '显示密钥'` |

嵌套键用点号路径（如 `Params.BindPort`、`Options.SafeMode`、`originRequest.noTLSVerify`、`transport.useEncryption`），读写通过 `get` / `set` 逐段处理，缺失层级自动视为 `{}`。

### 13.2 选项标签映射 `optionLabels`（逐字）

```ts
{
  '': '无', simple: '简易模式', diy: '定制模式', client: '客户端', server: '服务端',
  tunnel: 'Tunnel 隧道', access: 'Access 访问', auto: '自动', ip: 'IP 地址',
  networkInterface: '指定网卡', tcp4: 'TCP / IPv4', udp4: 'UDP / IPv4',
  blacklist: '黑名单', globalblacklist: '全局黑名单', whitelist: '白名单',
}
```

未命中的选项（如 `tcp`、`kcp`、`quic`、`http2`、`post`、`socks5`、`v1`、`4`、`6`…）**原样显示**。

### 13.3 「其他参数」`StructuredForm`

- `covered` = `fields(type, value, false)` 与 `fields(type, value, true)` 的全部 `key` 集合
- `extra` = `value` 中键不在 `covered`、且不属于 `['Key', 'ret', 'msg', 'Proxies', 'Visitors', 'proxies', 'visitors']` 的条目；若值为普通对象，则再剔除其中 `` `${key}.${child}` `` 已被覆盖的子键
- 变更合并：先把旧 `extra` 的键从 `value` 中移除（对象类型保留未被 extra 覆盖的子键），再把新条目写回（对象做浅合并）
- `StructuredForm` 控件：布尔 → 开关行（`minHeight 44`）；数字 → 数字输入（`minHeight 44`、`borderRadius 12`、`fontSize 12`，失焦提交，非法回退原值）；字符串 → 文本输入（键名匹配 `/content|script|dockerfile|forbidden|indexnames|paths|command/i` 时多行 `minHeight 112`，`/content|script|dockerfile|command/i` 时等宽字体）；数组 → 列表编辑（追加按钮 `文本项` / `数字项` / `开关项` / `对象项` / `列表项`，项标题 `第 N 项`，删除按钮 `38×38` 背景 `dangerBg`）；对象 → 递归（`depth > 0` 时 `padding 12` + 边框 + `borderRadius 14`）
- 新增字段面板：输入框 placeholder `字段名称`，重复时提示 `该字段已存在`；类型选项 `文本` / `数字` / `开关` / `对象` / `列表`（初值 `''` / `0` / `false` / `{}` / `[]`）；按钮 `取消` / `添加`；折叠态按钮文案 `添加字段`

---

## 14. 字段模式（标签 → 载荷键 → 控件 → 选项/范围 → 必填 → 默认值）

表中「条件」为空表示始终显示。`port(key, label, required)` = 数字控件，`min = required ? 1 : 0`，`max = 65535`。

### 14.1 Webhook 字段块（`stun` 与 `stun-settings` 共用，追加在基础字段末尾）

`WebhookEnable` 为假时**只显示第 1 行**。

| # | 标签 | 载荷键 | 控件 | 选项 / 范围 | 必填 | 默认 | 条件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 启用 Webhook | `WebhookEnable` | switch | — | — | `false` | |
| 2 | 仅地址变更时通知 | `WebhookOnlyAddrChange` | switch | — | — | `true` | `WebhookEnable` |
| 3 | Webhook 地址 | `WebhookURL` | text | — | ✅ | `''` | `WebhookEnable` |
| 4 | 请求方法 | `WebhookMethod` | options | `get` / `post` / `put` / `patch` | ✅ | `'post'` | `WebhookEnable` |
| 5 | 请求头 | `WebhookHeaders` | lines | — | — | `[]` | `WebhookEnable` |
| 6 | 请求内容 | `WebhookRequestBody` | multiline | — | — | `''` | `WebhookEnable && WebhookMethod !== 'get'` |
| 7 | 重试次数 | `RetryCount` | number | 0 ～ 10 | — | `0` | `WebhookEnable` |
| 8 | 重试间隔（毫秒） | `RetryInterval` | number | 500 ～ 10000 | — | `500` | `WebhookEnable && Number(RetryCount) > 0` |
| 9 | 跳过响应内容检查 | `WebhookDisableCallbackSuccessContentCheck` | switch | — | — | `true` | `WebhookEnable` |
| 10 | 成功响应关键字 | `WebhookSuccessContent` | lines | — | ✅ | `[]` | `WebhookEnable && !WebhookDisableCallbackSuccessContentCheck` |
| 11 | 代理类型 | `WebhookProxy` | options | `''`(无) / `http` / `https` / `socks5` / `dns` | — | `''` | `WebhookEnable` |
| 12 | 代理地址 | `WebhookProxyAddr` | text | — | 仅当 `WebhookProxy !== 'dns'` | `''` | `WebhookEnable && WebhookProxy` |
| 13 | 代理账号 | `WebhookProxyUser` | text | — | — | `''` | 同上 |
| 14 | 代理密码 | `WebhookProxyPassword` | secret | — | — | `''` | 同上 |

### 14.2 `stun-settings`（STUN 全局设置，`GET/PUT /api/stun/configure`）

无高级字段（`fields('stun-settings', v, true)` 返回空数组），无「高级设置」开关。

| # | 标签 | 载荷键 | 控件 | 必填 | 默认 |
| --- | --- | --- | --- | --- | --- |
| 1 | 启用 STUN 模块 | `EnableModule` | switch | — | `true` |
| 2 | 全局 STUN 服务器 | `GlobalStunServerList` | lines | — | `[]` |
| 3+ | （§14.1 Webhook 字段块） | | | | |

### 14.3 `stun` 基础字段（简易模式，始终显示）

| # | 标签 | 载荷键 | 控件 | 选项 / 范围 | 必填 | 默认 | 条件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 规则名称 | `Name` | text | — | ✅ | `''` | |
| 2 | 启用规则 | `Enable` | switch | — | — | `true` | 仅当 `value.Key` 非空（新建时隐藏） |
| 3 | 配置模式 | `DiaglogShowMode` | options | `simple`(简易模式) / `diy`(定制模式) | — | `'simple'` | |
| 4 | 穿透协议 | `StunType` | options | `tcp4`(TCP / IPv4) / `udp4`(UDP / IPv4) | — | `'tcp4'` | |
| 5 | 监听端口（0 为自动） | `ListenPort` | number | 0 ～ 65535 | — | `0` | |
| 6 | 自动配置防火墙 | `AutoOptionsFirewall` | switch | — | — | `true` | |
| 7 | UPnP | `UPnP` | switch | — | — | `false` | |
| 8 | UPnP 网关 IP | `UPnPGawayIP` | text | — | — | `''` | `UPnP` |
| 9 | UPnP 客户端本地 IP | `UPnpLocalHost` | text | — | — | `''` | `UPnP` |
| 10 | UPnP 控制接口地址 | `UpnPDiyControlAPIUrl` | text | — | — | `''` | `UPnP` |
| 11 | NAT-PMP | `NatPMP` | switch | — | — | `false` | |
| 12 | NAT-PMP 网关 | `NatPMPGateway` | text | — | — | `''` | `NatPMP` |
| 13 | 映射的本地端口 | `UPnPLocalPort` | number | 0 ～ 65535 | — | `0` | `(UPnP \|\| NatPMP) && DisablePortForward` |
| 14 | 仅获取公网地址 | `DisablePortForward` | switch | — | — | `false` | |
| 15 | 跳过 STUN 有效性检查 | `DisableStunAvalidCheck` | switch | — | — | `false` | `!DisablePortForward` |
| 16 | 目标地址 | `TargetAddressList` | lines | — | ✅ | `['127.0.0.1']` | `!DisablePortForward` |
| 17 | 目标端口 | `TargetPort` | number | 1 ～ 65535 | ✅ | `80` | `!DisablePortForward` |
| 18 | 执行自定义脚本 | `CallScript` | switch | — | — | `false` | |
| 19 | 脚本内容 | `CallScriptContent` | multiline | — | ✅ | `''` | `CallScript` |
| 20 | 使用全局 Webhook | `GlobalWebhook` | switch | — | — | `false` | |
| 21+ | （§14.1 Webhook 字段块） | | | | | | |

### 14.4 `stun` 定制模式字段（仅 `DiaglogShowMode === 'diy'` 时显示 **且** 参与校验）

| # | 标签 | 载荷键 | 控件 | 选项 / 范围 | 必填 | 默认 | 条件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | IP 过滤模式 | `Options.SafeMode` | options | `blacklist`(黑名单) / `globalblacklist`(全局黑名单) / `whitelist`(白名单) | — | `'blacklist'` | |
| 2 | 公网地址自动加入白名单 | `AutoAddPubAddrWhiteList` | switch | — | — | `false` | `Options.SafeMode === 'whitelist'` |
| 3 | 监听方式 | `StunListenType` | options | `ip`(IP 地址) / `networkInterface`(指定网卡) | — | `'ip'` | |
| 4 | 监听 IP（留空自动选择） | `ListenIP` | text | — | — | `''` | `StunListenType === 'ip'` |
| 5 | 网卡名称 | `SpecifyNetworkInterface` | text | — | — | `''` | `StunListenType !== 'ip'` |
| 6 | 地址匹配表达式 | `NetworkInterfaceReg` | text | — | — | `''` | `StunListenType !== 'ip'` |
| 7 | 跳过自身转发检查 | `Options.DisableSelfForwardingCheck` | switch | — | — | `false` | |
| 8 | 单端口限速 | `Options.SinglePortSpeedLimit` | switch | — | — | `false` | `!DisablePortForward && StunType === 'tcp4'` |
| 9 | 单端口最大发送速度 | `Options.SinglePortSendSpeedLimit` | number | 30 ～ 1000000 | — | `0` | 上一条为真 |
| 10 | 单端口最大接收速度 | `Options.SinglePortReceSpeedLimit` | number | 30 ～ 1000000 | — | `0` | 同上 |
| 11 | 单端口最大 TCP 连接数 | `Options.SingleProxyMaxTCPConnections` | number | 1 ～ 1024 | — | `256` | tcp4 分支 |
| 12 | 来源启用 TLS | `Options.TCPListenTLS` | switch | — | — | `false` | tcp4 分支 |
| 13 | 接收端启用 TLS | `Options.TCPRelayTLS` | switch | — | — | `false` | tcp4 分支 |
| 14 | 跳过 TLS 证书校验 | `Options.TCPRelayTLSInsecureSkipVerify` | switch | — | — | `false` | `Options.TCPRelayTLS` |
| 15 | TLS 转发服务域名 | `Options.TCPRelayTLSServerName` | text | — | — | `''` | `Options.TCPRelayTLS` |
| 16 | 来源流加密 | `Options.TCPStreamEncryptionSource` | switch | — | — | `false` | tcp4 分支 |
| 17 | 接收端流加密 | `Options.TCPStreamEncryptionAccept` | switch | — | — | `false` | tcp4 分支 |
| 18 | 流加密密钥 | `Options.TCPStreamEncryptionKey` | secret | — | ✅ | `''` | 16 或 17 为真 |

| 19 | UDP 会话超时（毫秒） | `Options.UDPSessionTimeout` | number | 30 ～ 300000 | — | `30000` | `!DisablePortForward && StunType === 'udp4'` |
| 20 | 单端口最大 UDP 会话数 | `Options.SingleProxyMaxUDPReadTargetDatagoroutineCount` | number | 0 ～ 32 | — | `32` | udp4 分支 |
| 21 | UDP 数据包最大长度 | `Options.UDPPacketSize` | number | 1 ～ 65507 | — | `1500` | udp4 分支 |
| 22 | UDP 短连接模式 | `Options.UDPShortMode` | switch | — | — | `false` | udp4 分支 |
| 23 | 来源数据包加密 | `Options.UDPPacketSourceEncryption` | switch | — | — | `false` | udp4 分支 |
| 24 | 接收端数据包加密 | `Options.UDPPacketAcceptEncryption` | switch | — | — | `false` | udp4 分支 |
| 25 | 数据包加密密钥 | `Options.UDPPacketEncryptionKey` | secret | — | ✅ | `''` | 23 或 24 为真 |
| 26 | 使用全局 STUN 服务器 | `UseGlobalStunServerList` | switch | — | — | `true` | |
| 27 | STUN 服务器 | `StunServerList` | lines | — | ✅ | `['stun.miwifi.com:3478']` | `!UseGlobalStunServerList` |
| 28 | TCP 保活服务器 | `TcpKeepAliveServerList` | lines | — | — | `[]` | `StunType === 'tcp4'` |
| 29 | STUN 超时（毫秒） | `StunTimeout` | number | 1000 ～ 10000 | — | `3000` | |
| 30 | 心跳检测间隔（毫秒） | `StunHeartbeatInterval` | number | 1000 ～ 10000 | — | `2300` | |
| 31 | 穿透重试间隔（毫秒） | `StunRetryInterval` | number | 1000 ～ 10000 | — | `3000` | |
| 32 | 穿透失败自动重试 | `StunAutoRetry` | switch | — | — | `true` | |
| 33 | 日志级别 | `LogLevel` | number | 0 ～ 6 | — | `4` | |
| 34 | 日志输出到终端 | `LogOutputToConsole` | switch | — | — | `false` | |
| 35 | 最大访问日志数 | `AccessLogMaxNum` | number | 0 ～ 102400 | — | `128` | |
| 36 | 页面显示最新日志数 | `WebListShowLastLogMaxCount` | number | 1 ～ 64 | — | `20` | |

### 14.5 `cloudflared` 基础字段

| # | 标签 | 载荷键 | 控件 | 选项 / 范围 | 必填 | 默认 | 条件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 实例名称 | `Remark` | text | — | ✅ | `''` | |
| 2 | 启用实例 | `Enable` | switch | — | — | `true` | |
| 3 | 实例类型 | `Type` | options | `tunnel`(Tunnel 隧道) / `access`(Access 访问) | — | `'tunnel'` | |
| 4 | 访问域名 | `Params.Hostname` | text | — | ✅ | `''` | `Type === 'access'` |
| 5 | 本地监听地址 | `Params.URL` | text | — | ✅ | `''` | `Type === 'access'` |
| 6 | 服务令牌 ID | `Params.TokenId` | secret | — | — | `''` | `Type === 'access'` |
| 7 | 服务令牌密钥 | `Params.TokenSecret` | secret | — | — | `''` | `Type === 'access'` |
| 8 | 隧道 Token | `Params.Token` | secret | — | ✅ | `''` | `Type !== 'access'` |
| 9 | 边缘 IP 版本 | `Params.EdgeIpVersion` | options | `auto`(自动) / `4` / `6` | — | `'auto'` | `Type !== 'access'` |
| 10 | 连接协议 | `Params.Protocol` | options | `auto`(自动) / `http2` / `quic` | — | `'http2'` | `Type !== 'access'` |
| 11 | 连接数 | `Params.HaConnections` | number | 1 ～ 8 | — | `4` | `Type !== 'access'` |
| 12 | 跳过源站 TLS 校验 | `Params.NoTlsVerify` | switch | — | — | `false` | 始终（两种类型都在末尾） |

### 14.6 `cloudflared` 高级字段（「高级设置」展开显示，**始终参与校验**）

| # | 标签 | 载荷键 | 控件 | 默认 | 条件 |
| --- | --- | --- | --- | --- | --- |
| 1 | 请求头 | `Params.HeaderList` | multiline | `''` | `Type === 'access'` |
| 2 | 目标地址 | `Params.Destination` | text | `''` | `Type === 'access'` |
| 3 | 连接地址 | `Params.ConnectTo` | text | `''` | `Type === 'access'` |
| 4 | User Agent | `Params.UserAgent` | text | `''` | `Type === 'access'` |
| 5 | Cloudflare API Token | `Params.CFApiToken` | secret | `''` | `Type !== 'access'` |
| 6 | 账户 ID | `Params.CFAccountId` | text | `''` | `Type !== 'access'` |
| 7 | 隧道 ID | `Params.CFTunnelId` | text | `''` | `Type !== 'access'` |
| 8 | 边缘绑定地址 | `Params.EdgeBindAddress` | text | `''` | `Type !== 'access'` |
| 9 | ICMP IPv4 源地址 | `Params.ICMPV4Src` | text | `''` | `Type !== 'access'` |
| 10 | ICMP IPv6 源地址 | `Params.ICMPV6Src` | text | `''` | `Type !== 'access'` |

### 14.7 `frp` 基础字段（客户端 / 服务端）

| # | 标签 | 载荷键 | 控件 | 选项 / 范围 | 必填 | 默认 | 条件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 实例名称 | `Remark` | text | — | ✅ | `''` | |
| 2 | 启用实例 | `Enable` | switch | — | — | `true` | |
| 3 | 实例类型 | `Type` | options | `client`(客户端) / `server`(服务端) | — | `'client'` | |
| 4 | 监听地址 | `Params.BindAddr` | text | — | — | `'0.0.0.0'` | `Type === 'server'` |
| 5 | 监听端口 | `Params.BindPort` | number | 1 ～ 65535 | ✅ | `7000` | `Type === 'server'` |
| 6 | HTTP 虚拟主机端口 | `Params.VhostHTTPPort` | number | 0 ～ 65535 | — | `0` | `Type === 'server'` |
| 7 | HTTPS 虚拟主机端口 | `Params.VhostHTTPSPort` | number | 0 ～ 65535 | — | `0` | `Type === 'server'` |
| 8 | 服务器地址 | `Params.ServerAddr` | text | — | ✅ | `''` | `Type !== 'server'` |
| 9 | 服务器端口 | `Params.ServerPort` | number | 1 ～ 65535 | ✅ | `7000` | `Type !== 'server'` |
| 10 | 传输协议 | `Params.Protocol` | options | `tcp` / `kcp` / `quic` / `websocket` / `wss` | — | `'tcp'` | `Type !== 'server'` |
| 11 | 认证方式 | `Params.AuthMethod` | options | `token` / `oidc` | — | `'token'` | `Type !== 'server'` |
| 12 | 启用 TLS | `Params.TLSEnable` | switch | — | — | `true` | `Type !== 'server'` |
| 13 | 认证 Token | `Params.Token` | secret | — | — | `''` | 始终（两种类型都在末尾） |

### 14.8 `frp` 高级字段（**始终参与校验**）

服务端（`Type === 'server'`）：

| # | 标签 | 载荷键 | 控件 | 范围 | 默认 |
| --- | --- | --- | --- | --- | --- |
| 1 | KCP 监听端口 | `Params.KCPBindPort` | number | 0 ～ 65535 | `0` |
| 2 | QUIC 监听端口 | `Params.QUICBindPort` | number | 0 ～ 65535 | `0` |
| 3 | 允许端口范围 | `Params.AllowPorts` | text | — | `''` |
| 4 | 管理面板端口 | `Params.DashboardPort` | number | 0 ～ 65535 | `0` |
| 5 | 管理面板账号 | `Params.DashboardUser` | text | — | `'admin'` |
| 6 | 管理面板密码 | `Params.DashboardPassword` | secret | — | 默认对象中**不存在**该键（初值 `undefined`，显示为空串） |
| 7 | 强制 TLS | `Params.TLSOnly` | switch | — | `false` |

客户端（`Type !== 'server'`）：

| # | 标签 | 载荷键 | 控件 | 范围 | 默认 |
| --- | --- | --- | --- | --- | --- |
| 1 | 用户标识 | `Params.User` | text | — | `''` |
| 2 | NAT 穿透 STUN 服务器 | `Params.NatHoleStunServer` | text | — | `''` |
| 3 | 连接代理 URL | `Params.ProxyURL` | text | — | `''` |
| 4 | DNS 服务器 | `Params.DNSServer` | text | — | `''` |
| 5 | TLS 服务名 | `Params.TLSServerName` | text | — | `''` |
| 6 | 跳过 TLS 证书校验 | `Params.TLSInsecureSkipVerify` | switch | — | `false` |
| 7 | 心跳间隔（秒） | `Params.HeartbeatInterval` | number | ≥ 1（无上限） | `30` |
| 8 | 心跳超时（秒） | `Params.HeartbeatTimeout` | number | ≥ 1（无上限） | `90` |
| 9 | OIDC 客户端 ID | `Params.OIDCClientID` | text | — | `''` |
| 10 | OIDC 客户端密钥 | `Params.OIDCClientSecret` | secret | — | `''` |
| 11 | OIDC 令牌地址 | `Params.OIDCTokenEndpointURL` | text | — | `''` |
| 12 | OIDC Audience | `Params.OIDCAudience` | text | — | `''` |
| 13 | OIDC Scope | `Params.OIDCScope` | text | — | `''` |

`min` 存在而 `max` 缺失时，越界文案后缀为 `（1 起）`（见 §15）。

### 14.9 `ingress`（Cloudflared 域名路由，键名**小写驼峰**）

基础：

| # | 标签 | 载荷键 | 控件 | 必填 | 默认 |
| --- | --- | --- | --- | --- | --- |
| 1 | 域名（留空为兜底规则） | `hostname` | text | — | `''` |
| 2 | 路径表达式 | `path` | text | — | `''` |
| 3 | 后端服务 | `service` | text | ✅ | `'http://127.0.0.1:80'` |
| 4 | 跳过源站 TLS 校验 | `originRequest.noTLSVerify` | switch | — | `false` |

高级（始终参与校验）：

| # | 标签 | 载荷键 | 控件 | 默认 |
| --- | --- | --- | --- | --- |
| 1 | 源站 TLS 服务名 | `originRequest.originServerName` | text | `''` |
| 2 | 源站 Host | `originRequest.httpHostHeader` | text | `''` |
| 3 | 源站 HTTP/2 | `originRequest.http2Origin` | switch | `false` |
| 4 | 连接超时（例如 30s） | `originRequest.connectTimeout` | text | 默认对象中**不存在**该键 |

### 14.10 `proxies`（FRP 代理规则）

基础：

| # | 标签 | 载荷键 | 控件 | 选项 / 范围 | 必填 | 默认 | 条件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 代理名称 | `name` | text | — | ✅ | `''` | |
| 2 | 代理类型 | `type` | options | `tcp` / `udp` / `http` / `https` / `stcp` / `xtcp` / `sudp` / `tcpmux` | — | `'tcp'` | |
| 3 | 停用代理 | `disabled` | switch | — | — | `false` | |
| 4 | 本地地址 | `localIP` | text | — | — | `'127.0.0.1'` | |
| 5 | 本地端口 | `localPort` | number | 1 ～ 65535 | ✅ | `80` | |
| 6 | 远端端口 | `remotePort` | number | 1 ～ 65535 | ✅ | `8080` | `type ∈ {tcp, udp}` |
| 7 | 自定义域名 | `customDomains` | lines | — | — | 默认对象中不存在 | `type ∈ {http, https, tcpmux}` |
| 8 | 子域名 | `subdomain` | text | — | — | 默认对象中不存在 | `type ∈ {http, https, tcpmux}` |
| 9 | 访问密钥 | `secretKey` | secret | — | ✅ | 默认对象中不存在 | `type ∈ {stcp, xtcp, sudp}` |

判定用 `proxyType = String(value.type ?? 'tcp')`。

高级（始终参与校验）：

| # | 标签 | 载荷键 | 控件 | 选项 | 默认 |
| --- | --- | --- | --- | --- | --- |
| 1 | 加密 | `useEncryption` | switch | — | `false` |
| 2 | 压缩 | `useCompression` | switch | — | `false` |
| 3 | Proxy Protocol | `proxyProtocolVersion` | options | `''`(无) / `v1` / `v2` | `''` |
| 4 | 带宽限制（例如 1MB） | `bandwidthLimit` | text | — | 默认对象中不存在 |
| 5 | 插件 | `plugin` | options | `''`(无) / `http_proxy` / `socks5` / `static_file` / `unix_domain_socket` / `http2https` / `https2http` / `https2https` / `tls2raw` | `''` |

默认对象另含 `natTraversal: { disableAssistedAddrs: false }`（无对应字段，出现在「其他参数」中）。

### 14.11 `visitors`（FRP 访问者）

基础：

| # | 标签 | 载荷键 | 控件 | 选项 / 范围 | 必填 | 默认 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 访问者名称 | `name` | text | — | ✅ | `''` |
| 2 | 访问类型 | `type` | options | `stcp` / `xtcp` / `sudp` | — | `'stcp'` |
| 3 | 停用访问者 | `disabled` | switch | — | — | `false` |
| 4 | 服务端代理名称 | `serverName` | text | — | ✅ | `''` |
| 5 | 访问密钥 | `secretKey` | secret | — | ✅ | `''` |
| 6 | 本地监听地址 | `bindAddr` | text | — | — | `'127.0.0.1'` |
| 7 | 本地监听端口 | `bindPort` | number | 1 ～ 65535 | ✅ | `8080` |

高级（始终参与校验）：

| # | 标签 | 载荷键 | 控件 | 选项 | 默认 |
| --- | --- | --- | --- | --- | --- |
| 1 | 加密 | `transport.useEncryption` | switch | — | `false` |
| 2 | 压缩 | `transport.useCompression` | switch | — | `false` |
| 3 | 保持隧道连接 | `keepTunnelOpen` | switch | — | `false` |
| 4 | 服务端用户 | `serverUser` | text | — | `''` |
| 5 | 穿透协议 | `protocol` | options | `quic` / `kcp` | `'quic'` |

默认对象另含无字段项：`maxRetriesAnHour: 8`、`minRetryInterval: 90`、`fallbackTo: ''`、`fallbackTimeoutMs: 0`（出现在「其他参数」中）。

---

## 15. 校验 `validateTunnelForm(type, value)`（保存前必须执行，返回规范化后的对象）

参与校验的字段集合（严格）：

| type | 集合 |
| --- | --- |
| `stun` | 基础字段 + （`DiaglogShowMode === 'diy'` 时）定制模式字段 |
| `stun-settings` | 仅基础字段 |
| 其余（`cloudflared` / `frp` / `ingress` / `proxies` / `visitors`） | 基础字段 **+ 高级字段（无论是否展开）** |

逐字段规则（按集合顺序执行，逐步改写 `result`）：

1. **必填**：`v == null || !String(v).trim() || (Array.isArray(v) && !v.some(x => String(x).trim()))`
   → `` throw new Error(`请填写${f.label}`) ``（如 `请填写规则名称`、`请填写实例名称`、`请填写后端服务`、`请填写访问密钥`、`请填写目标端口`）
2. **数字**（`type === 'number'` 且 `v !== undefined`）：`n = Number(v)`；非法条件 `v === '' || !Number.isInteger(n) || (min !== undefined && n < min) || (max !== undefined && n > max)`
   → `` throw new Error(`${f.label}范围无效${min !== undefined ? `（${min}${max !== undefined ? `～${max}` : ' 起'}）` : ''}`) ``
   例：`监听端口（0 为自动）范围无效（0～65535）`、`目标端口范围无效（1～65535）`、`心跳间隔（秒）范围无效（1 起）`、`重试次数范围无效（0～10）`
   合法则**写回为数字**（字符串输入转 number）
3. **lines**：`(Array.isArray(v) ? v : []).map(String).map(trim).filter(Boolean)` 写回（非数组一律变空数组）

跨字段规则（顺序在逐字段之后）：

4. `(type === 'stun' || type === 'stun-settings') && result.WebhookEnable && (!String(result.WebhookURL ?? '').trim() || !result.WebhookMethod)`
   → `throw new Error('请填写 Webhook 地址和请求方法')`
5. `type === 'stun' && result.NatPMP && result.UPnP` → `throw new Error('NAT-PMP 和 UPnP 只能启用一项')`
6. `type === 'frp' && ['kcp', 'quic'].includes(String(result.Params.Protocol))` → 强制 `result.Params.TCPMux = false`

返回值即提交给服务端的对象（`save()` 再做 §8.7 的分派与 frp 别名清理）。

---

## 16. 表单联动 `updateTunnelFormValue(type, value, key, next)`

1. `key === 'Type' && (type === 'frp' || type === 'cloudflared')`：
   ```ts
   { ...value, Type: next, Params: { ...record(tunnelDefaults(type, String(next)).Params), ...record(value.Params) } }
   ```
   即切换客户端/服务端、Tunnel/Access 时，用新类型的 `Params` 默认值补底，**已有 `Params` 键优先保留**
2. 其他情况先 `set(value, key, next)`（支持点号路径）
3. `type !== 'stun'` → 直接返回
4. `type === 'stun'`（`simple = updated.DiaglogShowMode !== 'diy'`）：

| 触发 | 副作用 |
| --- | --- |
| `AutoOptionsFirewall` → `true` | `DisablePortForward = false` |
| `UPnP` → `true` | `NatPMP = false`；`simple` 时额外 `AutoOptionsFirewall = false`、`DisablePortForward = false` |
| `NatPMP` → `true` | `UPnP = false`；`simple` 时额外 `AutoOptionsFirewall = false`、`DisablePortForward = false` |
| `DisablePortForward` → `true`（仅 `simple`） | `UPnP = false`、`NatPMP = false`、`AutoOptionsFirewall = false` |

---

## 17. `tunnelDefaults(type, mode?)` 逐字默认值

```ts
const webhookDefaults = {
  WebhookEnable: false, WebhookOnlyAddrChange: true, WebhookURL: '', WebhookMethod: 'post',
  WebhookHeaders: [], WebhookRequestBody: '', WebhookDisableCallbackSuccessContentCheck: true,
  WebhookSuccessContent: [], WebhookProxy: '', WebhookProxyAddr: '', WebhookProxyUser: '',
  WebhookProxyPassword: '', RetryCount: 0, RetryInterval: 500,
};

// type === 'stun-settings'
{ EnableModule: true, GlobalStunServerList: [], ...webhookDefaults }

// type === 'stun'
{
  Key: '', Name: '', Enable: true, StunType: 'tcp4', DiaglogShowMode: 'simple', StunListenType: 'ip',
  ListenIP: '', ListenPort: 0, SpecifyNetworkInterface: '', NetworkInterfaceReg: '',
  UseGlobalStunServerList: true, StunServerList: ['stun.miwifi.com:3478'], TcpKeepAliveServerList: [],
  DisablePortForward: false, TargetAddressList: ['127.0.0.1'], TargetPort: 80,
  AutoOptionsFirewall: true, NatPMP: false, NatPMPGateway: '', UPnP: false, UPnPGawayIP: '',
  UPnPLocalPort: 0, UPnpLocalHost: '', UpnPDiyControlAPIUrl: '',
  StunHeartbeatInterval: 2300, StunTimeout: 3000, StunRetryInterval: 3000, StunAutoRetry: true,
  DisableStunAvalidCheck: false, AutoAddPubAddrWhiteList: false, LogLevel: 4,
  LogOutputToConsole: false, AccessLogMaxNum: 128, WebListShowLastLogMaxCount: 20,
  GlobalWebhook: false, CallScript: false, CallScriptContent: '', ...webhookDefaults,
  Options: {
    DisableSelfForwardingCheck: false, SingleProxyMaxTCPConnections: 256,
    SingleProxyMaxUDPReadTargetDatagoroutineCount: 32, UDPShortMode: false, SafeMode: 'blacklist',
    TCPListenTLS: false, TCPRelayTLS: false, TCPRelayTLSServerName: '',
    TCPRelayTLSInsecureSkipVerify: false, TCPStreamEncryptionSource: false,
    TCPStreamEncryptionAccept: false, TCPStreamEncryptionKey: '', SinglePortSpeedLimit: false,
    SinglePortSendSpeedLimit: 0, SinglePortReceSpeedLimit: 0, RuleSpeedLimit: false,
    RuleSendSpeedLimit: 0, RuleReceSpeedLimit: 0, UDPSessionTimeout: 30000,
    UDPPacketSourceEncryption: false, UDPPacketAcceptEncryption: false,
    UDPPacketEncryptionKey: '', UDPPacketSize: 1500,
  },
}
```

> `Options.RuleSpeedLimit` / `RuleSendSpeedLimit` / `RuleReceSpeedLimit` 无对应表单字段（仅随默认值提交）。

```ts
// type === 'cloudflared'（mode 缺省为 'tunnel'）
{ Key: '', Remark: '', Enable: true, Type: mode ?? 'tunnel', Params: mode === 'access'
  ? { Hostname: '', URL: '', HeaderList: '', Destination: '', TokenId: '', TokenSecret: '',
      ConnectTo: '', UserAgent: '', NoTlsVerify: false }
  : { Token: '', EdgeIpVersion: 'auto', HaConnections: 4, Protocol: 'http2', EdgeBindAddress: '',
      ICMPV4Src: '', ICMPV6Src: '', NoTlsVerify: false, Network: 'tcp4', ListenIP: '127.0.0.1',
      ListenPort: 60000, CFApiToken: '', CFAccountId: '', CFTunnelId: '' } }

// type === 'frp'（mode 缺省为 'client'）
{ Key: '', Remark: '', Enable: true, Type: mode ?? 'client', Proxies: [], Visitors: [],
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
      Start: [], Metadatas: {}, AdminPort: 0, AdminUser: 'admin', OIDCClientID: '',
      OIDCClientSecret: '', OIDCAudience: '', OIDCScope: '', OIDCTokenEndpointURL: '' } }

// type === 'ingress'
{ hostname: '', path: '', service: 'http://127.0.0.1:80',
  originRequest: { noTLSVerify: false, originServerName: '', httpHostHeader: '', http2Origin: false } }

// type === 'proxies'
{ name: '', type: 'tcp', disabled: false, localIP: '127.0.0.1', localPort: 80, remotePort: 8080,
  useEncryption: false, useCompression: false, proxyProtocolVersion: '', plugin: '',
  natTraversal: { disableAssistedAddrs: false } }

// type === 'visitors'（函数末尾的兜底分支）
{ name: '', type: 'stcp', disabled: false, serverName: '', secretKey: '', bindAddr: '127.0.0.1',
  bindPort: 8080, serverUser: '', transport: { useEncryption: false, useCompression: false },
  protocol: 'quic', keepTunnelOpen: false, maxRetriesAnHour: 8, minRetryInterval: 90,
  fallbackTo: '', fallbackTimeoutMs: 0 }
```

注意：`tunnelDefaults` 的第二参数 `mode` 只有 `updateTunnelFormValue`（切换 `Type` 时）会传；屏幕调用 `tunnelDefaults(kind)` 时不传，因此新建 cloudflared 默认 `Type: 'tunnel'`、新建 frp 默认 `Type: 'client'`，并以对应分支的 `Params` 为初值。

---

## 18. 数值常量总表

| 常量 | 值 | 位置 |
| --- | --- | --- |
| 列表轮询间隔 | `5000` ms | 列表查询 `refetchInterval` |
| 详情轮询间隔 | `5000` ms | 日志（`page <= 1`）与 `status` |
| 全局 `staleTime` | `30_000` ms | query-client |
| 全局 `gcTime` | `120_000` ms | query-client |
| 全局 `retry` | `1` | query-client |
| 请求超时 | `12000` ms | luckyFetch |
| 日志页大小 | `100` | `pageSize=100`；也是「下一页」可用性判据（`logLines.length < 100` 时禁用） |
| 日志起始页 | 规则级 `0`（实时）/ 模块级 `1` | `openDetail` |
| NAT 检测超时 | `60000` ms | NatDetector |
| NAT 日志缓冲 | 最近 `200` 行 | `slice(-200)` |
| `StructuredDataView` 截断 | `200` 字段 / `200` 项 | structured-form |
| 列表首屏渲染数 | `8`（`initialNumToRender`） | FlatList |
| 列表窗口 | `7`（`windowSize`） | FlatList |
| 内容最大宽度 | `820` | Page / ScreenModal |
| 卡片圆角 | `18` | Panel / ErrorState |
| 控件圆角 | `12` | Action / 输入框 / 关闭按钮 |
| 选项芯片圆角 | `10` | FormField options |
| 搜索框圆角 / 高度 | `14` / `46` | SearchField |
| `Action` 尺寸 | `flexBasis 105`、`minHeight 42`、`gap 6`、图标 16、文字 12/600 | Action |
| 行内动作间距 | `7`（行内）/ `8`（头部与详情） | 列表行 / 表头 |
| 列表项间距 | `12`，底部留白 `24` | FlatList |
| 表单字段间距 | `15` | TunnelForm |
| 输入框最小高度 | `46`（单行）/ `112`（`lines`、`multiline`） | FormField |
| 保存按钮高度 | `48` | EditorModal footer |
| 端口范围 | `0`（可选）或 `1`（必填）～ `65535` | `port()` |

---

## 19. 中文 UI 文案索引（逐字，按出现位置）

**路由 / 表头**：`内网穿透`（导航标题与非法 kind 页标题）、`返回`（返回键）、`不支持的穿透模块`、`STUN 内网穿透`、`Cloudflared`、`FRP 内网穿透`、`刷新`（PageHeader 无障碍标签）、`STUN 模块未启用`、`搜索名称、类型或公网地址`。

**头部动作**：`新增`、`全局设置`、`NAT 检测`、`模块日志`。

**空态 / 提示**：`暂无规则`、`没有匹配的规则`、`暂无日志`、`暂无数据`、`暂无项目`、`操作已完成`、`配置已保存`、`列表中缺少规则标识，无法排序`、`读取配置失败`、`操作类型无效`、`STUN 不支持此操作`、`重试`。

**列表行**：`未命名`、`运行中`、`未运行`、`已启用`、`已停用`、`自动监听`、`自动`、`服务端`、`客户端`、`Cloudflare Tunnel`、`公网地址：`、`等待穿透`、`启用 {名称}`（开关无障碍标签）。

**行动作**：`编辑`、`日志`、`域名路由`、`运行详情`、`代理规则`、`访问者`、`复制地址`、`上移`、`下移`、`删除`。

**确认弹窗**：`此操作将修改服务器配置。`、`取消`、`确认`、`删除 {名称}？`、`删除此规则？`、`创建 {域名} 的 CNAME？`、`删除 {域名} 的 CNAME？`。

**详情模态**：`日志`、`运行详情`、`域名路由`、`代理规则`、`访问者`、`刷新`、`新增规则`、`最新日志`、`上一页`、`下一页`、`历史日志`、`实时`、`默认路由`、`域名代理`、`启用`、`停用`、`检测 DNS`、`创建 DNS`、`删除 DNS`、`关闭`、`第 N 项`、`仅显示前 200 个字段，共 N 个`、`仅显示前 200 项，共 N 项`、`是` / `否` / `--`。

**编辑器**：`新增{模块名}`、`编辑 {名称}`、`STUN 全局设置`、`新增{子集合名}`、`编辑规则`、`保存`、`保存中`、`创建并启用`、`测试 Webhook`、`请先填写 Webhook 地址`、`Webhook 请求成功`、`定制模式参数`、`高级设置`、`其他参数`、`收起其他参数`、`添加字段`、`字段名称`、`该字段已存在`、`文本` / `数字` / `开关` / `对象` / `列表`、`文本项` / `数字项` / `开关项` / `对象项` / `列表项`、`添加`、`取消`、`显示密钥` / `隐藏密钥`、`删除列表项`。

**NAT 检测**：`NAT 类型检测`、`STUN 服务器`、`开始检测`、`停止检测`、`请填写 STUN 服务器`、`检测连接失败，请检查服务端连接`、`检测超时`、`无法启动检测`。

**服务层错误**：`服务端未返回完整配置，请刷新后重试`、`服务端未返回列表数据`、`规则标识缺失，请刷新列表`、`当前 Lucky 服务端未提供 {模块名} 模块，请确认服务端版本和模块支持情况`。

**校验错误**：`请填写{字段标签}`、`{字段标签}范围无效（{min}～{max}）` / `（{min} 起）`、`请填写 Webhook 地址和请求方法`、`NAT-PMP 和 UPnP 只能启用一项`。

**传输层错误**：`请输入 Lucky 服务地址`、`请求超时，请检查服务器连接`、`请求已取消`、`请求失败（HTTP {status}）`、`登录已失效，请重新登录`。

字段标签全量清单见 §14 各表「标签」列（含 `启用 Webhook`、`仅地址变更时通知`、`Webhook 地址`、`请求方法`、`请求头`、`请求内容`、`重试次数`、`重试间隔（毫秒）`、`跳过响应内容检查`、`成功响应关键字`、`代理类型`、`代理地址`、`代理账号`、`代理密码` 等）。
