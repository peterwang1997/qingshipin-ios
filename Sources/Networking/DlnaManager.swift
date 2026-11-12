import Foundation
import Darwin

/// 一个 DLNA 投屏接收端设备（DMR）
struct DlnaDevice: Identifiable, Equatable {
    var id: String { udn }
    let udn: String
    let friendlyName: String
    let controlURL: String
    let serviceType: String

    var displayName: String { friendlyName.isEmpty ? udn : friendlyName }
}

/// 精简 DLNA / UPnP 控制点（DMC）：SSDP 搜索 → 解析描述 → AVTransport SOAP 控制
/// 与安卓 DlnaManager 行为一致，但用 POSIX socket 实现组播收发。
final class DlnaManager {
    static let shared = DlnaManager()
    private init() {}

    private let ssdpAddress = "239.255.255.250"
    private let ssdpPort: UInt16 = 1900
    private let avtService = "urn:schemas-upnp-org:service:AVTransport:1"
    private let soapNS = "http://schemas.xmlsoap.org/soap/envelope/"

    private let http: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        return URLSession(configuration: cfg)
    }()

    // MARK: - 发现

    /// SSDP 多播搜索 MediaRenderer；超时内收集设备
    func discover(timeout: TimeInterval = 5) async -> [DlnaDevice] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let devices = self.performDiscover(timeout: timeout)
                continuation.resume(returning: devices)
            }
        }
    }

    private func performDiscover(timeout: TimeInterval) -> [DlnaDevice] {
        var results: [String: DlnaDevice] = [:]
        var order: [String] = []

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return [] }

        // 组播 TTL
        var ttl: UInt8 = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        let search = "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: \(ssdpAddress):\(ssdpPort)\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 3\r\n" +
            "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
        let searchData = Array(search.utf8)

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = ssdpPort.bigEndian
        dest.sin_addr.s_addr = inet_addr(ssdpAddress)
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        _ = withUnsafePointer(to: &dest) { ptr -> Int in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(fd, searchData, searchData.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // 非阻塞 + 轮询读取
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 65536)
        let syncQueue = DispatchQueue(label: "dlna.ssdp.collect")
        var pending: [(String, String)] = []

        while Date() < deadline {
            var from = sockaddr()
            var fromLen = socklen_t(MemoryLayout<sockaddr>.size)
            let n = recvfrom(fd, &buffer, buffer.count, 0, &from, &fromLen)
            if n > 0 {
                let text = String(decoding: buffer[0..<n], as: UTF8.self)
                if let info = parseSsdpResponse(text) {
                    syncQueue.sync {
                        if results[info.0] == nil {
                            pending.append(info)
                        }
                    }
                }
            } else {
                usleep(120_000)
            }
        }

        // 逐个解析设备描述（并发不安全，顺序执行即可）
        for (udn, location) in pending {
            if results[udn] != nil { continue }
            if let dev = resolveDevice(location: location, udn: udn) {
                results[dev.udn] = dev
                order.append(dev.udn)
            }
        }
        return order.compactMap { results[$0] }
    }

    private func parseSsdpResponse(_ text: String) -> (String, String)? {
        let upper = text.uppercased()
        guard upper.hasPrefix("HTTP/1.1") || upper.hasPrefix("NOTIFY") else { return nil }
        var headers: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n") {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<idx].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { headers[key] = value }
        }
        guard let location = headers["location"], !location.isEmpty else { return nil }
        let st = headers["st"] ?? headers["nt"] ?? ""
        if !st.isEmpty && !st.contains("MediaRenderer") && !st.contains("ssdp:all") { return nil }
        let usn = headers["usn"] ?? "usn-\(abs(location.hashValue))"
        let udn = usn.components(separatedBy: "::").first ?? usn
        return (udn, location)
    }

    private func resolveDevice(location: String, udn: String) -> DlnaDevice? {
        guard let url = URL(string: location) else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: DlnaDevice?
        let task = http.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)) { data, _, _ in
            defer { sem.signal() }
            guard let data = data, let xml = String(data: data, encoding: .utf8) else { return }
            let base = Self.baseOf(location)
            let parsed = Self.parseDeviceDescription(xml: xml, base: base)
            guard !parsed.controlURL.isEmpty else { return }
            result = DlnaDevice(udn: udn,
                                friendlyName: parsed.friendlyName,
                                controlURL: parsed.controlURL,
                                serviceType: parsed.serviceType)
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 10)
        return result
    }

    static func baseOf(_ location: String) -> String {
        guard let url = URLComponents(string: location),
              let scheme = url.scheme, let host = url.host else {
            return location.components(separatedBy: "/").first.map { $0 + "/" } ?? location
        }
        let port = url.port ?? 80
        return "\(scheme)://\(host):\(port)/"
    }

    /// 用 XMLParser 抓 friendlyName / AVTransport 的 controlURL
    private static func parseDeviceDescription(xml: String, base: String) -> (friendlyName: String, controlURL: String, serviceType: String) {
        let delegate = DescriptionDelegate()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.parse()
        let control = delegate.controlURL.isEmpty ? "" : absURL(base: base, url: delegate.controlURL)
        return (delegate.friendlyName, control, delegate.serviceType)
    }

    private static func absURL(base: String, url: String) -> String {
        if url.hasPrefix("http://") || url.hasPrefix("https://") { return url }
        let b = base.hasSuffix("/") ? String(base.dropLast()) : base
        return url.hasPrefix("/") ? b + url : b + "/" + url
    }

    // MARK: - SOAP 控制

    /// 投屏播放：SetAVTransportURI + Play
    func play(device: DlnaDevice, videoURL: String, title: String?) async -> Bool {
        let metadata = buildMetadata(url: videoURL, title: title)
        let okSet = await soap(device: device, action: "SetAVTransportURI", body: setURIBody(videoURL, metadata))
        guard okSet else { return false }
        // 部分设备 Play 返回非 200 仍会开始拉流，因此不据此判定失败
        _ = await soap(device: device, action: "Play", body: playBody())
        return true
    }

    func stop(device: DlnaDevice) async -> Bool {
        await soap(device: device, action: "Stop", body: stopBody())
    }

    func pause(device: DlnaDevice) async -> Bool {
        await soap(device: device, action: "Pause", body: pauseBody())
    }

    /// 预置下一集，电视支持时无缝连播
    func setNext(device: DlnaDevice, videoURL: String, title: String?) async -> Bool {
        let metadata = buildMetadata(url: videoURL, title: title)
        return await soap(device: device, action: "SetNextAVTransportURI", body: setNextURIBody(videoURL, metadata))
    }

    /// 查询传输状态（PLAYING / STOPPED / PAUSED / TRANSITIONING…），用于投屏自动连播
    func transportState(device: DlnaDevice) async -> String? {
        let body = envelope(action: "GetTransportInfo", inner: "<InstanceID>0</InstanceID>")
        guard let url = URL(string: device.controlURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("\"\(device.serviceType.isEmpty ? avtService : device.serviceType)#GetTransportInfo\"", forHTTPHeaderField: "SOAPACTION")
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("QingShipin-DLNA/1.0", forHTTPHeaderField: "USER-AGENT")
        req.httpBody = Data(body.utf8)
        do {
            let (data, resp) = try await http.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let xml = String(data: data, encoding: .utf8) else { return nil }
            guard let regex = try? NSRegularExpression(pattern: "<CurrentTransportState>([^<]+)</CurrentTransportState>") else { return nil }
            guard let m = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
                  let r = Range(m.range(at: 1), in: xml) else { return nil }
            return String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func soap(device: DlnaDevice, action: String, body: String) async -> Bool {
        guard let url = URL(string: device.controlURL) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("\"\(device.serviceType.isEmpty ? avtService : device.serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("QingShipin-DLNA/1.0", forHTTPHeaderField: "USER-AGENT")
        req.httpBody = Data(body.utf8)
        do {
            let (_, resp) = try await http.data(for: req)
            if let http = resp as? HTTPURLResponse { return (200...299).contains(http.statusCode) }
            return false
        } catch {
            return false
        }
    }

    private func envelope(action: String, inner: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="\(soapNS)" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="\(avtService)">
              \(inner)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """
    }

    private func setURIBody(_ uri: String, _ metadata: String) -> String {
        envelope(action: "SetAVTransportURI",
                 inner: "<InstanceID>0</InstanceID><CurrentURI>\(escapeXML(uri))</CurrentURI><CurrentURIMetaData>\(metadata)</CurrentURIMetaData>")
    }

    private func setNextURIBody(_ uri: String, _ metadata: String) -> String {
        envelope(action: "SetNextAVTransportURI",
                 inner: "<InstanceID>0</InstanceID><NextURI>\(escapeXML(uri))</NextURI><NextURIMetaData>\(metadata)</NextURIMetaData>")
    }

    private func playBody() -> String {
        envelope(action: "Play", inner: "<InstanceID>0</InstanceID><Speed>1</Speed>")
    }

    private func pauseBody() -> String {
        envelope(action: "Pause", inner: "<InstanceID>0</InstanceID>")
    }

    private func stopBody() -> String {
        envelope(action: "Stop", inner: "<InstanceID>0</InstanceID>")
    }

    private func buildMetadata(url: String, title: String?) -> String {
        let t = escapeXML(title?.isEmpty == false ? title! : "轻视频")
        let escapedURL = url.replacingOccurrences(of: "&", with: "&amp;")
        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" " +
            "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" " +
            "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">" +
            "<item id=\"0\" parentID=\"-1\" restricted=\"1\">" +
            "<dc:title>\(t)</dc:title>" +
            "<upnp:class>object.item.videoItem</upnp:class>" +
            "<res protocolInfo=\"http-get:*:video/mp4:*\">\(escapedURL)</res>" +
            "</item></DIDL-Lite>"
    }

    private func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// 解析设备描述 XML
private final class DescriptionDelegate: NSObject, XMLParserDelegate {
    var friendlyName = ""
    var controlURL = ""
    var serviceType = ""
    private var inService = false
    private var currentServiceType = ""
    private var currentControlURL = ""
    private var currentText = ""
    private var capturing: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch elementName {
        case "friendlyName":
            capturing = "friendlyName"
        case "service":
            inService = true
            currentServiceType = ""
            currentControlURL = ""
        case "serviceType":
            if inService { capturing = "serviceType" }
        case "controlURL":
            if inService { capturing = "controlURL" }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "friendlyName":
            if friendlyName.isEmpty { friendlyName = text }
            capturing = nil
        case "serviceType":
            if inService { currentServiceType = text }
            capturing = nil
        case "controlURL":
            if inService { currentControlURL = text }
            capturing = nil
        case "service":
            if currentServiceType == "urn:schemas-upnp-org:service:AVTransport:1",
               !currentControlURL.isEmpty {
                controlURL = currentControlURL
                serviceType = currentServiceType
            }
            inService = false
        default:
            break
        }
        currentText = ""
    }
}
