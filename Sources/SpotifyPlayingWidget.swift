//
//  SpotifyPlayingWidget.swift
//  SpotifyPlaying
//

import AppKit
import PockKit

final class SpotifyPlayingWidget: NSObject, PKWidget {

	static var identifier: String = "SpotifyPlayingWidget"
	var customizationLabel: String = "Spotify Playing"
	var view: NSView!

	required override init() {
		super.init()
		view = SpotifyPlayingView(frame: NSRect(x: 0, y: 0, width: 120, height: 30), client: SpotifyClient())
	}

	deinit {
		view?.removeFromSuperview()
		view = nil
	}

}
