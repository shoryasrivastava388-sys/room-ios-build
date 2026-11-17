import UIKit
import WebKit
import AVFoundation

private final class WeakRoomHandler: NSObject, WKScriptMessageHandler {
    weak var owner: RoomViewController?
    init(owner: RoomViewController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        DispatchQueue.main.async { [weak self] in self?.owner?.receive(message) }
    }
}

final class RoomViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let appURL = URL(string: "https://nexusagent.shop/app/?native=ios-1")!
    private var webView: WKWebView!
    private let loading = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()
    private let retry = UIButton(type: .system)
    private var callActive = false
    private var captureGeneration = 0
    private var permissionInFlight = false
    private var permissionApprovedAwaitingActive = false
    private var pendingPermission: ((WKPermissionDecision) -> Void)?
    private var pendingMedia: [AVMediaType] = []
    private var permissionPage: URL?
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 17/255, green: 18/255, blue: 24/255, alpha: 1)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.applicationNameForUserAgent = "RoomIOS/1.0"
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.limitsNavigationsToAppBoundDomains = true
        configuration.userContentController.add(WeakRoomHandler(owner: self), name: "RoomNative")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        loading.color = UIColor(red: 133/255, green: 120/255, blue: 239/255, alpha: 1)
        loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loading)
        NSLayoutConstraint.activate([loading.centerXAnchor.constraint(equalTo: view.centerXAnchor), loading.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.textColor = .secondaryLabel
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true
        view.addSubview(errorLabel)
        retry.setTitle("Try again", for: .normal)
        retry.tintColor = loading.color
        retry.addTarget(self, action: #selector(reloadClient), for: .touchUpInside)
        retry.translatesAutoresizingMaskIntoConstraints = false
        retry.isHidden = true
        view.addSubview(retry)
        NSLayoutConstraint.activate([
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            retry.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 20),
            retry.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        reloadClient()
    }

    private static let bootstrap = """
    (() => {
      if (location.origin !== 'https://nexusagent.shop' || !/^\\/app(?:\\/|$)/.test(location.pathname)) return;
      window.RoomNative = { postMessage: value => window.webkit.messageHandlers.RoomNative.postMessage(String(value)) };
      window.__roomIOSMedia = []; window.__roomIOSSuspended = false;
      const media = navigator.mediaDevices;
      if (media && media.getUserMedia) {
        const original = media.getUserMedia.bind(media);
        media.getUserMedia = async constraints => {
          const stream = await original(constraints);
          if (window.__roomIOSSuspended) { stream.getTracks().forEach(t => t.stop()); throw new DOMException('Room is inactive', 'AbortError'); }
          window.__roomIOSMedia.push(stream); return stream;
        };
      }
    })();
    """

    private func trusted(_ url: URL?) -> Bool {
        guard let url = url, url.scheme?.lowercased() == "https", url.host?.lowercased() == "nexusagent.shop", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        let path = url.standardized.path
        return (path == "/app" || path.hasPrefix("/app/")) && !path.split(separator: "/").contains("..")
    }
    private func trusted(_ origin: WKSecurityOrigin) -> Bool {
        origin.protocol.lowercased() == "https" && origin.host.lowercased() == "nexusagent.shop" && (origin.port == 0 || origin.port == 443)
    }
    @objc private func reloadClient() {
        denyPendingPermission()
        stopCall()
        errorLabel.isHidden = true
        retry.isHidden = true
        webView.isHidden = false
        loading.startAnimating()
        webView.load(URLRequest(url: appURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if trusted(url) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if navigationAction.targetFrame?.isMainFrame != false { openBrowser(url) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { if trusted(url) { webView.load(URLRequest(url: url)) } else { openBrowser(url) } }
        return nil
    }
    private func openBrowser(_ url: URL) {
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        denyPendingPermission(); stopCall(); loading.startAnimating()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading.stopAnimating()
        emit("room-native-ready", ["screenShare": false, "audioRoute": true, "platform": "ios", "appVersion": "1.0.0", "cacheRevision": 1, "webViewVersion": "iOS WKWebView \(UIDevice.current.systemVersion)", "origin": "https://nexusagent.shop"])
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(error) }
    private func showError(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        stopCall(); loading.stopAnimating(); webView.isHidden = true
        errorLabel.text = "Can’t reach Room. Check your connection and try again.\n\nRoom iOS 1.0.0 · iOS \(UIDevice.current.systemVersion)\n\((error as NSError).localizedDescription)"
        errorLabel.isHidden = false; retry.isHidden = false
    }
    // Default WebKit trust handling remains enabled; no certificate exceptions.

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard frame.isMainFrame, trusted(origin), trusted(frame.request.url), trusted(webView.url), UIApplication.shared.applicationState == .active else { decisionHandler(.deny); return }
        denyPendingPermission()
        switch type {
        case .camera: pendingMedia = [.video]
        case .microphone: pendingMedia = [.audio]
        case .cameraAndMicrophone: pendingMedia = [.audio, .video]
        @unknown default: decisionHandler(.deny); return
        }
        permissionPage = webView.url
        pendingPermission = decisionHandler
        permissionInFlight = true
        let generation = captureGeneration
        requestPermission(at: 0, generation: generation)
    }
    private func requestPermission(at index: Int, generation: Int) {
        guard generation == captureGeneration, pendingPermission != nil else { return }
        if index == pendingMedia.count {
            if UIApplication.shared.applicationState != .active { permissionApprovedAwaitingActive = true; return }
            finishPermission(); return
        }
        let media = pendingMedia[index]
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: requestPermission(at: index + 1, generation: generation)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: media) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self = self, generation == self.captureGeneration else { return }
                    if allowed { self.requestPermission(at: index + 1, generation: generation) } else { self.denyPendingPermission() }
                }
            }
        default: denyPendingPermission()
        }
    }
    private func finishPermission() {
        guard let completion = pendingPermission else { return }
        let allowed = UIApplication.shared.applicationState == .active && trusted(webView.url) && webView.url == permissionPage && pendingMedia.allSatisfy { AVCaptureDevice.authorizationStatus(for: $0) == .authorized }
        pendingPermission = nil; pendingMedia = []; permissionInFlight = false; permissionApprovedAwaitingActive = false
        completion(allowed ? .grant : .deny)
    }
    private func denyPendingPermission() {
        captureGeneration += 1
        let completion = pendingPermission
        pendingPermission = nil; pendingMedia = []; permissionPage = nil; permissionInFlight = false; permissionApprovedAwaitingActive = false
        completion?(.deny)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, trusted(message.frameInfo.securityOrigin), trusted(message.frameInfo.request.url), trusted(webView.url), let text = message.body as? String, text.utf8.count <= 2048, let data = text.data(using: .utf8), let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "call_active":
            guard let active = body["active"] as? Bool else { return }
            if active { startCall() } else { denyPendingPermission(); stopCall() }
        case "audio_route":
            if let speaker = body["speaker"] as? Bool { routeAudio(speaker: speaker) }
        case "screen_start", "screen_stop":
            emit("room-native-screen-state", ["active": false, "error": "Screen sharing is not included in this iOS build. A ReplayKit Broadcast Upload Extension is required for sharing other apps."])
        default: break
        }
    }
    private func startCall() {
        guard !callActive else { return }
        guard UIApplication.shared.applicationState == .active, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { emit("room-native-call-state", ["active": false, "error": "Allow microphone access and keep Room open to join."]); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
            try session.setActive(true)
            callActive = true
            emit("room-native-call-state", ["active": true])
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            emit("room-native-call-state", ["active": false, "error": "Audio could not start. End other audio sessions and retry."])
        }
    }
    private func routeAudio(speaker: Bool) {
        guard callActive else { emit("room-native-audio-route", ["speaker": false, "error": "Join a call before changing its output."]); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.overrideOutputAudioPort(speaker ? .speaker : .none)
            let actual = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
            var detail: [String: Any] = ["speaker": actual, "output": session.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")]
            if actual != speaker { detail["error"] = "The requested route is unavailable. The current connected audio output is being used." }
            emit("room-native-audio-route", detail)
        } catch { emit("room-native-audio-route", ["speaker": AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }, "error": "iOS declined this audio route."]) }
    }
    private func stopCall() {
        let wasActive = callActive; callActive = false
        if wasActive { try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]); emit("room-native-call-state", ["active": false]) }
    }
    @objc private func didEnterBackground() {
        denyPendingPermission(); stopCall()
        webView.evaluateJavaScript("window.__roomIOSSuspended=true;(window.__roomIOSMedia||[]).forEach(s=>s.getTracks().forEach(t=>t.stop()));window.__roomIOSMedia=[];window.dispatchEvent(new CustomEvent('room-app-background'));")
    }
    @objc private func didBecomeActive() {
        if trusted(webView.url) { webView.evaluateJavaScript("window.__roomIOSSuspended=false;") }
        if permissionApprovedAwaitingActive { finishPermission() }
    }
    private func emit(_ name: String, _ detail: [String: Any]) {
        guard trusted(webView?.url), let data = try? JSONSerialization.data(withJSONObject: ["name": name, "detail": detail]), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("(()=>{const e=\(json);window.dispatchEvent(new CustomEvent(e.name,{detail:e.detail}));})();")
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
