import Foundation
import Security

/// This executable is installed once and kept unchanged when the app is rebuilt.
/// Its Keychain identity therefore does not inherit the app's changing ad-hoc hash.
enum CredentialVault {
  struct Reply: Decodable { let status: Int32; let value: String? }
  static func call(_ action: String, account: String, value: String? = nil) -> Reply {
    do {
      let fm = FileManager.default
      let folder = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("StillWithYou/Credentials", isDirectory: true)
      let helper = "credential-vault-v1"
      let executable = folder.appendingPathComponent(helper)
      if !fm.fileExists(atPath: executable.path) {
        guard let bundled = Bundle.main.url(forResource: helper, withExtension: nil) else {
          return Reply(status: errSecNotAvailable, value: nil)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.copyItem(at: bundled, to: executable)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
      }
      let process = Process()
      let input = Pipe(), output = Pipe()
      process.executableURL = executable
      process.standardInput = input
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      try process.run()
      var request = ["action": action, "account": account]
      request["value"] = value
      try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
      try input.fileHandleForWriting.close()
      let response = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return Reply(status: errSecNotAvailable, value: nil) }
      return try JSONDecoder().decode(Reply.self, from: response)
    } catch { return Reply(status: errSecNotAvailable, value: nil) }
  }
}
