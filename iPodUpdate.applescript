global itunes_active
set itunes_active to false

tell application "System Events"
	if (get name of every process) contains "iTunes" then set itunes_active to true
end tell

if itunes_active is true then
	tell application "iTunes"
		set myPlaylist to "Recently Played" -- Do not change. This will be replaced with the user chosen playlist while iScrobbler is running.
		try
			-- Do NOT change the date on the next line. It is used as a placeholder that will be changed while iScrobbler is running.
			set mytracks to get tracks of user playlist myPlaylist whose played date is greater than date "Thursday, January 1, 1970 12:00:00 AM"
		on error errmsg number errnum
			return "ERROR" & "$$$" & errmsg & "$$$" & (errnum as text)
		end try
		
		set out to ""
		repeat with theTrack in mytracks
			set trackClass to (get class of theTrack)
			if trackClass is file track then
				set trackIndex to index of theTrack
				set playlistIndex to index of the container of theTrack
				set songTitle to name of theTrack as Unicode text
				set songLength to duration of theTrack as Unicode text
				set songPosition to "0" (* player position as Unicode text // the song has already played, so player pos will not be returned *)
				set songArtist to artist of theTrack as Unicode text
				-- We don't currently do anything with the path, and this is causing execution errors for some people.
				-- E.G: "Can't make alias "System:Users:murraysteele:Music:iTunes:iTunes Music:The Go! Team:Thunder, Lightning, Strike:11 Everyone?s A V.I.P To Someone.m4a" into a string.";
				-- There's also been an error reported because of a bad link in the iTunes DB that causes alias creation to fail
				--set songLocation to location of theTrack as Unicode text
				set songLocation to "File Track" -- Don't rely on "File Track" in iScrobbler proper
				set songAlbum to album of theTrack as Unicode text
				set songLastPlayed to played date of theTrack as Unicode text
				set songRating to rating of theTrack as Unicode text
				set out to (out & ((trackIndex as Unicode text) & "***" & (playlistIndex as Unicode text) & "***" & songTitle & "***" & songLength & "***" & songPosition & "***" & songArtist & "***" & songAlbum & "***" & songLocation & "***" & songLastPlayed & "***" & songRating) as Unicode text) & "$$$"
			end if
		end repeat
		return out
	end tell
end if

if itunes_active is false then return "INACTIVE"