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
	set itunesActive to false
	tell application "System Events"
		if (get name of every process) contains "iTunes" then set itunesActive to true
	end tell
	
	if itunesActive is true then
		tell application "iTunes"
			tell source "Library"
				return persistent ID
			end tell
		end tell
	else
		return ""
	end if
end PlayerLibraryUUID
