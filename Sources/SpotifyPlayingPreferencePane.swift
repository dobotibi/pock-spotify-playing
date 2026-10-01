//
//  SpotifyPlayingPreferencePane.swift
//  SpotifyPlaying
//
//  Built in code (no nib) so the widget stays a single, easy to share bundle.
//

import AppKit
import PockKit

final class SpotifyPlayingPreferencePane: NSViewController, PKWidgetPreference {

	static var nibName: NSNib.Name = "SpotifyPlayingPreferencePane"

	private var styleButtons: [SpotifyPlayingStyle: NSButton] = [:]
	private var checkboxes: [Preferences.Keys: NSButton] = [:]
	private let statusLabel = NSTextField(labelWithString: "")

	private static let checkboxTitles: [(Preferences.Keys, String)] = [
		(.hideIfNotPlaying, "Hide when Spotify has nothing loaded"),
		(.animateIconWhilePlaying, "Animate icon while playing"),
		(.showArtwork, "Show album artwork"),
		(.showProgressBar, "Show progress bar"),
		(.showPlaybackTime, "Show elapsed / total time"),
		(.invertSwipeGesture, "Invert swipe gesture")
	]

	override func loadView() {
		let stack = NSStackView()
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 14
		stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

		// Header
		let icon = NSImageView(image: SpotifyClient.icon)
		icon.width(28)
		icon.height(28)
		let title = NSTextField(labelWithString: "Spotify Playing")
		title.font = .boldSystemFont(ofSize: 13)
		statusLabel.font = .systemFont(ofSize: 11)
		statusLabel.textColor = .secondaryLabelColor
		let titles = NSStackView(views: [title, statusLabel])
		titles.orientation = .vertical
		titles.alignment = .leading
		titles.spacing = 2
		stack.addArrangedSubview(NSStackView(views: [icon, titles]))

		// Style
		stack.addArrangedSubview(NSTextField(labelWithString: "Choose style:"))
		let styles = NSStackView()
		styles.spacing = 16
		let images: [SpotifyPlayingStyle: String] = [.default: "default", .onlyInfo: "only_info", .playPause: "play_pause"]
		for style in SpotifyPlayingStyle.allCases {
			let image = NSImageView(image: Bundle(for: SpotifyPlayingPreferencePane.self).image(forResource: images[style]!) ?? NSImage())
			image.imageScaling = .scaleProportionallyUpOrDown
			image.width(150)
			image.height(90)
			image.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didClickStyleImage(_:))))
			image.tag = SpotifyPlayingStyle.allCases.firstIndex(of: style)!
			let radio = NSButton(radioButtonWithTitle: "", target: self, action: #selector(didSelectStyle(_:)))
			radio.tag = image.tag
			styleButtons[style] = radio
			let column = NSStackView(views: [image, radio])
			column.orientation = .vertical
			column.spacing = 6
			styles.addArrangedSubview(column)
		}
		stack.addArrangedSubview(styles)

		// Options
		for (key, text) in SpotifyPlayingPreferencePane.checkboxTitles {
			let checkbox = NSButton(checkboxWithTitle: text, target: self, action: #selector(didToggleCheckbox(_:)))
			checkbox.identifier = NSUserInterfaceItemIdentifier(key.rawValue)
			checkboxes[key] = checkbox
			stack.addArrangedSubview(checkbox)
		}

		let hint = NSTextField(wrappingLabelWithString: "Tap: play / pause  ·  Swipe: previous / next track  ·  Long press: open Spotify")
		hint.font = .systemFont(ofSize: 11)
		hint.textColor = .secondaryLabelColor
		stack.addArrangedSubview(hint)

		view = stack
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		updateUI()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		updateUI()
	}

	private func updateUI() {
		let current = Preferences.style
		styleButtons.forEach { $0.value.state = $0.key == current ? .on : .off }
		checkboxes.forEach { $0.value.state = (Preferences[$0.key] as Bool) ? .on : .off }
		let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyClient.bundleIdentifier) != nil
		statusLabel.stringValue = installed ? "Works with the Spotify desktop app" : "Spotify is not installed"
	}

	func reset() {
		Preferences.reset()
		updateUI()
	}

	// MARK: Actions

	@objc private func didClickStyleImage(_ recognizer: NSClickGestureRecognizer) {
		selectStyle(at: recognizer.view?.tag ?? 0)
	}

	@objc private func didSelectStyle(_ sender: NSButton) {
		selectStyle(at: sender.tag)
	}

	private func selectStyle(at index: Int) {
		Preferences[.style] = SpotifyPlayingStyle.allCases[index].rawValue
		updateUI()
	}

	@objc private func didToggleCheckbox(_ sender: NSButton) {
		guard let raw = sender.identifier?.rawValue, let key = Preferences.Keys(rawValue: raw) else {
			return
		}
		Preferences[key] = sender.state == .on
	}

}
