import UIKit
import WebKit
import AVFoundation

// ══════════════════════════════════════════════════════════════════════
//  ChatLink — ViewController  (iOS 12+)
//  Native splash → fade-in WebView, camera permission, JS bridge
// ══════════════════════════════════════════════════════════════════════

class ViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {

    var webView:     WKWebView!
    var splashView:  CLSplashView!
    var statusBar:   CLStatusBar!
    var pageLoaded   = false

    // MARK: - viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)

        splashView = CLSplashView(frame: view.bounds)
        view.addSubview(splashView)
        splashView.startPulse()

        statusBar = CLStatusBar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        view.addSubview(statusBar)

        buildWebView()

        requestCameraPermission { [weak self] in
            DispatchQueue.main.async { self?.loadPage() }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(onForeground),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onBackground),
            name: UIApplication.willResignActiveNotification, object: nil)
    }

    // MARK: - Build WebView
    func buildWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKPreferences()
        prefs.javaScriptEnabled = true
        config.preferences = prefs

        config.websiteDataStore = WKWebsiteDataStore.default()
        config.userContentController.add(self, name: "iosbridge")
        config.userContentController.add(self, name: "statusUpdate")

        let flagJS = """
        window._chatLinkNative = true;
        window._nativeApp      = true;
        window._iosBuild       = true;
        window._nativeStatus = function(type, msg) {
          try { window.webkit.messageHandlers.statusUpdate.postMessage({type:type,msg:msg}); }
          catch(e) {}
        };
        """
        let flagScript = WKUserScript(source: flagJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(flagScript)

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.bounces              = false
        webView.scrollView.isScrollEnabled      = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor                 = UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        webView.isOpaque                        = false
        webView.navigationDelegate              = self
        webView.uiDelegate                      = self
        webView.alpha                           = 0

        view.insertSubview(webView, belowSubview: splashView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: - Camera permission
    func requestCameraPermission(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    completion()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { _ in completion() }
        default:             completion()
        }
    }

    // MARK: - Load page
    func loadPage() {
        let url = Bundle.main.url(forResource: "index", withExtension: "html",
                                  subdirectory: "Resources")
               ?? Bundle.main.url(forResource: "index", withExtension: "html")
        guard let url = url else { splashView.showError("index.html not found"); return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !pageLoaded else { return }
        pageLoaded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.revealWebView()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        splashView.showError("Load failed")
    }

    func revealWebView() {
        splashView.dismissWithFade { [weak self] in self?.splashView.removeFromSuperview() }
        UIView.animate(withDuration: 0.45, delay: 0.15, options: .curveEaseOut) {
            self.webView.alpha = 1
        }
    }

    // MARK: - Camera permission iOS 15+
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    // MARK: - WKUIDelegate alert/confirm (needed for camera permission dialogs on iOS 12-14)
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    // MARK: - JS bridge
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "statusUpdate",
           let body = message.body as? [String: Any],
           let type = body["type"] as? String,
           let msg  = body["msg"]  as? String {
            DispatchQueue.main.async { [weak self] in self?.statusBar.update(type: type, message: msg) }
        }
    }

    // MARK: - Lifecycle
    @objc func onForeground() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.webView?.evaluateJavaScript(
                "if(typeof window.appDidBecomeActive==='function')window.appDidBecomeActive();",
                completionHandler: nil)
        }
    }
    @objc func onBackground() {
        webView?.evaluateJavaScript(
            "if(typeof window.appWillResignActive==='function')window.appWillResignActive();",
            completionHandler: nil)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersStatusBarHidden: Bool              { false }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeAllUserScripts()
    }
}


// ══════════════════════════════════════════════════════════════════════
//  CLSplashView — Native animated splash screen
// ══════════════════════════════════════════════════════════════════════

class CLSplashView: UIView {

    private let bgGrad      = CAGradientLayer()
    private let gridLayer   = CAShapeLayer()
    private let cardView    = UIView()
    private let ringOuter   = CAShapeLayer()
    private let ringInner   = CAShapeLayer()
    private let logoView    = UIView()
    private let logoLabel   = UILabel()
    private let appLabel    = UILabel()
    private let tagLabel    = UILabel()
    private let loadLabel   = UILabel()
    private let verLabel    = UILabel()
    private var dotTimer:   Timer?
    private var dotCount    = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        clipsToBounds = true

        // Background
        bgGrad.colors = [
            UIColor(red: 0.03, green: 0.04, blue: 0.10, alpha: 1).cgColor,
            UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1).cgColor,
            UIColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1).cgColor,
        ]
        bgGrad.locations  = [0, 0.55, 1]
        bgGrad.startPoint = CGPoint(x: 0.1, y: 0)
        bgGrad.endPoint   = CGPoint(x: 0.9, y: 1)
        bgGrad.frame      = bounds
        layer.addSublayer(bgGrad)

        // Grid
        gridLayer.strokeColor = UIColor(white: 1, alpha: 0.035).cgColor
        gridLayer.lineWidth   = 0.5
        gridLayer.frame       = bounds
        layer.addSublayer(gridLayer)
        drawGrid()

        // Card
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor       = UIColor(white: 1, alpha: 0.05)
        cardView.layer.cornerRadius    = 32
        cardView.layer.borderWidth     = 1
        cardView.layer.borderColor     = UIColor(white: 1, alpha: 0.10).cgColor
        cardView.layer.shadowColor     = UIColor(red: 0, green: 0.48, blue: 1, alpha: 0.22).cgColor
        cardView.layer.shadowOffset    = .zero
        cardView.layer.shadowRadius    = 50
        cardView.layer.shadowOpacity   = 1
        addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),
            cardView.widthAnchor.constraint(equalToConstant: 270),
            cardView.heightAnchor.constraint(equalToConstant: 340),
        ])

        // Ring outer (behind card content, positioned via constants)
        let rOuter = UIBezierPath(ovalIn: CGRect(x: 75, y: 34, width: 120, height: 120)).cgPath
        ringOuter.path        = rOuter
        ringOuter.fillColor   = UIColor.clear.cgColor
        ringOuter.strokeColor = UIColor(red: 0, green: 0.73, blue: 1, alpha: 0.20).cgColor
        ringOuter.lineWidth   = 1
        cardView.layer.addSublayer(ringOuter)

        let rInner = UIBezierPath(ovalIn: CGRect(x: 85, y: 44, width: 100, height: 100)).cgPath
        ringInner.path        = rInner
        ringInner.fillColor   = UIColor.clear.cgColor
        ringInner.strokeColor = UIColor(red: 0, green: 0.73, blue: 1, alpha: 0.5).cgColor
        ringInner.lineWidth   = 1.5
        cardView.layer.addSublayer(ringInner)

        // Logo circle
        let logoSize: CGFloat = 76
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.backgroundColor      = UIColor(red: 0, green: 0.48, blue: 1, alpha: 1)
        logoView.layer.cornerRadius   = logoSize / 2
        logoView.layer.shadowColor    = UIColor(red: 0, green: 0.48, blue: 1, alpha: 0.65).cgColor
        logoView.layer.shadowRadius   = 22
        logoView.layer.shadowOffset   = .zero
        logoView.layer.shadowOpacity  = 1
        cardView.addSubview(logoView)
        NSLayoutConstraint.activate([
            logoView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            logoView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 56),
            logoView.widthAnchor.constraint(equalToConstant: logoSize),
            logoView.heightAnchor.constraint(equalToConstant: logoSize),
        ])

        logoLabel.text          = "CL"
        logoLabel.font          = UIFont.systemFont(ofSize: 27, weight: .black)
        logoLabel.textColor     = .white
        logoLabel.textAlignment = .center
        logoLabel.translatesAutoresizingMaskIntoConstraints = false
        logoView.addSubview(logoLabel)
        NSLayoutConstraint.activate([
            logoLabel.centerXAnchor.constraint(equalTo: logoView.centerXAnchor),
            logoLabel.centerYAnchor.constraint(equalTo: logoView.centerYAnchor),
        ])

        // App name
        appLabel.text          = "ChatLink"
        appLabel.font          = UIFont.systemFont(ofSize: 30, weight: .bold)
        appLabel.textColor     = .white
        appLabel.textAlignment = .center
        appLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(appLabel)
        NSLayoutConstraint.activate([
            appLabel.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 20),
            appLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
        ])

        // Tagline
        tagLabel.text          = "Secure Face Recognition Chat"
        tagLabel.font          = UIFont.systemFont(ofSize: 12, weight: .medium)
        tagLabel.textColor     = UIColor(white: 1, alpha: 0.40)
        tagLabel.textAlignment = .center
        tagLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(tagLabel)
        NSLayoutConstraint.activate([
            tagLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 7),
            tagLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
        ])

        // Divider
        let div = UIView()
        div.backgroundColor = UIColor(white: 1, alpha: 0.07)
        div.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(div)
        NSLayoutConstraint.activate([
            div.topAnchor.constraint(equalTo: tagLabel.bottomAnchor, constant: 26),
            div.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 28),
            div.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -28),
            div.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Loading
        loadLabel.text          = "Loading..."
        if #available(iOS 13.0, *) { loadLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium) } else { loadLabel.font = UIFont(name: "Courier New", size: 12) ?? UIFont.systemFont(ofSize: 12) }
        loadLabel.textColor     = UIColor(red: 0, green: 0.73, blue: 1, alpha: 0.75)
        loadLabel.textAlignment = .center
        loadLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(loadLabel)
        NSLayoutConstraint.activate([
            loadLabel.topAnchor.constraint(equalTo: div.bottomAnchor, constant: 20),
            loadLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
        ])

        // Version
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        verLabel.text          = "v\(ver)  ·  iOS 12+"
        if #available(iOS 13.0, *) { verLabel.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular) } else { verLabel.font = UIFont(name: "Courier New", size: 10) ?? UIFont.systemFont(ofSize: 10) }
        verLabel.textColor     = UIColor(white: 1, alpha: 0.18)
        verLabel.textAlignment = .center
        verLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(verLabel)
        NSLayoutConstraint.activate([
            verLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -44),
            verLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    private func drawGrid() {
        let path = UIBezierPath()
        let step: CGFloat = 42
        var x: CGFloat = 0
        while x <= bounds.width  { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: bounds.height)); x += step }
        var y: CGFloat = 0
        while y <= bounds.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: bounds.width, y: y)); y += step }
        gridLayer.path = path.cgPath
    }

    func startPulse() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0; pulse.toValue = 1.09; pulse.duration = 1.5
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ringOuter.add(pulse, forKey: "pulse")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.2; fade.toValue = 0.75; fade.duration = 1.5
        fade.autoreverses = true; fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ringOuter.add(fade, forKey: "fade")

        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.fromValue = 0; rot.toValue = CGFloat.pi * 2; rot.duration = 5
        rot.repeatCount = .infinity
        ringInner.add(rot, forKey: "rotate")

        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.dotCount = (self.dotCount + 1) % 4
            self.loadLabel.text = "Loading" + String(repeating: ".", count: self.dotCount)
        }
    }

    func showError(_ msg: String) {
        dotTimer?.invalidate()
        loadLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.9)
        loadLabel.text      = "⚠ \(msg)"
    }

    func dismissWithFade(completion: @escaping () -> Void) {
        dotTimer?.invalidate()
        ringOuter.removeAllAnimations()
        ringInner.removeAllAnimations()
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseIn, animations: {
            self.alpha     = 0
            self.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        }, completion: { _ in completion() })
    }
}


// ══════════════════════════════════════════════════════════════════════
//  CLStatusBar — Floating native status pill
// ══════════════════════════════════════════════════════════════════════

class CLStatusBar: UIView {

    private let pill      = UIView()
    private let iconLabel = UILabel()
    private let textLabel = UILabel()
    private var hideTimer: Timer?
    private var visible   = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        backgroundColor = .clear

        pill.backgroundColor     = UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 0.93)
        pill.layer.cornerRadius  = 14
        pill.layer.borderWidth   = 1
        pill.layer.borderColor   = UIColor(white: 1, alpha: 0.13).cgColor
        pill.layer.shadowColor   = UIColor.black.cgColor
        pill.layer.shadowRadius  = 10
        pill.layer.shadowOpacity = 0.4
        pill.layer.shadowOffset  = CGSize(width: 0, height: 4)
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        iconLabel.font = UIFont.systemFont(ofSize: 11)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(iconLabel)

        if #available(iOS 13.0, *) { textLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium) } else { textLabel.font = UIFont(name: "Courier New", size: 11) ?? UIFont.systemFont(ofSize: 11) }
        textLabel.textColor     = UIColor(white: 0.85, alpha: 1)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(textLabel)

        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            pill.heightAnchor.constraint(equalToConstant: 28),

            iconLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            iconLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 14),

            textLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 5),
            textLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
            textLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    func update(type: String, message: String) {
        let (ico, col): (String, UIColor) = {
            switch type {
            case "online":  return ("🟢", UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1))
            case "offline": return ("🔴", UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1))
            case "ai":      return ("🤖", UIColor(red: 0, green: 0.73, blue: 1, alpha: 1))
            case "warn":    return ("⚠️", UIColor(red: 1, green: 0.80, blue: 0.15, alpha: 1))
            default:        return ("ℹ️", UIColor(white: 0.7, alpha: 1))
            }
        }()
        iconLabel.text  = ico
        textLabel.text  = message
        textLabel.textColor = col
        showPill()
    }

    private func showPill() {
        hideTimer?.invalidate()
        if !visible {
            visible           = true
            pill.alpha        = 0
            pill.transform    = CGAffineTransform(translationX: 0, y: -12)
            UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) {
                self.pill.alpha     = 1
                self.pill.transform = .identity
            }
        }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.hidePill()
        }
    }

    private func hidePill() {
        visible = false
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseIn) {
            self.pill.alpha     = 0
            self.pill.transform = CGAffineTransform(translationX: 0, y: -8)
        }
    }
}
