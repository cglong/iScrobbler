global itunes_active
set itunes_active to false

tell application "Finder"
	if (get name of every process) contains "iTunes" then set itunes_active to true
end tell

if itunes_active is true then
	tell application "iTunes"
		if player state is playing then
			set theTrack to get current track
			if (get class of theTrack) is URL track then
				return "RADIO"
			end if
			set trackIndex to index of theTrack
			set playlistIndex to index of the container of theTrack
			set songTitle to name of theTrack as string
			set songLength to duration of theTrack as string
			set songPosition to player position as string
			set songArtist to artist of theTrack as string
			set songLocation to location of theTrack as string
			set songAlbum to album of theTrack as string
			return ((trackIndex as string) & "***" & (playlistIndex as string) & "***" & songTitle & "***" & songLength & "***" & songPosition & "***" & songArtist & "***" & songAlbum & "***" & songLocation) as string
		end if
		return "NOT PLAYING"
	end tell
end if

if itunes_active is false then return "INACTIVE"