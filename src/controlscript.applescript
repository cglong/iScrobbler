global itunes_active
set itunes_active to false

tell application "System Events"
	if (get name of every process) contains "iTunes" then set itunes_active to true
end tell

if itunes_active is true then
	tell application "iTunes"
		if player state is playing then
			set theTrack to get current track
			
			set trackClass to (get class of theTrack)
			if trackClass is file track or trackClass is audio CD track then
				-- We don't currently do anything with the path, and this is causing execution errors for some people.
				-- E.G: "Can't make alias "System:Users:murraysteele:Music:iTunes:iTunes Music:The Go! Team:Thunder, Lightning, Strike:11 Everyone?s A V.I.P To Someone.m4a" into a string.";
				-- There's also been an error reported because of a bad link in the iTunes DB that causes alias creation to fail
				--set songLocation to location of theTrack as Unicode text
				set songLocation to "File Track" -- Don't rely on "File Track" in iScrobbler proper
			else
				if trackClass is URL track then
					set songLocation to address of theTrack as Unicode text
					return "RADIO"
				else (* shared track *)
					-- iScrobbler uses this text to detect a Shared Track, don't change unless you change the iScrobbler code too.
					set songLocation to "Shared Track"
				end if
			end if
			
			set trackIndex to index of theTrack
			set playlistIndex to index of the container of theTrack
			set songTitle to name of theTrack as Unicode text
			set songLength to duration of theTrack as Unicode text
			set songPosition to player position as Unicode text
			set songArtist to artist of theTrack as Unicode text
			set songAlbum to album of theTrack as Unicode text
			set songLastPlayed to ""
			set songRating to rating of theTrack as Unicode text
			return ((trackIndex as Unicode text) & "***" & (playlistIndex as Unicode text) & "***" & songTitle & "***" & songLength & "***" & songPosition & "***" & songArtist & "***" & songAlbum & "***" & songLocation & "***" & songLastPlayed & "***" & songRating) as Unicode text
		end if
		return "NOT PLAYING"
	end tell
end if

if itunes_active is false then return "INACTIVE"