-- syncIpod enum
property iTunesIsInactive : -1
property iTunesError : -2

on UpdateiPod(thePlaylistName, theDate)
	set itunes_active to true
	(*
	tell application "System Events"
		if (get name of every process) contains "iTunes" then set itunes_active to true
	end tell
	*)
	set sourceIsiTunes to false
	set errMsg to {iTunesIsInactive, "", 0}
	if itunes_active is true then
		set out to {}
		set errMsg to {iTunesError, "No Matching Source" as Unicode text, 0}
		tell application "iTunes"
			with timeout of 60 seconds
				set iTunesVer to version as string
				-- try the iTunes library first, if that fails we'll fall back to the iPod (for manual users)
				set allSources to (get every source whose kind is library) & (get every source whose kind is iPod)
				repeat with theSource in allSources
					tell theSource
						set mytracks to {}
						set errMsg to {iTunesError, "No Matching Tracks" as Unicode text, 0}
						set theSourceName to ("Unknown Source" as Unicode text)
						try
							set theSourceName to (name of theSource as Unicode text)
						end try
						
						set thePlaylist to null
						try
							set thePlaylist to the first item in (every user playlist whose name is thePlaylistName)
						on error
							set errMsg to {iTunesError, "Playlist not found in source " & theSourceName as Unicode text, 0}
						end try
						if thePlaylist is not null then
							try
								--This simple statement to get the playlist breaks when run from a 64bit app with: "iTunes got an error: Illegal logical operator called." (-1725)
								--set thePlaylist to the first item in (every user playlist whose name is thePlaylistName and smart is true)
								-- we'll just ignore the smart property, as it's enforced by the GUI
								tell thePlaylist
									(*The "whose played date" clause will cause a -10001 "type mismatch" error if
										any track in the chosen playlist has not been played yet. This is because iTunes
										apparently can't handle comparing a date type to a missing value internally.*)
									set mytracks to get (every file track whose played date is greater than theDate)
									-- 10.5 64-bit bug: greater than acts as less than and less than gives a -10001 error, WTF!
								end tell
							on error errDescription number errnum
								set errMsg to {iTunesError, ("(" & theSourceName & ", " & thePlaylistName & ") " & errDescription) as Unicode text, errnum}
							end try
						end if
						
						repeat with theTrack in mytracks
							set trackID to database ID of theTrack
							set playlistid to index of the container of theTrack
							set songTitle to name of theTrack as Unicode text
							-- iTunes 7 changed the song duration to a real number which broke all iPod submissions
							-- on eariler versions we'll be converting to a real and rounding just to get back to an integer
							try
								set songLength to (round (duration of theTrack as real) rounding down) as integer
							on error errDescription number errnum
								set songLength to 0
							end try
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
							try
								-- iTunes 7.4+ only
								if rating kind of theTrack is equal to computed then
									set songRating to 0
								end if
							end try
							set songGenre to ""
							if genre of theTrack is not missing value then
								set songGenre to genre of theTrack as Unicode text
							end if
							set trackPodcast to 0
							try
								if podcast of theTrack is true then
									set trackPodcast to 1
								end if
							end try
							set trackComment to ""
							try
								set trackComment to comment of theTrack
							end try
							try
								set trackNumber to track number of theTrack
							on error
								set trackNumber to 0
							end try
							if (played count of theTrack is not missing value) then
								set trackPlayCount to played count of theTrack
							else
								set trackPlayCount to 0
							end if
							try
								set trackPersistentID to persistent ID of theTrack
							on error
								set trackPersistentID to ""
							end try
							try
								set trackYear to year of theTrack
							on error
								set trackYear to 0
							end try
							
							-- if you add/remove members, make sure to update IPOD_SYNC_VALUE_COUNT in iScrobblerController+Private.m
							set trackInfo to {trackID, playlistid, songTitle, songLength, songPosition, songArtist, songLocation, songAlbum, songLastPlayed, songRating, songGenre, trackPodcast, trackComment, trackNumber, trackPlayCount, trackPersistentID, trackYear}
							set out to out & {trackInfo}
						end repeat
						
						if out is not {} then
							if the kind of theSource is library then
								set sourceIsiTunes to true
							end if
							exit repeat -- we retrieved some songs from the playlist, no need to check alternate sources
						end if
					end tell
				end repeat
			end timeout
		end tell
		
		if out is not {} then
			return {{sourceIsiTunes, iTunesVer}} & out
		else
			return {errMsg}
		end if
		
	end if
end UpdateiPod

-- for testing in ScriptEditor
on run
	set when to date "Monday, June 9, 2008 1:00:00 AM"
	UpdateiPod("Recently Played" as Unicode text, when)
end run
