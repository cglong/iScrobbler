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
		set errMsg to {iTunesError, "No Matching Source" as Unicode text, 0}
		tell application "iTunes"
			-- try the iTunes library first, if that fails we'll fall back to the iPod (for manual users)
			set allSources to (get every source whose kind is library) & (get every source whose kind is iPod)
			with timeout of 60 seconds
				repeat with theSource in allSources
					tell theSource
						set mytracks to {}
						set errMsg to {iTunesError, "No Matching Tracks" as Unicode text, 0}
						set theSourceName to ("Unknown Source" as Unicode text)
						try
							set theSourceName to (name of theSource as Unicode text)
						end try
						
						try
							if the name of every user playlist contains thePlaylistName then
								set thePlaylist to the first item in (every user playlist whose name is thePlaylistName and visible is true and smart is true)
								tell thePlaylist
									try
										(*The "whose played date" clause will cause a -10001 "type mismatch" error if
										any track in the chosen playlist has not been played yet. This is because iTunes
										apparently can't handle comparing a date type to a missing value internally.*)
										set mytracks to get (every file track whose played date is greater than theDate)
									on error errDescription number errnum
										set errMsg to {iTunesError, ("(" & theSourceName & ", " & thePlaylistName & ") " & errDescription) as Unicode text, errnum}
									end try
								end tell
							end if
						on error errDescription number errnum
							set errMsg to {iTunesError, ("(" & theSourceName & ", " & thePlaylistName & ") " & errDescription) as Unicode text, errnum}
						end try
						
						repeat with theTrack in mytracks
							set trackID to database ID of theTrack
							set playlistID to index of the container of theTrack
							set songTitle to name of theTrack as Unicode text
							set songLength to duration of theTrack
							set songPosition to 0 -- the song has already played, so player pos will not be returned 
							set songArtist to artist of theTrack as Unicode text
							set songLocation to ""
							try
								if location of theTrack is not missing value then
									set songLocation to POSIX path of ((location of theTrack) as Unicode text)
								end if
							end try
							set songAlbum to album of theTrack as Unicode text
							set songLastPlayed to played date of theTrack
							set songRating to rating of theTrack
							set songGenre to ""
							if genre of theTrack is not missing value then
								set songGenre to genre of theTrack as Unicode text
							end if
							-- if you add/remove members, make sure to update IPOD_SYNC_VALUE_COUNT in iScrobblerController+Private.m
                        set trackInfo to {trackID, playlistID, songTitle, songLength, songPosition, songArtist, songLocation, songAlbum, songLastPlayed, songRating, songGenre}
							set out to out & {trackInfo}
						end repeat
						
						if out is not {} then
							exit repeat -- we retrieved some songs from the playlist, no need to check alternate sources
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
	set when to date "Thursday, June 2, 2005 1:30:00 PM"
	UpdateiPod("Recently Played" as Unicode text, when)
end run
