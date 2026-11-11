import SwiftUI
import Foundation
import Network

// MARK: - DLNA 设备

struct DlnaDevice: Identifiable, Hashable {
    let id: String          // 设备描述地址
    let name: String
    let location: URL
    let controlURL: URL?
}

// MARK: - DLNA 投屏（SSDP 发现 + AVTransport 控制）

final class DlnaCaster: ObservableObject {
    @Published var devices: [DlnaDevice] = []
    @Published var discovering = false
    @Published var status: String = ""

    private var conn: NWConnection?
    private var seen = Set<String>()
    private var stopWork: DispatchWorkItem?

    func discover() {
        devices = []
        seen = []
        status = "正在搜索局域网内可投屏设备…"
        discovering = true

        let host = NWEndpoint.Host("239.255.255.250")
        let port = NWEndpoint.Port(integerLiteral: 1900)
        let c = NWConnection(host: host, port: port, using: .udp)
        conn = c

        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                let mediaRenderer = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
                let discoverAll = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n"
                for msg in [mediaRenderer, discoverAll] {
                    c.send(content: msg.data(using: .utf8), completion: .contentProcessed { _ in })
                }
                self.receiveLoop(c)
            }
        }
        c.start(queue: .global(qos: .userInitiated))

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.conn?.cancel()
            self.conn = nil
            DispatchQueue.main.async {
                self.discovering = false
                self.status = self.devices.isEmpty ? "没有找到可投屏设备（电视需与手机在同一局域网，并开启投屏/媒体接收）" : "找到 \(self.devices.count) 台设备"
            }
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func receiveLoop(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, let text = String(data: data, encoding: .utf8) {
                self.handleSsdp(text)
            }
            if error == nil && !isComplete {
                self.receiveLoop(c)
            }
        }
    }

    private func handleSsdp(_ text: String) {
        guard let locLine = text.components(separatedBy: "\r\n")
            .first(where: { $0.uppercased().hasPrefix("LOCATION:") }) else { return }
        let location = locLine.replacingOccurrences(of: "LOCATION:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: location), seen.insert(location).inserted else { return }

        loadDescription(url)
    }

    private func loadDescription(_ location: URL) {
        var req = URLRequest(url: location)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data, let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
            let name = self.extract("friendlyName", from: xml) ?? location.host ?? "投屏设备"
            let control = self.findAvTransportControlURL(xml: xml, location: location)
            let device = DlnaDevice(id: location.absoluteString, name: name, location: location, controlURL: control)
            DispatchQueue.main.async {
                if !self.devices.contains(where: { $0.id == device.id }) {
                    self.devices.append(device)
                    self.status = "找到 \(self.devices.count) 台设备"
                }
            }
        }.resume()
    }

    private func extract(_ tag: String, from xml: String) -> String? {
        guard let s = xml.range(of: "<\(tag)>"),
              let e = xml.range(of: "</\(tag)>", range: s.upperBound..<xml.endIndex) else { return nil }
        return String(xml[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findAvTransportControlURL(xml: String, location: URL) -> URL? {
        for block in xml.components(separatedBy: "<service") {
            guard block.contains("urn:schemas-upnp-org:service:AVTransport:1"),
                  let cu = extract("controlURL", from: block) else { continue }
            if let abs = URL(string: cu), abs.scheme != nil { return abs }
            var comps = URLComponents(url: location, resolvingAgainstBaseURL: false)
            comps?.path = cu.hasPrefix("/") ? cu : "/" + cu
            comps?.query = nil
            return comps?.url
        }
        return nil
    }

    /// 投屏：设置播放地址并开始播放
    func cast(device: DlnaDevice, videoUrl: URL, completion: @escaping (Bool, String) -> Void) {
        guard let control = device.controlURL else {
            completion(false, "该设备不支持标准投屏控制")
            return
        }
        guard let scheme = device.location.scheme, let host = device.location.host else {
            completion(false, "设备地址无效")
            return
        }
        var base = "\(scheme)://\(host)"
        if let port = device.location.port { base += ":\(port)" }
        guard let target = URL(string: base + control.path) ?? device.controlURL else {
            completion(false, "控制地址无效")
            return
        }

        let escaped = xmlEscape(videoUrl.absoluteString)
        let setUriBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID><CurrentURI>\(escaped)</CurrentURI><CurrentURIMetaData></CurrentURIMetaData></u:SetAVTransportURI></s:Body></s:Envelope>
        """
        let playBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID><Speed>1</Speed></u:Play></s:Body></s:Envelope>
        """

        status = "正在投屏到 \(device.name)…"
        soap(target: target, action: "SetAVTransportURI", body: setUriBody) { [weak self] ok, msg in
            guard ok else { completion(false, msg); return }
            self?.soap(target: target, action: "Play", body: playBody) { ok2, msg2 in
                DispatchQueue.main.async { self?.status = ok2 ? "已投屏到 \(device.name)" : msg2 }
                completion(ok2, msg2)
            }
        }
    }

    private func soap(target: URL, action: String, body: String,
                      completion: @escaping (Bool, String) -> Void) {
        var req = URLRequest(url: target)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err {
                completion(false, "投屏请求失败：\(err.localizedDescription)")
                return
            }
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
                completion(false, "设备拒绝（HTTP \(h.statusCode)）")
                return
            }
            completion(true, "ok")
        }.resume()
    }

    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - 投屏选择界面

struct CastSheet: View {
    let url: URL
    let title: String
    var onCasted: (() -> Void)? = nil

    @StateObject private var caster = DlnaCaster()
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.11).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("把「\(title)」投到电视")
                        .font(.subheadline).foregroundColor(.gray)
                        .padding(.top, 8)

                    if caster.devices.isEmpty {
                        VStack(spacing: 10) {
                            if caster.discovering { ProgressView().tint(.white) }
                            Text(caster.status).font(.footnote).foregroundColor(.gray)
                                .multilineTextAlignment(.center).padding(.horizontal, 24)
                        }
                        .padding(.top, 30)
                    } else {
                        List(caster.devices) { d in
                            Button {
                                caster.cast(device: d, videoUrl: url) { ok, msg in
                                    message = ok ? "投屏成功，电视已开始播放" : "投屏失败：\(msg)"
                                    if ok { DispatchQueue.main.async { onCasted?() } }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "tv").foregroundColor(.orange)
                                    Text(d.name).foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(.gray)
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                        .listStyle(.plain)
                    }

                    Button {
                        caster.discover()
                    } label: {
                        Text(caster.discovering ? "搜索中…" : "重新搜索设备")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.orange).foregroundColor(.white).cornerRadius(10)
                    }
                    .padding(.horizontal, 20)
                    .disabled(caster.discovering)

                    if let message {
                        Text(message).font(.footnote)
                            .foregroundColor(message.contains("成功") ? .green : .red)
                            .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("投屏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
        .onAppear { caster.discover() }
    }
}
