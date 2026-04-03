#if canImport(FoundationModels)
import FoundationModels
#endif
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pendingTransferPayload: String?
  private let transferChannelName = "xyz.depollsoft.monkeyssh/transfer"
  private let appleDatabaseChannelName = "xyz.depollsoft.monkeyssh/apple_file_protection"
  private let localTerminalAiChannelName = "xyz.depollsoft.monkeyssh/local_terminal_ai"
  private let maxTransferPayloadBytes = 10 * 1024 * 1024
  private var transferChannel: FlutterMethodChannel?
  private var appleDatabaseChannel: FlutterMethodChannel?
  private var localTerminalAiChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      setupTransferChannel(with: controller)
      setupAppleDatabaseChannel(with: controller)
      setupLocalTerminalAiChannel(with: controller)
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    guard filename.lowercased().hasSuffix(".monkeysshx") else {
      return false
    }
    do {
      pendingTransferPayload = try readTransferPayload(from: URL(fileURLWithPath: filename))
      notifyIncomingTransferPayload()
      return true
    } catch {
      pendingTransferPayload = nil
      return false
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func setupTransferChannel(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: transferChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    transferChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "consumeIncomingTransferPayload":
        result(self.pendingTransferPayload)
        self.pendingTransferPayload = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    notifyIncomingTransferPayload()
  }

  private func setupAppleDatabaseChannel(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: appleDatabaseChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    appleDatabaseChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "applyDatabaseFilePolicy":
        self.handleAppleDatabaseMethodCall(call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupLocalTerminalAiChannel(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: localTerminalAiChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    localTerminalAiChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "getRuntimeInfo":
        result(self.localTerminalAiRuntimeInfo())
      case "prepareRuntime":
        result(self.localTerminalAiRuntimeInfo())
      case "generateText":
        self.handleLocalTerminalAiGenerate(call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func readTransferPayload(from url: URL) throws -> String {
    let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    if let fileSize, fileSize > maxTransferPayloadBytes {
      throw NSError(domain: "MonkeySSHTransfer", code: 1)
    }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    if data.count > maxTransferPayloadBytes {
      throw NSError(domain: "MonkeySSHTransfer", code: 1)
    }
    guard let payload = String(data: data, encoding: .utf8) else {
      throw NSError(domain: "MonkeySSHTransfer", code: 2)
    }
    return payload
  }

  private func notifyIncomingTransferPayload() {
    guard let payload = pendingTransferPayload else {
      return
    }
    transferChannel?.invokeMethod("onIncomingTransferPayload", arguments: payload)
  }

  private func handleLocalTerminalAiGenerate(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let prompt = arguments["prompt"] as? String,
      let maxTokens = arguments["maxTokens"] as? Int,
      !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      maxTokens > 0
    else {
      result(
        FlutterError(
          code: "invalid_args",
          message: "Missing Apple Foundation Models prompt arguments",
          details: nil
        )
      )
      return
    }

    Task {
#if canImport(FoundationModels)
      guard #available(macOS 26.0, *) else {
        result(
          FlutterError(
            code: "unsupported_platform",
            message: "Apple Foundation Models requires macOS 26 or newer",
            details: nil
          )
        )
        return
      }
#else
      result(
        FlutterError(
          code: "unsupported_platform",
          message: "Apple Foundation Models is unavailable in this build",
          details: nil
        )
      )
      return
#endif
      do {
        let response = try await self.generateWithAppleFoundationModels(
          prompt: prompt,
          maxTokens: maxTokens
        )
        result(response)
      } catch {
        result(
          FlutterError(
            code: "generation_error",
            message: "Apple Foundation Models generation failed",
            details: error.localizedDescription
          )
        )
      }
    }
  }

  private func localTerminalAiRuntimeInfo() -> [String: Any] {
#if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      let model = SystemLanguageModel.default
      switch model.availability {
      case .available:
        return makeLocalTerminalAiRuntimeInfo(
          supportedPlatform: true,
          available: true,
          statusMessage: "Apple Intelligence is ready on this device.",
          modelName: "Apple Intelligence"
        )
      case .unavailable(.deviceNotEligible):
        return makeLocalTerminalAiRuntimeInfo(
          supportedPlatform: false,
          available: false,
          statusMessage:
            "This Mac does not support Apple Intelligence on-device models."
        )
      case .unavailable(.appleIntelligenceNotEnabled):
        return makeLocalTerminalAiRuntimeInfo(
          supportedPlatform: true,
          available: false,
          statusMessage: "Turn on Apple Intelligence in System Settings to use the built-in model."
        )
      case .unavailable(.modelNotReady):
        return makeLocalTerminalAiRuntimeInfo(
          supportedPlatform: true,
          available: false,
          statusMessage:
            "Apple Intelligence is still downloading or preparing its on-device model."
        )
      case .unavailable(let other):
        return makeLocalTerminalAiRuntimeInfo(
          supportedPlatform: true,
          available: false,
          statusMessage: "Apple Foundation Models unavailable: \(String(describing: other))."
        )
      }
    }
#endif
    return makeLocalTerminalAiRuntimeInfo(
      supportedPlatform: false,
      available: false,
      statusMessage: "Apple Foundation Models requires macOS 26 or newer."
    )
  }

  private func makeLocalTerminalAiRuntimeInfo(
    supportedPlatform: Bool,
    available: Bool,
    statusMessage: String,
    modelName: String? = nil
  ) -> [String: Any] {
    var info: [String: Any] = [
      "provider": "appleFoundationModels",
      "supportedPlatform": supportedPlatform,
      "available": available,
      "statusMessage": statusMessage,
    ]
    if let modelName, !modelName.isEmpty {
      info["modelName"] = modelName
    }
    return info
  }

#if canImport(FoundationModels)
  @available(macOS 26.0, *)
  private func generateWithAppleFoundationModels(
    prompt: String,
    maxTokens: Int
  ) async throws -> String {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
      throw NSError(
        domain: "LocalTerminalAi",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            localTerminalAiRuntimeInfo()["statusMessage"] as? String ??
            "Apple Intelligence is not ready on this device."
        ]
      )
    }

    let session = LanguageModelSession(
      instructions: """
      Respond with plain text only.
      Do not add markdown fences or surrounding quotes.
      """
    )
    let response = try await session.respond(
      to: prompt,
      options: GenerationOptions(
        temperature: 0.2,
        maximumResponseTokens: maxTokens
      )
    )
    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw NSError(
        domain: "LocalTerminalAi",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Apple Foundation Models returned an empty response."
        ]
      )
    }
    return text
  }
#endif

  private func handleAppleDatabaseMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let databaseDirectoryPath = arguments["databaseDirectoryPath"] as? String,
      let databasePath = arguments["databasePath"] as? String,
      let companionPaths = arguments["companionPaths"] as? [String]
    else {
      result(
        FlutterError(
          code: "invalid_args",
          message: "Missing Apple database file policy arguments",
          details: nil
        )
      )
      return
    }

    do {
      try applyAppleDatabaseFilePolicy(
        databaseDirectoryPath: databaseDirectoryPath,
        databasePath: databasePath,
        companionPaths: companionPaths
      )
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "file_policy_error",
          message: "Failed to apply Apple database file policy",
          details: error.localizedDescription
        )
      )
    }
  }

  private func applyAppleDatabaseFilePolicy(
    databaseDirectoryPath: String,
    databasePath: String,
    companionPaths: [String]
  ) throws {
    let validatedPaths = try validatedDatabaseFilePolicyPaths(
      databaseDirectoryPath: databaseDirectoryPath,
      databasePath: databasePath,
      companionPaths: companionPaths
    )

    try excludeFromBackup(path: validatedPaths.databaseDirectoryPath)

    for path in [validatedPaths.databasePath] + validatedPaths.companionPaths {
      guard FileManager.default.fileExists(atPath: path) else {
        continue
      }
      try excludeFromBackup(path: path)
    }
  }

  private func validatedDatabaseFilePolicyPaths(
    databaseDirectoryPath: String,
    databasePath: String,
    companionPaths: [String]
  ) throws -> (databaseDirectoryPath: String, databasePath: String, companionPaths: [String]) {
    func canonicalURL(for path: String) -> URL {
      URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    }

    let baseURL = canonicalURL(for: databaseDirectoryPath)
    let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"

    func validatedPath(_ path: String, kind: String) throws -> String {
      let canonicalPath = canonicalURL(for: path).path
      if canonicalPath == baseURL.path || canonicalPath.hasPrefix(basePath) {
        return canonicalPath
      }

      throw NSError(
        domain: "AppleDatabaseFilePolicy",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "\(kind) path is outside the database directory: \(path)"
        ]
      )
    }

    return (
      databaseDirectoryPath: baseURL.path,
      databasePath: try validatedPath(databasePath, kind: "Database"),
      companionPaths: try companionPaths.map { path in
        try validatedPath(path, kind: "Companion")
      }
    )
  }

  private func excludeFromBackup(path: String) throws {
    var url = URL(fileURLWithPath: path)
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try url.setResourceValues(resourceValues)
  }
}
