import Foundation
import Compression

/// 真实的 zip 压缩 / 解压（仅用系统 API）。
/// 自研最小 ZIP 读写 + Compression 框架的原始 DEFLATE（RFC1951）编解码。
/// 生成的归档可被标准 unzip 解开，本解析器亦可解开标准 zip（存储/DEFLATE）。
enum ArchiveStore {

    enum ArchiveError: LocalizedError {
        case badZip(String)
        case inflateFailed(name: String)
        case writeFailed(name: String, underlying: String)

        var errorDescription: String? {
            switch self {
            case .badZip(let why): return "无效的 zip：\(why)"
            case .inflateFailed(let name): return "解压条目失败：\(name)"
            case .writeFailed(let name, let underlying): return "写入失败 \(name)：\(underlying)"
            }
        }
    }

    // MARK: - 压缩
    static func zip(item: URL, to dest: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: item.path, isDirectory: &isDir)

        // 收集 (归档内路径, 文件 URL)
        var entries: [(name: String, url: URL)] = []
        if isDir.boolValue {
            let base = item.deletingLastPathComponent().path + "/"
            if let walker = fm.enumerator(at: item, includingPropertiesForKeys: [.isDirectoryKey]) {
                for case let url as URL in walker {
                    let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if dir { continue }
                    entries.append((String(url.path.dropFirst(base.count)), url))
                }
            }
        } else {
            entries.append((item.lastPathComponent, item))
        }

        var output: [UInt8] = []
        var central: [UInt8] = []

        for entry in entries {
            let data = [UInt8]((try? Data(contentsOf: entry.url)) ?? Data())
            let crc = crc32(data)
            let nameBytes = [UInt8](entry.name.utf8)

            var method = 8
            var payload = deflate(data) ?? []
            if (payload.isEmpty && !data.isEmpty) || payload.count >= data.count {
                method = 0
                payload = data
            }

            let localOffset = output.count
            // 本地文件头
            append32(&output, 0x04034b50)
            append16(&output, 20); append16(&output, 0); append16(&output, method)
            append16(&output, 0); append16(&output, 0)
            append32(&output, Int(crc))
            append32(&output, payload.count)
            append32(&output, data.count)
            append16(&output, nameBytes.count); append16(&output, 0)
            output.append(contentsOf: nameBytes)
            output.append(contentsOf: payload)

            // 中央目录记录
            append32(&central, 0x02014b50)
            append16(&central, 20); append16(&central, 20); append16(&central, 0); append16(&central, method)
            append16(&central, 0); append16(&central, 0)
            append32(&central, Int(crc))
            append32(&central, payload.count)
            append32(&central, data.count)
            append16(&central, nameBytes.count); append16(&central, 0); append16(&central, 0)
            append16(&central, 0); append16(&central, 0); append32(&central, 0)
            append32(&central, localOffset)
            central.append(contentsOf: nameBytes)
        }

        let cdOffset = output.count
        output.append(contentsOf: central)
        // 结束记录 EOCD
        append32(&output, 0x06054b50)
        append16(&output, 0); append16(&output, 0)
        append16(&output, entries.count); append16(&output, entries.count)
        append32(&output, central.count)
        append32(&output, cdOffset)
        append16(&output, 0)

        do {
            try Data(output).write(to: dest, options: .atomic)
        } catch {
            throw ArchiveError.writeFailed(name: dest.lastPathComponent, underlying: error.localizedDescription)
        }
    }

    // MARK: - 解压
    static func unzip(_ zipURL: URL, to destDir: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: zipURL))
        guard let eocd = findEOCD(bytes) else { throw ArchiveError.badZip("未找到结束记录") }

        let count = u16(bytes, eocd + 10)
        var p = u32(bytes, eocd + 16)   // 中央目录偏移

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x02014b50 else {
                throw ArchiveError.badZip("中央目录损坏")
            }
            let method = u16(bytes, p + 10)
            let compSize = u32(bytes, p + 20)
            let uncompSize = u32(bytes, p + 24)
            let nameLen = u16(bytes, p + 28)
            let extraLen = u16(bytes, p + 30)
            let commentLen = u16(bytes, p + 32)
            let localOff = u32(bytes, p + 42)
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen

            guard localOff + 30 <= bytes.count, u32(bytes, localOff) == 0x04034b50 else {
                throw ArchiveError.badZip("本地文件头损坏")
            }
            let lNameLen = u16(bytes, localOff + 26)
            let lExtraLen = u16(bytes, localOff + 28)
            let dataStart = localOff + 30 + lNameLen + lExtraLen

            let outURL = destDir.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)

            let comp = Array(bytes[dataStart..<(dataStart + compSize)])
            let result: Data
            switch method {
            case 0:
                result = Data(comp)
            case 8:
                guard let inflated = inflate(comp, expected: uncompSize) else {
                    throw ArchiveError.inflateFailed(name: name)
                }
                result = inflated
            default:
                throw ArchiveError.badZip("不支持的压缩方式 \(method)")
            }
            do {
                try result.write(to: outURL, options: .atomic)
            } catch {
                throw ArchiveError.writeFailed(name: name, underlying: error.localizedDescription)
            }
        }
    }

    // MARK: - 字节工具
    private static func append16(_ a: inout [UInt8], _ v: Int) {
        a.append(UInt8(v & 0xFF)); a.append(UInt8((v >> 8) & 0xFF))
    }
    private static func append32(_ a: inout [UInt8], _ v: Int) {
        a.append(UInt8(v & 0xFF)); a.append(UInt8((v >> 8) & 0xFF))
        a.append(UInt8((v >> 16) & 0xFF)); a.append(UInt8((v >> 24) & 0xFF))
    }
    private static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | (Int(b[o + 1]) << 8) }
    private static func u32(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) | (Int(b[o + 1]) << 8) | (Int(b[o + 2]) << 16) | (Int(b[o + 3]) << 24)
    }

    private static func findEOCD(_ b: [UInt8]) -> Int? {
        guard b.count >= 22 else { return nil }
        var i = b.count - 22
        let lower = max(0, b.count - 22 - 65_536)
        while i >= lower {
            if b[i] == 0x50, b[i + 1] == 0x4b, b[i + 2] == 0x05, b[i + 3] == 0x06 { return i }
            i -= 1
        }
        return nil
    }

    // MARK: - CRC32 / DEFLATE
    private static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    private static func crc32(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func deflate(_ input: [UInt8]) -> [UInt8]? {
        if input.isEmpty { return [] }
        let cap = input.count + 64
        var dst = [UInt8](repeating: 0, count: cap)
        let n = input.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { d in
                compression_encode_buffer(d.baseAddress!, cap, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 ? Array(dst[0..<n]) : nil
    }

    private static func inflate(_ input: [UInt8], expected: Int) -> Data? {
        if expected == 0 { return Data() }
        var dst = [UInt8](repeating: 0, count: expected)
        let written = input.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, expected, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written > 0 ? Data(dst[0..<written]) : nil
    }
}
