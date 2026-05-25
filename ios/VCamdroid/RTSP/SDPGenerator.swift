import Foundation

struct SDPGenerator {
    static func generate(ip: String, port: Int, trackId: Int) -> String {
        return """
v=0
o=- 0 0 IN IP4 \(ip)
s=VCamdroid Live
c=IN IP4 \(ip)
t=0 0
m=video \(port) RTP/AVP 96
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1; profile-level-id=64001E; sprop-parameter-sets=Z2QAHqw2FAFugICAgA==,aOpx8gA=
a=control:trackID=\(trackId)
"""
    }
}
