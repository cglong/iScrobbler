-- syncIpod enum
property iTunesIsInactive : -1
property iTunesError : -2

on UpdateiPod(thePlaylistName, theDate)
	set itunes_active to false
	tell application "System Events"
		if (get name of every process) contains "iTunes" then set itunes_active to true
	end tell
	
	set errMsg to {iTunesIsInactive, "", 0}
	if itunes_active is true then
		set out to {}
		set errMsg to {iTunesError, "No Matching Tracks" as Unicode text, 0}
		tell application "iTunes"
			-- try the iPod source first, if that fails we'll fall back to the main library
			set allSources to (get every source whose kind is iPod) & (get every source whose kind is library)
			with timeout of 60 seconds
				repeat with theSource in allSources
					tell theSource
						set mytracks to {}
						
						try
							set thePlaylist to the first item in (every user playlist whose name is thePlaylistName)
							if the visible of thePlaylist is true and the smart of thePlaylist is true then
								tell thePlaylist
									try
										set mytracks to get (every track whose played date is greater than theDate)
									on error errDescription number errnum
										set errMsg to {iTunesError, ("(" & name of theSource & ", " & name of thePlaylist & ") " & errDescription) as Unicode text, errnum}
									end try
								end tell
							else
								set errMsg to {iTunesError, ("Playlist: " & thePlaylistName & "cannot be used") as Unicode text, 0}
							end if
						on error errDescription number errnum
							set errMsg to {iTunesError, ("(" & name of theSource & ", " & thePlaylistName & ") " & errDescription) as Unicode text, errnum}
						end try
						
						repeat with theTrack in mytracks
							set trackClass to (get class of theTrack)
							if trackClass is file track then
								set trackID to database ID of theTrack
								set playlistID to index of the container of theTrack
								set songTitle to name of theTrack as Unicode text
								set songLength to duration of theTrack
								set songPosition to 0 -- the song has already played, so player pos will not be returned 
								set songArtist to artist of theTrack as Unicode text
								try
									set songLocation to POSIX path of ((location of theTrack) as Unicode text)
								on error
									set songLocation to ""
								end try
								set songAlbum to album of theTrack as Unicode text
								set songLastPlayed to played date of theTrack
								set songRating to rating of theTrack
								set trackInfo to {trackID, playlistID, songTitle, songLength, songPosition, songArtist, songLocation, songAlbum, songLastPlayed, songRating}
								set out to out & {trackInfo}
							end if
						end repeat
						
						if out is not {} then
							-- we retrieved some songs from the playlist, no need to check alternate sources
							return out
						end if
					end tell
				end repeat
			end timeout
		end tell
		
		if out is not {} then
			return out
		else
			return {errMsg}
		end if
		
	end if
end UpdateiPod

-- for testing in ScriptEditor
on run
	set when to date "Saturday, April 9, 2005 9:00:00 PM"
	UpdateiPod("Top Artists", when)
end run
