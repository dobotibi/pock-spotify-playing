//
//  Preferences.swift
//  SpotifyPlaying
//
//  Based on Now Playing widget by Pierluigi Galdi (MIT).
//

import Foundation

extension Notification.Name {
	static let spotifyPlayingPreferencesDidChange = Notification.Name("SpotifyPlaying.preferencesDidChange")
}

enum SpotifyPlayingStyle: String, CaseIterable {
	case `default`, onlyInfo, playPause
}

/// Widget preferences, stored in Pock's defaults with a `SpotifyPlaying.` prefix
/// so they never collide with the built-in Now Playing widget.
struct Preferences {
	enum Keys: String, CaseIterable {
		case style
		case hideIfNotPlaying
		case animateIconWhilePlaying
		case showArtwork
		case invertSwipeGesture
		case showProgressBar
		case showPlaybackTime
	}

	private static let defaults: [Keys: Any] = [
		.style: SpotifyPlayingStyle.default.rawValue,
		.hideIfNotPlaying: false,
		.animateIconWhilePlaying: true,
		.showArtwork: true,
		.invertSwipeGesture: true,
		.showProgressBar: true,
		.showPlaybackTime: false
	]

	private static func storageKey(_ key: Keys) -> String {
		return "SpotifyPlaying.\(key.rawValue)"
	}

	static subscript<T>(_ key: Keys) -> T {
		get {
			return (UserDefaults.standard.object(forKey: storageKey(key)) ?? defaults[key]) as! T
		}
		set {
			UserDefaults.standard.set(newValue, forKey: storageKey(key))
			NotificationCenter.default.post(name: .spotifyPlayingPreferencesDidChange, object: nil)
		}
	}

	static var style: SpotifyPlayingStyle {
		return SpotifyPlayingStyle(rawValue: Preferences[.style]) ?? .default
	}

	static func reset() {
		Keys.allCases.forEach { UserDefaults.standard.removeObject(forKey: storageKey($0)) }
		NotificationCenter.default.post(name: .spotifyPlayingPreferencesDidChange, object: nil)
	}
}
