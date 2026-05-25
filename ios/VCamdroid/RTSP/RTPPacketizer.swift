import Foundation
import CoreMedia

class RTPPacketizer {
    private let mtu = 1400
    private var sequenceNumber: UInt16 = 0
    private let ssrc: UInt32 = arc4random()
    private let payloadType: UInt8 = 96

    func packetize(nalUnit: Data, timestamp: CMTime) -> [Data] {
        let nalType = nalUnit[0] & 0x1F
        let data = nalUnit

        var packets: [Data] = []
        let ts = UInt32(CMTimeGetSeconds(timestamp) * 90000)

        if data.count <= mtu {
            var header = rtpHeader(ts: ts, marker: true)
            header.append(contentsOf: data)
            packets.append(header)
        } else {
            let fuIndicator: UInt8 = (nalUnit[0] & 0xE0) | 0x1C
            let fuHeaderBase = (nalUnit[0] & 0x1F)
            var offset = 1

            var first = true
            while offset < data.count {
                let end = min(offset + mtu - 2, data.count)
                let isLast = end >= data.count

                let fuHeader: UInt8 = fuHeaderBase | (first ? 0x80 : 0) | (isLast ? 0x40 : 0)

                var packet = rtpHeader(ts: ts, marker: isLast)
                packet.append(fuIndicator)
                packet.append(fuHeader)
                packet.append(data[offset..<end])

                packets.append(packet)
                offset = end
                first = false
            }
        }
        return packets
    }

    private func rtpHeader(ts: UInt32, marker: Bool) -> Data {
        var header = Data()
        let version: UInt8 = 2 << 6
        let pt: UInt8 = payloadType | (marker ? 0x80 : 0)
        header.append(version | 0x00)
        header.append(pt)
        header.append(contentsOf: withUnsafeBytes(of: CFSwapInt16HostToBig(sequenceNumber)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: CFSwapInt32HostToBig(ts)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: CFSwapInt32HostToBig(ssrc)) { Data($0) })
        sequenceNumber &+= 1
        return header
    }
}
