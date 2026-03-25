#if canImport(FoundationModels)
import FoundationModels
#endif
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "xyz.depollsoft.monkeyssh/ssh_service"
  private let transferChannelName = "xyz.depollsoft.monkeyssh/transfer"
  private let appleDatabaseChannelName = "xyz.depollsoft.monkeyssh/apple_file_protection"
  private let localTerminalAiChannelName = "xyz.depollsoft.monkeyssh/local_terminal_ai"
  private let maxTransferPayloadBytes = 10 * 1024 * 1024
  private var backgroundSshChannel: FlutterMethodChannel?
  private var transferChannel: FlutterMethodChannel?
  private var appleDatabaseChannel: FlutterMethodChannel?
  private var localTerminalAiChannel: FlutterMethodChannel?
  private var pendingTransferPayload: String?

  /// Background task identifier used to request a brief grace period
  /// before iOS suspends the app after entering the background.
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "AppDelegateBridge") {
        setupBackgroundSshChannel(with: registrar)
        setupTransferChannel(with: registrar)
        setupAppleDatabaseChannel(with: registrar)
        setupLocalTerminalAiChannel(with: registrar)
      } else {
        NSLog("Failed to configure AppDelegate method channels.")
      }
    if let launchUrl = launchOptions?[.url] as? URL {
      _ = handleTransferFile(url: launchUrl)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if handleTransferFile(url: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    if #available(iOS 16.1, *) {
      ConnectionStatusLiveActivityManager.shared.setForegroundState(
        isForeground: false
      )
    }

    // Request a brief amount of extra execution time so the Dart isolate can
    // flush any in-flight SSH keepalive traffic before iOS suspends the app.
    // The Live Activity remains a status surface only; it does not extend
    // background execution beyond this short grace period.
    backgroundTaskId = application.beginBackgroundTask(withName: "SSHKeepAlive") {
      // Expiration handler — clean up when time runs out.
      application.endBackgroundTask(self.backgroundTaskId)
      self.backgroundTaskId = .invalid
    }
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    if #available(iOS 16.1, *) {
      ConnectionStatusLiveActivityManager.shared.setForegroundState(
        isForeground: true
      )
    }

    // End the background task when returning to the foreground.
    if backgroundTaskId != .invalid {
      application.endBackgroundTask(backgroundTaskId)
      backgroundTaskId = .invalid
    }
  }

  private func setupBackgroundSshChannel(with registrar: FlutterPluginRegistrar) {
    backgroundSshChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    backgroundSshChannel?.setMethodCallHandler(handleBackgroundSshMethodCall)
    NSLog("Configured SSH background method channel.")
  }

  private func setupTransferChannel(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: transferChannelName,
      binaryMessenger: registrar.messenger()
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

  private func setupAppleDatabaseChannel(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: appleDatabaseChannelName,
      binaryMessenger: registrar.messenger()
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

  private func setupLocalTerminalAiChannel(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: localTerminalAiChannelName,
      binaryMessenger: registrar.messenger()
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
      case "generateText":
        self.handleLocalTerminalAiGenerate(call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleBackgroundSshMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "updateStatus":
      guard
        let arguments = call.arguments as? [String: Any],
        let connectionCount = arguments["connectionCount"] as? Int,
        let connectedCount = arguments["connectedCount"] as? Int
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Missing live activity status arguments",
            details: nil
          )
        )
        return
      }

      NSLog(
        "Received SSH background status update: %d total, %d connected.",
        connectionCount,
        connectedCount
      )
      if #available(iOS 16.1, *) {
        ConnectionStatusLiveActivityManager.shared.updateStatus(
          connectionCount: connectionCount,
          connectedCount: connectedCount
        )
      }
      result(nil)
    case "setForegroundState":
      guard
        let arguments = call.arguments as? [String: Any],
        let isForeground = arguments["isForeground"] as? Bool
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Missing foreground state argument",
            details: nil
          )
        )
        return
      }

      NSLog("Received SSH app foreground state update: %@.", isForeground.description)
      if #available(iOS 16.1, *) {
        ConnectionStatusLiveActivityManager.shared.setForegroundState(
          isForeground: isForeground
        )
      }
      result(nil)
    case "stopService":
      NSLog("Received SSH background stop request.")
      if #available(iOS 16.1, *) {
        ConnectionStatusLiveActivityManager.shared.stop()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

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

    let applyFileProtection =
      arguments["applyFileProtection"] as? Bool ?? true

    do {
      try applyAppleDatabaseFilePolicy(
        databaseDirectoryPath: databaseDirectoryPath,
        databasePath: databasePath,
        companionPaths: companionPaths,
        applyFileProtection: applyFileProtection
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

  private func handleTransferFile(url: URL) -> Bool {
    guard url.pathExtension.lowercased() == "monkeysshx" else {
      return false
    }
    let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
    defer {
      if accessedSecurityScopedResource {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      pendingTransferPayload = try readTransferPayload(from: url)
      notifyIncomingTransferPayload()
      return true
    } catch {
      pendingTransferPayload = nil
      return false
    }
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
      guard #available(iOS 26.0, *) else {
        result(
          FlutterError(
            code: "unsupported_platform",
            message: "Apple Foundation Models requires iOS 26 or newer",
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
    if #available(iOS 26.0, *) {
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
            "This device does not support Apple Intelligence on-device models."
        )
      case .unavailable(.appleIntelligenceNotEnabled):
        return makeLocalTerminalAiRuntimeInfo(
          supportedPlatform: true,
          available: false,
          statusMessage: "Turn on Apple Intelligence in Settings to use the built-in model."
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
      statusMessage: "Apple Foundation Models requires iOS 26 or newer."
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
  @available(iOS 26.0, *)
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

  private func applyAppleDatabaseFilePolicy(
    databaseDirectoryPath: String,
    databasePath: String,
    companionPaths: [String],
    applyFileProtection: Bool
  ) throws {
    let validatedPaths = try validatedDatabaseFilePolicyPaths(
      databaseDirectoryPath: databaseDirectoryPath,
      databasePath: databasePath,
      companionPaths: companionPaths
    )

    try excludeFromBackup(path: validatedPaths.databaseDirectoryPath)
    if applyFileProtection {
      try applyFileProtectionClass(path: validatedPaths.databaseDirectoryPath)
    }

    for path in [validatedPaths.databasePath] + validatedPaths.companionPaths {
      guard FileManager.default.fileExists(atPath: path) else {
        continue
      }
      try excludeFromBackup(path: path)
      if applyFileProtection {
        try applyFileProtectionClass(path: path)
      }
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

  private func applyFileProtectionClass(path: String) throws {
    try FileManager.default.setAttributes(
      [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
      ],
      ofItemAtPath: path
    )
  }
}
