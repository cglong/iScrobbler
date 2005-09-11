on GetArtwork(theSource, theArtist, theAlbum)
	tell application "iTunes"
		tell source theSource
			-- just use any master lists in the source and don't worry about thePlaylistID
			set thePlaylists to (every library playlist)
			with timeout of 20 seconds
				repeat with pl in thePlaylists
					tell pl
						try
						if theAlbum is not "" then
							set albumTracks to (search pl for theAlbum only albums)
							if albumTracks is not {} then
								repeat with myTrack in albumTracks	
																if theArtist is (the artist of myTrack) and exists ( artworks of myTrack) then
										return get data of artwork 1 of myTrack
									end if
								end repeat
							end if
						end if
						end try
			end tell
				end repeat
			end timeout
		end tell
	end tell
end GetArtwork

-- for testing within script editor
on run
	tell application "iTunes"
		set ct to current track
		set theTrackID to database ID of ct
		set theAlbum to album of ct
		set playlistid to index of the container of ct
		set theArtist to the artist of ct
	end tell
	set starttime to current date
	set theresult to my GetArtwork("Library", theArtist, theAlbum)
	log "run time: " & ((current date) - starttime) & " seconds."
end run
