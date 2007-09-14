on PlayTrack(theSource, thePlaylistID, theTrackID)
	tell application "iTunes"
		tell source theSource
			-- We want to try the given playlist first
			set myPlaylist to ""
			try
				set myPlaylist to first item in (every playlist whose index is thePlaylistID)
			end try
			-- if that fails, then fall back to any master lists in the source
			set thePlaylists to {myPlaylist} & (every library playlist)
			repeat with pl in thePlaylists
				try
					tell pl
						set theTrack to first item in (every track whose persistent ID is theTrackID)
						play theTrack
						return
					end tell
				end try
			end repeat
		end tell
	end tell
end PlayTrack

-- for testing within script editor
on run
	PlayTrack("Library", 3, 3099)
end run
