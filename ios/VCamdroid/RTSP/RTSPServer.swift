import Foundation
import Network
import CoreMedia

class RTSPServer {
    private var listener: NWListener?
    private var clients: [RTSPClient] = []
    private let port: UInt16 = 8554
    private let rtpPort: UInt16 = 20000

    private let packetizer = RTPPacketizer()
    private var rtpConnection: NWConnection?

    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?

    private var currentCSeq = 0
    private var clientIP = ""

    func start() {
        guard listener == nil else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleClient(connection)
            }
            listener?.start(queue: .global(qos: .default))
            Logger.log("RTSP server listening on port \(port)")
        } catch {
            Logger.log("RTSP server failed: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        clients.forEach { $0.connection.cancel() }
        clients.removeAll()
        rtpConnection?.cancel()
        rtpConnection = nil
    }

    func sendH264Packet(_ nalUnit: Data, timestamp: CMTime, isKeyframe: Bool) {
        guard let rtp = rtpConnection else { return }

        let packets = packetizer.packetize(nalUnit: nalUnit, timestamp: timestamp)
        for packet in packets {
            rtp.send(content: packet, completion: .idempotent)
        }
    }

    private func handleClient(_ connection: NWConnection) {
        let client = RTSPClient(connection: connection)
        clients.append(client)
        clientIP = connection.endpoint.debugDescription

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Logger.log("RTSP client connected")
                self?.onClientConnected?()
                self?.setupRTP()
            case .failed, .cancelled:
                Logger.log("RTSP client disconnected")
                self?.clients.removeAll { $0.connection === connection }
                self?.onClientDisconnected?()
            default: break
            }
        }

        receiveRequests(client)
        connection.start(queue: .global(qos: .default))
    }

    private func setupRTP() {
        let host = NWEndpoint.Host(clientIP.components(separatedBy: ":").first ?? "0.0.0.0")
        rtpConnection = NWConnection(host: host, port: NWEndpoint.Port(rawValue: rtpPort)!,
                                      using: .udp)
        rtpConnection?.start(queue: .global(qos: .default))
    }

    private func receiveRequests(_ client: RTSPClient) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, !isComplete else {
                client.connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            self.handleRequest(request, on: client.connection)
            self.receiveRequests(client)
        }
    }

    private func handleRequest(_ request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let method = parts[0]
        let cseq = lines.first { $0.hasPrefix("CSeq:") }?.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "1"

        var response = ""

        switch method {
        case "OPTIONS":
            response = """
RTSP/1.0 200 OK\r
CSeq: \(cseq)\r
Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN\r
\r
"""
        case "DESCRIBE":
            let sdp = SDPGenerator.generate(ip: clientIP, port: Int(rtpPort), trackId: 0)
            response = """
RTSP/1.0 200 OK\r
CSeq: \(cseq)\r
Content-Type: application/sdp\r
Content-Length: \(sdp.utf8.count)\r
\r
\(sdp)
"""
        case "SETUP":
            response = """
RTSP/1.0 200 OK\r
CSeq: \(cseq)\r
Transport: RTP/AVP;unicast;client_port=\(rtpPort)-\(rtpPort+1);server_port=\(rtpPort)-\(rtpPort+1);ssrc=\(String(format:"%08X", packetizer.ssrc))\r
Session: 12345\r
\r
"""
        case "PLAY":
            response = """
RTSP/1.0 200 OK\r
CSeq: \(cseq)\r
Session: 12345\r
Range: npt=0.000-\r
RTP-Info: url=rtsp://\(clientIP):\(port)/live/trackID=0;seq=0;rtptime=0\r
\r
"""
        case "TEARDOWN":
            response = """
RTSP/1.0 200 OK\r
CSeq: \(cseq)\r
Session: 12345\r
\r
"""
        default:
            response = """
RTSP/1.0 405 Method Not Allowed\r
CSeq: \(cseq)\r
\r
"""
        }

        connection.send(content: response.data(using: .utf8), completion: .idempotent)
    }
}

private struct RTSPClient {
    let connection: NWConnection
}
