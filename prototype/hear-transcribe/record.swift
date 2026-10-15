// sf hear record — laptop side. Count-in click to the headphones, then record a take from the default mic.
//
//   swift record.swift out.wav --seconds 8 --bpm 100 --countin 4 [--no-click]
//
// Prints one JSON line: {file, seconds, sr, channels, bpm, countin_beats, grid_start_s, motif}.
// Writes <out>.motif.json beside the take: the take is a root motif (spec/motif-lifecycle.md, source: mic).
// grid_start_s is where bar 1 beat 1 falls in the file (the end of the count-in). The click keeps
// going through the take so the musician can hold tempo; wear headphones or it bleeds into the mic.
import AVFoundation
import Foundation

func arg(_ name: String, _ def: String) -> String {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return def
}
let args = CommandLine.arguments
guard args.count >= 2 else { fputs("usage: record.swift out.wav --seconds N --bpm B --countin 4\n", stderr); exit(2) }
let outPath = args[1]
let seconds = Double(arg("--seconds", "8"))!
let bpm = Double(arg("--bpm", "100"))!
let countin = Int(arg("--countin", "4"))!
let click = !args.contains("--no-click")

// microphone consent (TCC prompt lands on the terminal app the first time)
let sem = DispatchSemaphore(value: 0)
var granted = false
AVCaptureDevice.requestAccess(for: .audio) { ok in granted = ok; sem.signal() }
while sem.wait(timeout: .now()) != .success { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
guard granted else {
    print("{\"status\":\"failed\",\"reason\":\"microphone-consent\",\"hint\":\"Allow the microphone for this terminal in System Settings > Privacy & Security > Microphone.\"}")
    exit(1)
}

let engine = AVAudioEngine()
let input = engine.inputNode
let inFmt = input.outputFormat(forBus: 0)
let sr = inFmt.sampleRate
let beat = 60.0 / bpm
let gridStart = Double(countin) * beat
let total = gridStart + seconds

let settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr,
    AVNumberOfChannelsKey: inFmt.channelCount, AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
]
var file: AVAudioFile? = try AVAudioFile(forWriting: URL(fileURLWithPath: outPath), settings: settings,
                           commonFormat: inFmt.commonFormat, interleaved: inFmt.isInterleaved)

// click track: one buffer covering count-in + take, played once from engine start
let player = AVAudioPlayerNode()
let outFmt = engine.outputNode.outputFormat(forBus: 0)
let clickFmt = AVAudioFormat(standardFormatWithSampleRate: outFmt.sampleRate, channels: 1)!
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: clickFmt)
let frames = AVAudioFrameCount(total * clickFmt.sampleRate) + 1
let buf = AVAudioPCMBuffer(pcmFormat: clickFmt, frameCapacity: frames)!
buf.frameLength = frames
if click {
    let p = buf.floatChannelData![0]
    let csr = clickFmt.sampleRate
    var k = 0
    while Double(k) * beat < total {
        let start = Int(Double(k) * beat * csr)
        let len = Int(0.012 * csr)
        let accent = (k % 4 == 0)
        let f = accent ? 1800.0 : 1200.0
        let amp: Float = (k < countin) ? 0.5 : (accent ? 0.35 : 0.2)
        for i in 0..<len where start + i < Int(frames) {
            let env = Float(1.0 - Double(i) / Double(len))
            p[start + i] = amp * env * Float(sin(2 * Double.pi * f * Double(i) / csr))
        }
        k += 1
    }
}

var written: AVAudioFramePosition = 0
let need = AVAudioFramePosition(total * sr)
input.installTap(onBus: 0, bufferSize: 2048, format: inFmt) { b, _ in
    if written >= need { return }
    do { try file?.write(from: b); written += AVAudioFramePosition(b.frameLength) } catch { fputs("write: \(error)\n", stderr) }
}
engine.prepare()
try engine.start()
player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
player.play()
let t0 = Date()
fputs("count-in \(countin) beats at \(bpm) BPM, then \(seconds)s of take…\n", stderr)
while written < need && Date().timeIntervalSince(t0) < total + 2 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
input.removeTap(onBus: 0)
engine.stop()
file = nil   // release = close = header finalised
func ulid() -> String {
    let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    var ms = UInt64(Date().timeIntervalSince1970 * 1000)
    var out = [Character](repeating: "0", count: 26)
    for i in stride(from: 9, through: 0, by: -1) { out[i] = alphabet[Int(ms & 31)]; ms >>= 5 }
    for i in 10..<26 { out[i] = alphabet[Int.random(in: 0..<32)] }
    return String(out)
}
let name = (outPath as NSString).lastPathComponent.components(separatedBy: ".").dropLast().joined(separator: ".")
let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
let sidecar: [String: Any] = ["id": ulid(), "name": name, "kind": "audio",
                              "source": ["by": "mic", "device": "default input", "sr": sr, "countin_beats": countin, "grid_start_s": gridStart],
                              "parents": [], "at": iso.string(from: t0), "tempo": bpm, "key": NSNull(), "bars": NSNull(),
                              "text": "", "placed": []]
try JSONSerialization.data(withJSONObject: sidecar, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: outPath + ".motif.json"))
let dict: [String: Any] = ["status": "ok", "file": outPath, "motif": ["id": sidecar["id"]!, "name": name, "kind": "audio", "path": outPath], "seconds": Double(written) / sr, "sr": sr,
                           "channels": inFmt.channelCount, "bpm": bpm, "countin_beats": countin, "grid_start_s": gridStart]
let data = try JSONSerialization.data(withJSONObject: dict)
print(String(data: data, encoding: .utf8)!)
