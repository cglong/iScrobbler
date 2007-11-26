on StopPlaying()
	tell application "iTunes"
		stop
	end tell
end StopPlaying

on PlayNextTrack()
	tell application "iTunes"
		next track
	end tell
end PlayNextTrack

on PlayerLibraryUUID()
	tell application "iTunes"
		tell source "Library"
			return persistent ID
		end tell
	end tell
end PlayerLibraryUUID
