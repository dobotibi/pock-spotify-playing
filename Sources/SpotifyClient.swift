//
//  SpotifyClient.swift
//  SpotifyPlaying
//
//  Since macOS 15.4 MediaRemote no longer returns now playing info to third-party apps,
//  so this talks to Spotify directly:
//  - state:    `com.spotify.client.PlaybackStateChanged` distributed notification (instant, no permission needed)
//  - commands: AppleScript through `osascript` (Pock is not entitled to send Apple Events itself)
//  - artwork:  Spotify's public oEmbed endpoint
//

import AppKit

final class SpotifyClient {

	static let bundleIdentifier = "com.spotify.client"

	struct Track: Equatable {
		let id: String?
		let title: String?
		let artist: String?
		let album: String?
		/// Seconds
		let duration: TimeInterval
	}

	// MARK: State
	private(set) var track: Track?
	private(set) var isPlaying: Bool = false
	private(set) var artwork: NSImage?
	private(set) var isRunning: Bool = false

	/// Position reported by Spotify and when it was reported; the current position is extrapolated from these.
	private var reportedPosition: TimeInterval = 0
	private var reportedAt: Date = Date()

	var position: TimeInterval {
		guard let duration = track?.duration, duration > 0 else {
			return 0
		}
		let elapsed = isPlaying ? Date().timeIntervalSince(reportedAt) : 0
		return min(max(reportedPosition + elapsed, 0), duration)
	}

	/// Called on the main thread whenever anything above changes.
	var onChange: (() -> Void)?

	static var displayName: String {
		return NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyClient.bundleIdentifier)?
			.deletingPathExtension().lastPathComponent ?? "Spotify"
	}

	static var icon: NSImage {
		if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyClient.bundleIdentifier) {
			return NSWorkspace.shared.icon(forFile: url.path)
		}
		return NSWorkspace.shared.icon(forFileType: "mp3")
	}

	var displayName: String { return SpotifyClient.displayName }
	var icon: NSImage { return SpotifyClient.icon }
	
	// MARK: Artwork
	private var artworkTask: URLSessionTask?
	private var artworkCache: [String: NSImage] = [:]
	private var artworkCacheOrder: [String] = []

	private static let scriptQueue = DispatchQueue(label: "SpotifyPlaying.osascript")

	// MARK: Init
	init() {
		isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyClient.bundleIdentifier).isEmpty
		DistributedNotificationCenter.default().addObserver(self,
															selector: #selector(playbackStateChanged),
															name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
															object: nil,
															suspensionBehavior: .deliverImmediately)
		let workspaceCenter = NSWorkspace.shared.notificationCenter
		workspaceCenter.addObserver(self, selector: #selector(applicationDidLaunch), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
		workspaceCenter.addObserver(self, selector: #selector(applicationDidTerminate), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
		refresh()
	}

	deinit {
		DistributedNotificationCenter.default().removeObserver(self)
		NSWorkspace.shared.notificationCenter.removeObserver(self)
		artworkTask?.cancel()
	}

	// MARK: Commands

	func togglePlayPause() {
		guard isRunning else {
			// Launches Spotify and resumes the last played item
			SpotifyClient.run("tell application id \"\(SpotifyClient.bundleIdentifier)\" to play")
			return
		}
		// Optimistic update, Spotify confirms with a notification right after
		reportedPosition = position
		reportedAt = Date()
		isPlaying.toggle()
		notifyChange()
		SpotifyClient.run("tell application id \"\(SpotifyClient.bundleIdentifier)\" to playpause")
	}

	func nextTrack() {
		guard isRunning else { return }
		SpotifyClient.run("tell application id \"\(SpotifyClient.bundleIdentifier)\" to next track")
	}

	func previousTrack() {
		guard isRunning else { return }
		SpotifyClient.run("tell application id \"\(SpotifyClient.bundleIdentifier)\" to previous track")
	}

	func openSpotify() {
		guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyClient.bundleIdentifier) else {
			return
		}
		NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
	}

	/// Spotify only posts its notification on changes, so ask it for the current state (e.g. when the widget loads).
	func refresh() {
		guard isRunning else {
			return
		}
		let script = """
		if application id "\(SpotifyClient.bundleIdentifier)" is running then
			tell application id "\(SpotifyClient.bundleIdentifier)"
				set t to current track
				return (name of t) & tab & (artist of t) & tab & (album of t) & tab & (id of t) & tab & (duration of t) & tab & (player position) & tab & (player state as string)
			end tell
		end if
		"""
		let requestedAt = Date()
		SpotifyClient.run(script) { [weak self] output in
			let fields = output?.components(separatedBy: "\t") ?? []
			guard let self = self, fields.count == 7, self.lastNotificationAt < requestedAt else {
				// A real notification arrived meanwhile; it is more recent.
				return
			}
			let states = ["playing": "Playing", "paused": "Paused", "stopped": "Stopped"]
			self.apply([
				"Name": fields[0],
				"Artist": fields[1],
				"Album": fields[2],
				"Track ID": fields[3],
				"Duration": Double(fields[4]) ?? 0,
				// AppleScript may format decimals with the user's locale (e.g. "12,5")
				"Playback Position": Double(fields[5].replacingOccurrences(of: ",", with: ".")) ?? 0,
				"Player State": states[fields[6]] ?? "Paused"
			])
		}
	}

	// MARK: Notifications

	private var lastNotificationAt: Date = .distantPast

	@objc private func playbackStateChanged(_ notification: Notification) {
		lastNotificationAt = Date()
		apply(notification.userInfo ?? [:])
	}

	@objc private func applicationDidLaunch(_ notification: Notification) {
		guard isSpotify(notification) else { return }
		isRunning = true
		notifyChange()
	}

	@objc private func applicationDidTerminate(_ notification: Notification) {
		guard isSpotify(notification) else { return }
		isRunning = false
		isPlaying = false
		track = nil
		artwork = nil
		artworkTask?.cancel()
		notifyChange()
	}

	private func isSpotify(_ notification: Notification) -> Bool {
		let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
		return app?.bundleIdentifier == SpotifyClient.bundleIdentifier
	}

	private func apply(_ info: [AnyHashable: Any]) {
		isRunning = true
		let state = info["Player State"] as? String
		if state == "Stopped" {
			track = nil
			artwork = nil
			artworkTask?.cancel()
		} else {
			let newTrack = Track(
				id: info["Track ID"] as? String,
				title: (info["Name"] as? String).nonEmpty,
				artist: (info["Artist"] as? String).nonEmpty,
				album: (info["Album"] as? String).nonEmpty,
				duration: ((info["Duration"] as? NSNumber)?.doubleValue ?? 0) / 1000
			)
			if newTrack.id != track?.id {
				artwork = nil
			}
			track = newTrack
			if artwork == nil {
				loadArtwork(for: newTrack)
			}
		}
		isPlaying = state == "Playing"
		reportedPosition = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
		reportedAt = Date()
		notifyChange()
	}

	private func notifyChange() {
		onChange?()
	}

	// MARK: Artwork

	private func loadArtwork(for track: Track) {
		artworkTask?.cancel()
		guard let id = track.id else {
			return
		}
		if let cached = artworkCache[id] {
			artwork = cached
			return
		}
		// "spotify:track:<id>" -> "https://open.spotify.com/track/<id>"
		let parts = id.components(separatedBy: ":")
		guard parts.count == 3, ["track", "episode"].contains(parts[1]),
			  let url = URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/\(parts[1])/\(parts[2])") else {
			// Local files and ads have no public artwork
			return
		}
		artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
			guard let data = data,
				  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let thumbnail = (json["thumbnail_url"] as? String).flatMap(URL.init(string:)) else {
				return
			}
			self?.artworkTask = URLSession.shared.dataTask(with: thumbnail) { [weak self] data, _, _ in
				guard let image = data.flatMap(NSImage.init(data:)) else {
					return
				}
				DispatchQueue.main.async {
					self?.didLoadArtwork(image, for: id)
				}
			}
			self?.artworkTask?.resume()
		}
		artworkTask?.resume()
	}

	private func didLoadArtwork(_ image: NSImage, for id: String) {
		artworkCache[id] = image
		artworkCacheOrder.append(id)
		if artworkCacheOrder.count > 30 {
			artworkCache[artworkCacheOrder.removeFirst()] = nil
		}
		guard track?.id == id else {
			return
		}
		artwork = image
		notifyChange()
	}

	// MARK: AppleScript

	/// Runs AppleScript via `osascript` off the main thread; `completion` gets stdout on the main thread (nil on failure).
	private static func run(_ script: String, completion: ((String?) -> Void)? = nil) {
		scriptQueue.async {
			let process = Process()
			let pipe = Pipe()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
			process.arguments = ["-e", script]
			process.standardOutput = pipe
			process.standardError = FileHandle.nullDevice
			var output: String?
			if (try? process.run()) != nil {
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()
				if process.terminationStatus == 0 {
					output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
				} else {
					NSLog("[SPOTIFY_PLAYING]: osascript failed with status \(process.terminationStatus)")
				}
			}
			if let completion = completion {
				DispatchQueue.main.async { completion(output) }
			}
		}
	}

}

private extension Optional where Wrapped == String {
	var nonEmpty: String? {
		guard let value = self, !value.isEmpty else { return nil }
		return value
	}
}
