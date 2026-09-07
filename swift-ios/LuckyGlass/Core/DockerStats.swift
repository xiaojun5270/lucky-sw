import Foundation

/// The statistics reader behind the Docker dashboards, ported from the helper block at the top of
/// `src/components/docker-overview.tsx`.
///
/// Lucky forwards whatever the Docker daemon and its own cache happen to hold, so one reading
/// arrives as `CPUPerc: "3.21%"` on one build, as a `cpu_stats` / `precpu_stats` pair on another,
/// and as a bare `cpu` number on a third. Every reader therefore takes a list of spellings and
/// searches case-insensitively.
///
/// The optionals are load-bearing: "the field was absent" and "the field said zero" must stay
/// distinguishable, because the first draws `--` and the second draws `0`.
enum DockerStats {
    // MARK: - Scalars

    private static let bytePowers: [String: Int] = [
        "b": 0, "kb": 1, "kib": 1, "mb": 2, "mib": 2, "gb": 3, "gib": 3,
        "tb": 4, "tib": 4, "pb": 5, "pib": 5, "eb": 6, "eib": 6,
    ]

    /// `parseDockerBytes`. A finite number passes through; a string is matched against
    /// `/^(-?\d+(?:\.\d+)?)\s*([kmgtpe]?i?b)?/i` after trimming and dropping thousands commas.
    ///
    /// The `i` in the unit is what selects 1024 over 1000, so `"12 MB"` really does read as
    /// 12 000 000 here — that is what the original computes, and a Docker daemon that reports `MB`
    /// means the decimal unit anyway.
    static func parseBytes(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if case .number(let number) = value { return number.isFinite ? number : nil }
        guard case .string(let raw) = value else { return nil }
        let text = raw.jsTrimmed.replacingOccurrences(of: ",", with: "")

        var index = text.startIndex
        if index < text.endIndex, text[index] == "-" { index = text.index(after: index) }
        let digitsStart = index
        while index < text.endIndex, text[index].isASCII, text[index].isNumber {
            index = text.index(after: index)
        }
        // `\d+` — a string with no leading digits does not match at all.
        guard index > digitsStart else { return nil }
        if index < text.endIndex, text[index] == "." {
            var scan = text.index(after: index)
            let fractionStart = scan
            while scan < text.endIndex, text[scan].isASCII, text[scan].isNumber {
                scan = text.index(after: scan)
            }
            // `(?:\.\d+)?` needs at least one digit after the dot, else the dot is not consumed.
            if scan > fractionStart { index = scan }
        }
        guard let amount = Double(text[text.startIndex..<index]) else { return nil }

        var unitStart = index
        while unitStart < text.endIndex, text[unitStart].isWhitespace {
            unitStart = text.index(after: unitStart)
        }
        let unit = unitSuffix(text, from: unitStart)
        let base: Double = unit.contains("i") ? 1024 : 1000
        return amount * pow(base, Double(bytePowers[unit] ?? 0))
    }

    /// `([kmgtpe]?i?b)?`, lowercased. No match means the amount is already in bytes, which is what
    /// the original's `?? "b"` says.
    private static func unitSuffix(_ text: String, from start: String.Index) -> String {
        var unit = ""
        var index = start
        if index < text.endIndex {
            let lowered = text[index].lowercased()
            if lowered.count == 1, "kmgtpe".contains(lowered) {
                unit += lowered
                index = text.index(after: index)
            }
        }
        if index < text.endIndex, text[index] == "i" || text[index] == "I" {
            unit += "i"
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "b" || text[index] == "B" else { return "b" }
        return unit + "b"
    }

    /// `dockerValue` — the first of `keys` whose deep lookup yields something that is not null.
    /// Only the key advances on a miss, never the record: the first record owning the key wins even
    /// if it holds null, and then the *next key* is tried.
    static func value(_ source: JSONValue, _ keys: [String]) -> JSONValue? {
        for key in keys {
            if let found = JSONUnwrap.deepValue(source, key: key), !found.isNull { return found }
        }
        return nil
    }

    /// `dockerDirectValue` — own keys only, no descent. The source's key order decides, not the
    /// order of `keys`, so a record holding both `NetIO` and `net_io` answers with whichever it
    /// lists first.
    static func directValue(_ source: JSONValue, _ keys: [String]) -> JSONValue? {
        guard case .object(let object) = source else { return nil }
        let wanted = Set(keys.map { $0.lowercased() })
        guard let match = object.keys.first(where: { wanted.contains($0.lowercased()) }) else {
            return nil
        }
        return object[match]
    }

    /// `dockerChildRecord` — the first own key that names a record.
    static func childRecord(_ source: JSONValue, _ keys: [String]) -> JSONValue? {
        guard case .object(let object) = source else { return nil }
        let wanted = Set(keys.map { $0.lowercased() })
        for (key, value) in object.pairs where wanted.contains(key.lowercased()) && value.isRecord {
            return value
        }
        return nil
    }

    // MARK: - CPU

    /// `dockerCpuPercent`. A reported percentage wins; failing that the Docker `cpu_stats` /
    /// `precpu_stats` deltas are turned into one, and failing that a raw usage field is returned
    /// unclamped — the original only clamps the direct reading, and a negative delta there means
    /// the daemon restarted, which should look wrong rather than look like zero.
    static func cpuPercent(_ source: JSONValue) -> Double? {
        let direct = JSONUnwrap.deepNumber(source, keys: [
            "CPUPercent", "cpuPercent", "cpu_percent", "CPUPerc", "cpuPerc",
        ])
        if let direct { return max(0, direct) }

        let fallback = {
            JSONUnwrap.deepNumber(source, keys: ["CPUUsage", "cpuUsage", "cpu_usage", "CPU", "cpu"])
        }
        guard let stats = childRecord(source, ["cpu_stats", "cpuStats", "CPUStats"]),
              let previous = childRecord(source, ["precpu_stats", "preCpuStats", "PreCPUStats"]),
              let usage = childRecord(stats, ["cpu_usage", "cpuUsage", "CPUUsage"]),
              let previousUsage = childRecord(previous, ["cpu_usage", "cpuUsage", "CPUUsage"])
        else { return fallback() }

        let totalKeys = ["total_usage", "totalUsage", "TotalUsage"]
        let cpuDelta = (JSONUnwrap.deepNumber(usage, keys: totalKeys) ?? 0)
            - (JSONUnwrap.deepNumber(previousUsage, keys: totalKeys) ?? 0)
        let systemKeys = ["system_cpu_usage", "systemCpuUsage", "SystemCPUUsage"]
        let systemDelta = (JSONUnwrap.deepNumber(stats, keys: systemKeys) ?? 0)
            - (JSONUnwrap.deepNumber(previous, keys: systemKeys) ?? 0)
        guard cpuDelta > 0, systemDelta > 0 else { return fallback() }

        let perCpu = value(usage, ["percpu_usage", "perCpuUsage", "PercpuUsage"])
        let count = JSONUnwrap.deepNumber(stats, keys: ["online_cpus", "onlineCpus", "OnlineCPUs"])
            ?? Double(perCpu?.arrayValue?.count ?? 1)
        return cpuDelta / systemDelta * max(1, count) * 100
    }

    // MARK: - Memory

    struct Memory: Sendable, Hashable {
        var usage: Double?
        var limit: Double?
        var percent: Double?
    }

    /// `dockerMemoryValues`. Four shapes are accepted: separate usage and limit fields, one
    /// `"512MiB / 2GiB"` string, the raw `memory_stats` block (cache subtracted the way `docker
    /// stats` does), and a directly reported percentage.
    static func memoryValues(_ source: JSONValue) -> Memory {
        let rawUsage = value(source, [
            "MemoryUsage", "memoryUsage", "memory_usage", "MemUsage", "memUsage", "mem_usage",
            "Memory", "memory", "Mem", "mem",
        ])
        var usage = parseBytes(rawUsage)
        var limit = parseBytes(value(source, [
            "MemoryLimit", "memoryLimit", "memory_limit", "MemLimit", "memLimit", "mem_limit",
        ]))

        if let rawUsage, case .string(let text) = rawUsage, text.contains("/") {
            let parts = text.split(separator: "/", omittingEmptySubsequences: false)
            usage = parseBytes(.string(String(parts[0]))) ?? usage
            limit = parseBytes(.string(String(parts[1]))) ?? limit
        }

        let stats = childRecord(source, ["memory_stats", "memoryStats", "MemoryStats"])
        if usage == nil, let stats {
            let raw = JSONUnwrap.deepNumber(stats, keys: ["usage", "Usage"])
            let cache = childRecord(stats, ["stats", "Stats"]).flatMap {
                JSONUnwrap.deepNumber($0, keys: [
                    "total_inactive_file", "inactive_file", "cache", "Cache",
                ])
            } ?? 0
            // Cache is only subtracted when it is plausible: a cache larger than the usage means
            // the two numbers came from different places.
            if let raw { usage = cache > 0 && cache < raw ? raw - cache : raw }
        }
        if limit == nil, let stats {
            limit = JSONUnwrap.deepNumber(stats, keys: ["limit", "Limit"])
        }

        var percent = JSONUnwrap.deepNumber(source, keys: [
            "MemoryPercent", "memoryPercent", "memory_percent", "MemPercent", "memPercent",
            "MemPerc", "memPerc",
        ])
        if percent == nil, let usage, let limit, limit > 0 { percent = usage / limit * 100 }
        return Memory(
            usage: usage.map { max(0, $0) },
            limit: limit,
            percent: percent.map { max(0, $0) }
        )
    }

    // MARK: - Network and block IO

    struct IO: Sendable, Hashable {
        var networkRx: Double?
        var networkTx: Double?
        var blockRead: Double?
        var blockWrite: Double?
    }

    /// `dockerBytePair` — `"1.2kB / 3.4kB"` as `docker stats` prints it, or a two-element array.
    private static func bytePair(_ value: JSONValue?) -> (Double?, Double?) {
        guard let value else { return (nil, nil) }
        switch value {
        case .string(let text) where text.contains("/"):
            let parts = text.split(separator: "/", omittingEmptySubsequences: false)
            return (parseBytes(.string(String(parts[0]))), parseBytes(.string(String(parts[1]))))
        case .array(let items) where items.count >= 2:
            return (parseBytes(items[0]), parseBytes(items[1]))
        default:
            return (nil, nil)
        }
    }

    /// `dockerIoValues`. Reported totals win; otherwise the per-interface `networks` map and the
    /// `blkio_stats` service-bytes list are summed.
    static func ioValues(_ source: JSONValue) -> IO {
        var result = IO()
        let (combinedRx, combinedTx) = bytePair(directValue(source, [
            "NetIO", "netIO", "net_io", "NetworkIO", "networkIO", "network_io",
        ]))
        result.networkRx = parseBytes(directValue(source, [
            "NetworkRx", "NetworkRX", "networkRx", "network_rx", "network_rx_bytes",
            "NetworkInput", "networkInput", "network_input", "NetInput", "netInput", "net_input",
            "RxBytes", "rxBytes", "rx_bytes",
        ])) ?? combinedRx
        result.networkTx = parseBytes(directValue(source, [
            "NetworkTx", "NetworkTX", "networkTx", "network_tx", "network_tx_bytes",
            "NetworkOutput", "networkOutput", "network_output", "NetOutput", "netOutput",
            "net_output", "TxBytes", "txBytes", "tx_bytes",
        ])) ?? combinedTx
        sumNetworks(source, into: &result)

        let (combinedRead, combinedWrite) = bytePair(directValue(source, [
            "BlockIO", "blockIO", "blockIo", "block_io", "BlkIO", "blkIO", "DiskIO", "diskIO",
            "disk_io",
        ]))
        result.blockRead = parseBytes(directValue(source, [
            "BlockRead", "blockRead", "block_read", "block_read_bytes", "DiskRead", "diskRead",
            "disk_read", "BlockInput", "blockInput", "block_input", "IORead", "ioRead", "io_read",
            "ReadBytes", "readBytes", "read_bytes",
        ])) ?? combinedRead
        result.blockWrite = parseBytes(directValue(source, [
            "BlockWrite", "blockWrite", "block_write", "block_write_bytes", "DiskWrite",
            "diskWrite", "disk_write", "BlockOutput", "blockOutput", "block_output", "IOWrite",
            "ioWrite", "io_write", "WriteBytes", "writeBytes", "write_bytes",
        ])) ?? combinedWrite
        sumServiceBytes(source, into: &result)
        return result
    }

    /// The `networks` map, which is either `{ eth0: { rx_bytes, tx_bytes } }` or, on some builds,
    /// flattened to `{ rx_bytes, tx_bytes }`. Both are read, and the flattened pair is the starting
    /// total rather than an alternative to the per-interface sum.
    private static func sumNetworks(_ source: JSONValue, into result: inout IO) {
        guard result.networkRx == nil || result.networkTx == nil,
              let networks = childRecord(source, ["networks", "Networks", "network", "Network"])?
                  .objectValue
        else { return }

        let directRx = networks.keys
            .first { ["rx_bytes", "rxbytes"].contains($0.lowercased()) }
            .flatMap { parseBytes(networks[$0]) }
        let directTx = networks.keys
            .first { ["tx_bytes", "txbytes"].contains($0.lowercased()) }
            .flatMap { parseBytes(networks[$0]) }
        var received = directRx ?? 0
        var sent = directTx ?? 0
        var foundReceived = directRx != nil
        var foundSent = directTx != nil

        for entry in networks.values where entry.isRecord {
            if let next = JSONUnwrap.deepNumber(entry, keys: ["rx_bytes", "rxBytes", "RxBytes"]) {
                received += next
                foundReceived = true
            }
            if let next = JSONUnwrap.deepNumber(entry, keys: ["tx_bytes", "txBytes", "TxBytes"]) {
                sent += next
                foundSent = true
            }
        }
        if result.networkRx == nil, foundReceived { result.networkRx = received }
        if result.networkTx == nil, foundSent { result.networkTx = sent }
    }

    /// `blkio_stats.io_service_bytes_recursive`, preferring the recursive list when it has entries.
    /// Each entry is `{ op: "Read" | "Write", value }` and the ops are summed separately.
    private static func sumServiceBytes(_ source: JSONValue, into result: inout IO) {
        guard result.blockRead == nil || result.blockWrite == nil,
              let stats = childRecord(source, ["blkio_stats", "blkioStats", "BlkioStats"])
        else { return }

        let recursive = value(stats, [
            "io_service_bytes_recursive", "ioServiceBytesRecursive", "IoServiceBytesRecursive",
        ])?.arrayValue
        let entries = recursive?.isEmpty == false
            ? recursive
            : value(stats, ["io_service_bytes", "ioServiceBytes", "IoServiceBytes"])?.arrayValue
        guard let entries else { return }

        var read = 0.0
        var written = 0.0
        var foundRead = false
        var foundWritten = false
        for entry in entries where entry.isRecord {
            let operation = JSONUnwrap.pick(entry, ["op", "Op", "operation", "Operation"])
                .lowercased()
            guard let amount = JSONUnwrap.deepNumber(entry, keys: ["value", "Value"]) else {
                continue
            }
            if operation == "read" {
                read += amount
                foundRead = true
            }
            if operation == "write" {
                written += amount
                foundWritten = true
            }
        }
        if result.blockRead == nil, foundRead { result.blockRead = read }
        if result.blockWrite == nil, foundWritten { result.blockWrite = written }
    }

    // MARK: - Finding the stat records

    private static let statShapeExact: Set<String> = [
        "cpu", "memory", "mem", "networks", "network", "rxbytes", "txbytes", "readbytes",
        "writebytes",
    ]

    private static let statShapeFragments = [
        "cpupercent", "cpuperc", "cpuusage", "cpustats", "memoryusage", "memusage",
        "memorypercent", "memperc", "memorystats", "networkio", "netio", "networkrx", "networktx",
        "blockio", "blockread", "blockwrite", "diskread", "diskwrite", "blkiostats",
    ]

    /// `hasDockerStatShape` — does this record look like one container's statistics? Keys are
    /// lowercased and stripped to letters first, so `Mem_Usage`, `memUsage` and `MEM USAGE` all
    /// read the same.
    static func hasStatShape(_ record: JSONObject) -> Bool {
        record.keys.contains { key in
            let normalized = String(key.lowercased().filter { $0.isASCII && $0.isLetter })
            return statShapeExact.contains(normalized)
                || statShapeFragments.contains { normalized.contains($0) }
        }
    }

    /// One candidate record plus the container name or id inherited from the key that led to it.
    struct Candidate {
        var record: JSONValue
        var hint: String
    }

    private static let wrapperKeys: Set<String> = ["data", "result", "stats", "list", "containers"]

    /// `collectDockerStats` — walk the payload and collect every record that looks like statistics,
    /// carrying down the nearest container identifier as a hint. A matching record is *not*
    /// descended into, so a container's nested `cpu_stats` never becomes a row of its own.
    ///
    /// The original also keeps a `visited` set of object identities; a parsed JSON tree has no
    /// shared nodes, so the depth cap alone bounds this walk.
    static func collect(_ source: JSONValue) -> [Candidate] {
        var rows: [Candidate] = []
        visit(source, hint: "", depth: 0, into: &rows)
        return rows
    }

    private static func visit(
        _ value: JSONValue,
        hint: String,
        depth: Int,
        into rows: inout [Candidate]
    ) {
        guard depth <= 7 else { return }
        switch value {
        case .array(let items):
            for item in items { visit(item, hint: hint, depth: depth + 1, into: &rows) }
        case .object(let object):
            if hasStatShape(object) {
                rows.append(Candidate(record: value, hint: hint))
                return
            }
            let ownName = JSONUnwrap.pick(value, [
                "Name", "name", "ContainerName", "containerName",
            ])
            for (key, child) in object.pairs {
                // A record that names itself passes that name down; a plain wrapper key passes the
                // hint through unchanged; anything else becomes the hint itself.
                let nextHint = !ownName.isEmpty
                    ? ownName
                    : (wrapperKeys.contains(key.lowercased()) ? hint : key)
                visit(child, hint: nextHint, depth: depth + 1, into: &rows)
            }
        default:
            return
        }
    }

    // MARK: - Container state

    /// `cleanDockerContainerName` — `"/nginx,/nginx-1"` is one container with two names, and the
    /// leading slash is Docker's.
    static func cleanContainerName(_ value: String) -> String {
        let first = value.split(separator: ",", omittingEmptySubsequences: false).first
        var name = (first.map(String.init) ?? "").jsTrimmed
        while name.hasPrefix("/") { name.removeFirst() }
        return name
    }

    /// `dockerContainerState`. The words come first because `State` and `Status` are the fields
    /// every build reports; the `Running` flag is only consulted when neither word matched, and it
    /// is accepted as a bool, a number or a string.
    static func containerState(_ item: JSONValue) -> DockerContainerState {
        let state = [
            JSONUnwrap.pick(item, ["State", "state"]),
            JSONUnwrap.pick(item, ["Status", "status"]),
        ].joined(separator: " ").lowercased()

        if state.contains("paused") { return .paused }
        if state.contains("created") { return .created }
        if JSRegex.containsAny(state, ["exited", "stopped", "dead", "removing"]) { return .exited }

        let flag = item["Running"].flatMap { $0.isNull ? nil : $0 } ?? item["running"]
        if let flag {
            switch flag {
            case .bool(let running):
                return running ? .running : .exited
            case .number(let number) where number == 1:
                return .running
            case .number(let number) where number == 0:
                return .exited
            case .string(let text):
                switch text.jsTrimmed.lowercased() {
                case "true", "1": return .running
                case "false", "0": return .exited
                default: break
                }
            default:
                break
            }
        }

        if JSRegex.containsAny(state, ["running", "active", "restarting"]) { return .running }
        // `\bup\b`: `"Up 3 hours"` is running, `"backup failed"` is not.
        if containsWord(state, "up") { return .running }
        return .other
    }

    /// `/\bword\b/` over an already-lowercased haystack.
    private static func containsWord(_ text: String, _ word: String) -> Bool {
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: search) {
            let openStart = range.lowerBound == text.startIndex
                || !isWordCharacter(text[text.index(before: range.lowerBound)])
            let openEnd = range.upperBound == text.endIndex
                || !isWordCharacter(text[range.upperBound])
            if openStart, openEnd { return true }
            guard range.lowerBound < text.endIndex else { return false }
            search = text.index(after: range.lowerBound)..<text.endIndex
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
    }

    // MARK: - Rows

    private struct KnownContainer {
        var container: JSONValue
        var id: String
        var name: String
    }

    /// `dockerStatRows` — pair every collected record with the container it belongs to.
    ///
    /// Matching is deliberately loose because the statistics endpoint and the container list rarely
    /// agree on how much of the id they print: either side may hold the prefix, the hint may be the
    /// id or the name, and the name may still carry Docker's leading slash.
    ///
    /// Rows whose container is known to be stopped are dropped — a stopped container reports
    /// zeroes, and a screen of zeroes buries the containers that are doing something.
    static func rows(_ source: JSONValue?, containers: [JSONValue]) -> [DockerStatRow] {
        guard let source else { return [] }
        let known = containers.enumerated().map { index, container in
            KnownContainer(
                container: container,
                id: JSONUnwrap.pick(container, [
                    "Id", "ID", "id", "Container", "ContainerID", "ContainerId", "containerId",
                ], String(index)),
                name: cleanContainerName(JSONUnwrap.pick(container, [
                    "Names", "Name", "name", "ContainerName", "containerName",
                ]))
            )
        }

        // A `Map` iterates in insertion order, so the row order follows the payload.
        var order: [String] = []
        var byKey: [String: DockerStatRow] = [:]

        for (index, candidate) in collect(source).enumerated() {
            let rawId = JSONUnwrap.pick(candidate.record, [
                "Id", "ID", "id", "Container", "ContainerID", "ContainerId", "containerId",
                "container_id",
            ])
            let rawName = cleanContainerName(JSONUnwrap.pick(candidate.record, [
                "Name", "name", "ContainerName", "containerName",
            ]))
            let hint = candidate.hint
            let match = known.first { item in
                (!rawId.isEmpty && (item.id.hasPrefix(rawId) || rawId.hasPrefix(item.id)))
                    || (!hint.isEmpty && (item.id.hasPrefix(hint) || hint.hasPrefix(item.id)))
                    || (!rawName.isEmpty && item.name == rawName)
                    || (!hint.isEmpty && item.name == cleanContainerName(hint))
            }
            if let match, [.exited, .created].contains(containerState(match.container)) { continue }

            let cpu = cpuPercent(candidate.record)
            let usage = memoryValues(candidate.record)
            let traffic = ioValues(candidate.record)
            // A record can look like statistics and still carry none, usually because it is the
            // envelope around the real ones.
            if cpu == nil, usage.usage == nil, traffic.networkRx == nil, traffic.networkTx == nil,
               traffic.blockRead == nil, traffic.blockWrite == nil { continue }

            let name = [match?.name ?? "", rawName, cleanContainerName(hint), "容器 \(index + 1)"]
                .first { !$0.isEmpty } ?? ""
            let key = [match?.id ?? "", rawId, hint, "\(name)-\(index)"]
                .first { !$0.isEmpty } ?? ""
            var next = DockerStatRow(key: key, name: name)
            next.cpu = cpu ?? 0
            next.hasCpu = cpu != nil
            next.memory = usage.usage ?? 0
            next.hasMemory = usage.usage != nil
            next.memoryPercent = usage.percent ?? 0
            next.hasMemoryPercent = usage.percent != nil
            next.networkRx = traffic.networkRx ?? 0
            next.hasNetworkRx = traffic.networkRx != nil
            next.networkTx = traffic.networkTx ?? 0
            next.hasNetworkTx = traffic.networkTx != nil
            next.blockRead = traffic.blockRead ?? 0
            next.hasBlockRead = traffic.blockRead != nil
            next.blockWrite = traffic.blockWrite ?? 0
            next.hasBlockWrite = traffic.blockWrite != nil

            guard var current = byKey[key] else {
                order.append(key)
                byKey[key] = next
                continue
            }
            // Two records for one container: each field is taken from whichever record reported it,
            // the later one winning.
            current.name = current.name.isEmpty ? next.name : current.name
            current.cpu = next.hasCpu ? next.cpu : current.cpu
            current.hasCpu = current.hasCpu || next.hasCpu
            current.memory = next.hasMemory ? next.memory : current.memory
            current.hasMemory = current.hasMemory || next.hasMemory
            current.memoryPercent = next.hasMemoryPercent
                ? next.memoryPercent
                : current.memoryPercent
            current.hasMemoryPercent = current.hasMemoryPercent || next.hasMemoryPercent
            current.networkRx = next.hasNetworkRx ? next.networkRx : current.networkRx
            current.hasNetworkRx = current.hasNetworkRx || next.hasNetworkRx
            current.networkTx = next.hasNetworkTx ? next.networkTx : current.networkTx
            current.hasNetworkTx = current.hasNetworkTx || next.hasNetworkTx
            current.blockRead = next.hasBlockRead ? next.blockRead : current.blockRead
            current.hasBlockRead = current.hasBlockRead || next.hasBlockRead
            current.blockWrite = next.hasBlockWrite ? next.blockWrite : current.blockWrite
            current.hasBlockWrite = current.hasBlockWrite || next.hasBlockWrite
            byKey[key] = current
        }
        return order.compactMap { byKey[$0] }
    }
}

/// One row of `docker stats`, with a companion flag per field: a container that reports 0 B of
/// network traffic and one that never reported any are different facts, and only the second draws
/// a dash.
struct DockerStatRow: Identifiable, Hashable, Sendable {
    var key: String
    var name: String
    var cpu: Double = 0
    var hasCpu = false
    var memory: Double = 0
    var hasMemory = false
    var memoryPercent: Double = 0
    var hasMemoryPercent = false
    var networkRx: Double = 0
    var hasNetworkRx = false
    var networkTx: Double = 0
    var hasNetworkTx = false
    var blockRead: Double = 0
    var hasBlockRead = false
    var blockWrite: Double = 0
    var hasBlockWrite = false

    var id: String { key }
}

/// `DockerContainerState`. `other` is not an error state — Lucky's own container cache sometimes
/// reports a word none of the tests recognise, and that must not read as a failure.
enum DockerContainerState: String, Sendable, Hashable, CaseIterable {
    case running, paused, exited, created, other
}
