on GetArtwork(theSource, theArtist, theAlbum)
	set itunesActive to false
	tell application "System Events"
		if (get name of every process) contains "iTunes" then set itunesActive to true
	end tell
	
	if itunesActive is true then
		tell application "iTunes"
			if theSource is "" then
				try
					set theSource to name of the container of the current playlist as Unicode text
				end try
			end if
			tell source theSource
				-- just use any master list in the source
				set thePlaylists to (every library playlist)
				with timeout of 20 seconds
					repeat with pl in thePlaylists
						tell pl
							try
								if theAlbum is not "" then
									set albumTracks to (search pl for theAlbum only albums)
									if albumTracks is not {} then
										repeat with myTrack in albumTracks
											-- We have to check the artist because multiple artists can have the same album name (how many "Greatest Hits" are there?)
											-- We have to check the album because search is not an exact match. e.g
											-- Artist: Under the Sun Album: Under the Sun
											-- Artist: Under the Sun Album: Schematism: On Stage with Under The Sun
											-- Searching for tracks from the album "Under the Sun" will also return the tracks from "Schematism"
											if theAlbum is (the album of myTrack) and theArtist is (the artist of myTrack) and (exists (artworks of myTrack)) then
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
	end if
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
	set theresult to my GetArtwork("", theArtist, theAlbum)
	log "run time: " & ((current date) - starttime) & " seconds."
end run
