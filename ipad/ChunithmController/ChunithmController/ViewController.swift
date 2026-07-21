import UIKit

final class ViewController: UIViewController, TouchViewDelegate {

    private let sender = UDPSender()
    private let touchView = TouchView()
    private let ipField = UITextField()
    private let modeButton = UIButton(type: .system)
    private var currentMask: UInt32 = 0
    private var displayLink: CADisplayLink?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // 觸控區鋪滿整個畫面
        touchView.delegate = self
        touchView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(touchView)
        NSLayoutConstraint.activate([
            touchView.topAnchor.constraint(equalTo: view.topAnchor),
            touchView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            touchView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            touchView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        setupControlBar()
    }

    // 上方一條細設定列：輸入 PC 的 IP + 連線
    private func setupControlBar() {
        ipField.placeholder = "Windows PC 的 IP，例如 192.168.0.10"
        ipField.text = "192.168.0.10"
        ipField.borderStyle = .roundedRect
        ipField.keyboardType = .numbersAndPunctuation
        ipField.autocorrectionType = .no

        let connectBtn = UIButton(type: .system)
        connectBtn.setTitle("連線", for: .normal)
        connectBtn.setTitleColor(.white, for: .normal)
        connectBtn.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        modeButton.setTitleColor(.white, for: .normal)
        modeButton.addTarget(self, action: #selector(modeButtonTapped), for: .touchUpInside)
        updateModeButtonTitle()

        let bar = UIStackView(arrangedSubviews: [ipField, connectBtn, modeButton])
        bar.axis = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 16),
        ])
    }

    @objc private func connectTapped() {
        guard let ip = ipField.text, !ip.isEmpty else { return }
        sender.connect(host: ip, port: 7777)
        ipField.resignFirstResponder()
        startHeartbeat()
    }

    // 心跳：用 CADisplayLink 在每個畫面更新時重送目前狀態。
    // 萬一某個封包掉了，下一幀就把狀態補回去 (自我修復)。
    // ProMotion 機種會以 120Hz 跑，剛好。
    private func startHeartbeat() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(heartbeat))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func heartbeat() {
        sender.send(mask: currentMask)
    }

    // TouchViewDelegate：狀態一變就立刻送 (這比等心跳更低延遲)。
    func touchMaskChanged(_ mask: UInt32) {
        currentMask = mask
        sender.send(mask: mask)
    }

    // 切換模式一 (32 區 chunithm 版面) / 模式二 (dfjk 4 區)。
    @objc private func modeButtonTapped() {
        let newMode: TouchView.Mode = (touchView.mode == .classic32) ? .dfjk4 : .classic32
        touchView.setMode(newMode)
        updateModeButtonTitle()
    }

    private func updateModeButtonTitle() {
        switch touchView.mode {
        case .classic32:
            modeButton.setTitle("模式：CHUNITHM", for: .normal)
        case .dfjk4:
            modeButton.setTitle("模式：DFJK", for: .normal)
        }
    }
}
