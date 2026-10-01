//
//  SpotifyPlayingItemView.swift
//  SpotifyPlaying
//
//  Based on Now Playing widget by Pierluigi Galdi (MIT).
//

import AppKit
import PockKit
import TinyConstraints

/// Thin progress line drawn under the track info.
final class ProgressBarView: NSView {

	var progress: CGFloat = 0 {
		didSet {
			if abs(oldValue - progress) > 0.0005 {
				needsDisplay = true
			}
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
		NSColor(white: 1, alpha: 0.18).setFill()
		track.fill()
		var filled = bounds
		filled.size.width = bounds.width * min(max(progress, 0), 1)
		spotifyGreen.setFill()
		NSBezierPath(roundedRect: filled, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
	}

}

final class SpotifyPlayingItemView: PKDetailView {

	/// Handlers
	var didTap: (() -> Void)?
	var didSwipeLeft: (() -> Void)?
	var didSwipeRight: (() -> Void)?
	var didLongPress: (() -> Void)?

	let progressBar = ProgressBarView(frame: .zero)

	override func didLoad() {
		canScrollTitle = true
		canScrollSubtitle = true
		titleView.numberOfLoop = 3
		subtitleView.numberOfLoop = 1
		maxWidth = 160
		addSubview(progressBar)
		progressBar.height(2)
		progressBar.bottomToSuperview()
		progressBar.leading(to: labelsContainer)
		progressBar.trailing(to: contentContainer)
		super.didLoad()
	}

	func update(with client: SpotifyClient) {
		let showArtwork: Bool = Preferences[.showArtwork]
		imageView.image = (showArtwork ? client.artwork : nil) ?? client.icon
		if let track = client.track {
			setIfChanged(title: track.title ?? track.album ?? client.displayName)
			let subtitle = track.artist ?? (track.title != nil ? track.album : nil)
			subtitleView.isHidden = subtitle == nil
			setIfChanged(subtitle: subtitle)
		} else {
			// Spotify not running or nothing loaded
			setIfChanged(title: client.displayName)
			subtitleView.isHidden = true
			setIfChanged(subtitle: nil)
		}
		updateProgress(with: client)
		let animate: Bool = Preferences[.animateIconWhilePlaying]
		if animate, client.isPlaying {
			if !isAnimating {
				startBounceAnimation()
			}
		} else {
			stopBounceAnimation()
		}
	}

	/// Re-setting the same text would restart the scrolling animation (e.g. on every play/pause)
	private func setIfChanged(title: String?) {
		if titleView.text as String? != title { set(title: title) }
	}
	
	private func setIfChanged(subtitle: String?) {
		if subtitleView.text as String? != subtitle { set(subtitle: subtitle) }
	}
	
	func updateProgress(with client: SpotifyClient) {
		let show: Bool = Preferences[.showProgressBar]
		guard show, let duration = client.track?.duration, duration > 0 else {
			progressBar.isHidden = true
			return
		}
		progressBar.isHidden = false
		progressBar.progress = CGFloat(client.position / duration)
	}

	// MARK: Gestures

	override func didTapHandler() {
		didTap?()
	}

	override func didSwipeLeftHandler() {
		let invert: Bool = Preferences[.invertSwipeGesture]
		invert ? didSwipeRight?() : didSwipeLeft?()
	}

	override func didSwipeRightHandler() {
		let invert: Bool = Preferences[.invertSwipeGesture]
		invert ? didSwipeLeft?() : didSwipeRight?()
	}

	override func didLongPressHandler() {
		didLongPress?()
	}

	override func removeFromSuperview() {
		super.removeFromSuperview()
		stopBounceAnimation()
	}

}
