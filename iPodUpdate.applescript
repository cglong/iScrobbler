global itunes_active
set itunes_active to false

tell application "Finder"
	if (get name of every process) contains "iTunes" then set itunes_active to true
end tell

if itunes_active is true then
	tell application "iTunes"
		set myPlaylist to "Recently Played"
		try
			set mytracks to get tracks of user playlist myPlaylist whose played date is greater than date "Thursday, January 1, 1970 12:00:00 AM"
		on error errmsg number errnum
			return "ERROR%%%" & errmsg & "%%%" & (errnum as text)
		end try
		
		set out to ""
		repeat with theTrack in mytracks
			if (get class of theTrack) is not URL track then
				set trackIndex to index of theTrack
				set playlistIndex to index of the container of theTrack
				set songTitle to name of theTrack as string
				set songLength to duration of theTrack as string
				set songPosition to player position as string
				set songArtist to artist of theTrack as string
				set songLocation to location of theTrack as string
				set songAlbum to album of theTrack as string
				set songLastPlayed to played date of theTrack as string
				set out to (out & ((trackIndex as string) & "***" & (playlistIndex as string) & "***" & songTitle & "***" & songLength & "***" & songPosition & "***" & songArtist & "***" & songAlbum & "***" & songLocation & "***" & songLastPlayed) as string) & "$$$"
			end if
		end repeat
		return out
	end tell
end if

if itunes_active is false then return "INACTIVE"