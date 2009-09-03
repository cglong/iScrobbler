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
	try
		tell application "System Events"
			if (get name of every process) contains "iTunes" then set itunesActive to true
		end tell
	on error
		set itunesActive to true
	end try
	
	if itunesActive is true then
		with timeout of 3 seconds
			tell application "iTunes"
				set mainLib to the first item in (get every source whose kind is library)
				tell mainLib
					return persistent ID
				end tell
			end tell
		end timeout
	else
		return ""
	end if
end PlayerLibraryUUID
