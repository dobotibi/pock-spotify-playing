//
//  SpotifyPlayingView.swift
//  SpotifyPlaying
//
//  Based on Now Playing widget by Pierluigi Galdi (MIT).
//

import AppKit
import PockKit
import TinyConstraints

let spotifyGreen = NSColor(calibratedRed: 30/255, green: 215/255, blue: 96/255, alpha: 1)

/// Native Touch Bar pill button with an SF Symbol (falls back to the classic Touch Bar glyphs before macOS 11).
private enum ControlButton {
	case previous, next, play, pause
	
	private var symbolName: String {
		switch self {
		case .previous: return "backward.fill"
		case .next:     return "forward.fill"
		case .play:     return "play.fill"
		case .pause:    return "pause.fill"
		}
	}
	
	private var fallbackName: NSImage.Name {
		switch self {
		case .previous: return NSImage.touchBarRewindTemplateName
		case .next:     return NSImage.touchBarFastForwardTemplateName
		case .play:     return NSImage.touchBarPlayTemplateName
		case .pause:    return NSImage.touchBarPauseTemplateName
		}
	}
	
	var image: NSImage {
		if #available(macOS 11.0, *),
		   let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
			.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)) {
			return symbol
		}
		return NSImage(named: fallbackName)!
	}
	
	func build(target: Any?, action: Selector?, width: CGFloat = 44, tint: NSColor? = nil) -> NSButton {
		let button = NSButton(image: image, target: target, action: action)
		button.imagePosition = .imageOnly
		button.bezelColor = tint
		button.width(width)
		return button
	}
}

final class SpotifyPlayingView: PKView {

	/// UI
	private let stackView = NSStackView(frame: .zero)
	private var itemView: SpotifyPlayingItemView?
	private var playPauseButton: NSButton?
	private var timeLabel: NSTextField?

	/// Data
	private var client: SpotifyClient?
	private var progressTimer: Timer?

	private var style: SpotifyPlayingStyle = Preferences.style

	private var shouldHideWidget: Bool {
		let hide: Bool = Preferences[.hideIfNotPlaying]
		guard hide, let client = client else {
			return false
		}
		return !client.isRunning || client.track == nil
	}

	convenience init(frame: NSRect, client: SpotifyClient?) {
		self.init(frame: frame)
		self.client = client
		stackView.orientation = .horizontal
		stackView.alignment = .centerY
		stackView.distribution = .fillProportionally
		addSubview(stackView)
		stackView.edgesToSuperview()
		client?.onChange = { [weak self] in self?.updateContent() }
		NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange), name: .spotifyPlayingPreferencesDidChange, object: nil)
		rebuild()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
		progressTimer?.invalidate()
		client?.onChange = nil
	}

	// MARK: Build

	@objc private func preferencesDidChange() {
		rebuild()
	}

	/// Recreates the arranged views for the current style and fills them with the current state.
	private func rebuild() {
		style = Preferences.style
		stackView.arrangedSubviews.forEach {
			stackView.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}
		itemView = nil
		playPauseButton = nil
		timeLabel = nil
		guard !shouldHideWidget else {
			updateProgressTimer()
			return
		}
		let showTime: Bool = Preferences[.showPlaybackTime]
		var views: [NSView] = []
		switch style {
		case .default, .onlyInfo:
			let item = SpotifyPlayingItemView(leftToRight: true)
			item.didTap        = { [weak self] in self?.client?.togglePlayPause() }
			item.didSwipeLeft  = { [weak self] in self?.client?.previousTrack() }
			item.didSwipeRight = { [weak self] in self?.client?.nextTrack() }
			item.didLongPress  = { [weak self] in self?.client?.openSpotify() }
			itemView = item
			views = [item]
		case .playPause:
			let button = ControlButton.play.build(target: self, action: #selector(togglePlayPause), width: 64, tint: spotifyGreen)
			playPauseButton = button
			views = [button]
		}
		if showTime {
			let label = NSTextField(labelWithString: "")
			label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
			label.textColor = NSColor(calibratedRed: 124/255, green: 131/255, blue: 127/255, alpha: 1)
			label.setContentCompressionResistancePriority(.required, for: .horizontal)
			timeLabel = label
			views.append(label)
		}
		switch style {
		case .default:
			views = [previousButton()] + views + [nextButton()]
			stackView.spacing = 14
		case .onlyInfo:
			stackView.spacing = 10
		case .playPause:
			views = [previousButton()] + views + [nextButton()]
			stackView.spacing = 10
		}
		views.forEach { stackView.addArrangedSubview($0) }
		updateContent()
	}

	private func previousButton() -> NSButton {
		return ControlButton.previous.build(target: self, action: #selector(previousTrack))
	}

	private func nextButton() -> NSButton {
		return ControlButton.next.build(target: self, action: #selector(nextTrack))
	}

	// MARK: Update

	private func updateContent() {
		guard let client = client else {
			return
		}
		// Visibility may have changed (Spotify launched/quit, track loaded/stopped)
		if shouldHideWidget != stackView.arrangedSubviews.isEmpty {
			rebuild()
			return
		}
		itemView?.update(with: client)
		playPauseButton?.image = (client.isPlaying ? ControlButton.pause : ControlButton.play).image
		updateTime()
		updateProgressTimer()
	}

	private func updateTime() {
		guard let client = client else {
			return
		}
		if let itemView = itemView {
			itemView.updateProgress(with: client)
		}
		if let timeLabel = timeLabel {
			if let duration = client.track?.duration, duration > 0 {
				timeLabel.isHidden = false
				timeLabel.stringValue = "\(format(client.position)) / \(format(duration))"
			} else {
				timeLabel.isHidden = true
			}
		}
	}

	private func format(_ seconds: TimeInterval) -> String {
		let total = Int(seconds.rounded(.down))
		if total >= 3600 {
			return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
		}
		return String(format: "%d:%02d", total / 60, total % 60)
	}

	/// Ticks only while something is playing and a time element is visible.
	private func updateProgressTimer() {
		let needsTimer = (client?.isPlaying ?? false) && ((itemView != nil && Preferences[.showProgressBar] as Bool) || timeLabel != nil)
		if needsTimer, progressTimer == nil {
			let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateTime() }
			RunLoop.main.add(timer, forMode: .common)
			progressTimer = timer
		} else if !needsTimer {
			progressTimer?.invalidate()
			progressTimer = nil
		}
	}

	// MARK: Actions

	@objc private func togglePlayPause() {
		client?.togglePlayPause()
	}

	@objc private func previousTrack() {
		client?.previousTrack()
	}

	@objc private func nextTrack() {
		client?.nextTrack()
	}

	override func didLongPressHandler() {
		client?.openSpotify()
	}

}
