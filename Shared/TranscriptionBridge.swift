import Foundation
import UIKit

struct TranscriptionBridge: Sendable {

  @MainActor
  static func writeTranscription(_ text: String) {
    if let url = transcriptionFileURL {
      do {
        try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        DiagnosticLog.write("bridge: wrote \(text.count) chars")
      } catch {
        DiagnosticLog.write("bridge: WRITE FAILED: \(error.localizedDescription)")
      }
    } else {
      UIPasteboard.general.setData(Data(text.utf8), forPasteboardType: self.transcriptionPasteboardType)
      DiagnosticLog.write("bridge: wrote \(text.count) chars to pasteboard fallback")
    }
    self.postDarwinNotification(DarwinNotificationName.transcriptionReady)
  }

  @MainActor
  static func readTranscription() -> String? {
    if let url = transcriptionFileURL {
      do {
        let text = try String(contentsOf: url, encoding: .utf8)
        DiagnosticLog.write("bridge: read \(text.count) chars")
        return text
      } catch {
        DiagnosticLog.write("bridge: READ FAILED: \(error.localizedDescription)")
        return nil
      }
    }
    guard let data = UIPasteboard.general.data(forPasteboardType: self.transcriptionPasteboardType) else { return nil }
    let text = String(data: data, encoding: .utf8)
    DiagnosticLog.write("bridge: read \(text?.count ?? 0) chars from pasteboard fallback")
    return text
  }

  @MainActor
  static func clearTranscription() {
    if let url = transcriptionFileURL {
      try? Data().write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    } else {
      UIPasteboard.general.setData(Data(), forPasteboardType: self.transcriptionPasteboardType)
    }
  }

  static func postDarwinNotification(_ name: String) {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
  }

  static func observeDarwinNotification(_ name: String, callback: @escaping () -> Void) -> DarwinNotificationObserver {
    DarwinNotificationObserver(name: name, callback: callback)
  }

  private static let transcriptionFileName = "transcription.txt"
  private static let transcriptionPasteboardType = "app.sayboard.transcription"

  private static var transcriptionFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent(transcriptionFileName)
  }
}

final class DarwinNotificationObserver: @unchecked Sendable {

  init(name: String, callback: @escaping () -> Void) {
    self.name = name
    self.callback = callback

    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passRetained(self).toOpaque()

    CFNotificationCenterAddObserver(
      center,
      observer,
      { _, observer, _, _, _ in
        guard let observer else { return }
        let obj = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
        obj.callback()
      },
      name as CFString,
      nil,
      .deliverImmediately,
    )
    self.isObserving = true
  }

  deinit {
    if self.isObserving {
      let center = CFNotificationCenterGetDarwinNotifyCenter()
      let observer = Unmanaged.passUnretained(self).toOpaque()
      CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(self.name as CFString), nil)
    }
  }

  func stopObserving() {
    guard self.isObserving else { return }
    self.isObserving = false

    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(self.name as CFString), nil)

    Unmanaged.passUnretained(self).release()
  }

  private let name: String
  private let callback: () -> Void
  private var isObserving = false
}
