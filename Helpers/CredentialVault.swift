import Foundation
import LocalAuthentication
import Security

// Stable executable identity: v3 prevents background reads from showing a
// Keychain prompt while retaining the same service so existing keys remain readable.
// Secrets travel only through anonymous pipes, never arguments or files.
struct Request: Decodable {
  let action: String
  let account: String
  let value: String?
  let allowPrompt: String?
}
struct Reply: Encodable { let status: Int32; let value: String? }
func run() -> Reply {
  guard let request = try? JSONDecoder().decode(Request.self, from: FileHandle.standardInput.readDataToEndOfFile()),
    request.account == "chat-api" || request.account == "cosyvoice"
      || request.account.hasPrefix("verification-") else {
    return Reply(status: errSecParam, value: nil)
  }
  let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "app.stillwithyou.credential-vault.v1", kSecAttrAccount as String: request.account]
  var status: OSStatus = errSecParam
  switch request.action {
  case "read":
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext()
    context.interactionNotAllowed = request.allowPrompt != "true"
    read[kSecUseAuthenticationContext as String] = context
    var result: CFTypeRef?
    status = SecItemCopyMatching(read as CFDictionary, &result)
    return Reply(status: status, value: (result as? Data).flatMap { String(data: $0, encoding: .utf8) })
  case "write":
    guard let value = request.value, !value.isEmpty else { return Reply(status: errSecParam, value: nil) }
    let attributes = [kSecValueData as String: Data(value.utf8)]
    status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = Data(value.utf8)
      status = SecItemAdd(add as CFDictionary, nil)
    }
  case "delete":
    status = SecItemDelete(query as CFDictionary)
    if status == errSecItemNotFound { status = errSecSuccess }
  default: break
  }
  return Reply(status: status, value: nil)
}
if let data = try? JSONEncoder().encode(run()) { FileHandle.standardOutput.write(data) }
