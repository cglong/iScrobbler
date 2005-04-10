on GetArtwork(theSource, thePlaylistID, theTrackID)
	tell application "iTunes"
		tell source theSource
			-- We want to try the given playlist first
			set myPlaylist to ""
			try
				set myPlaylist to first item in (every playlist whose index is thePlaylistID)
			end try
			-- if that fails, then fall back to any master lists in the source
			set thePlaylists to {myPlaylist} & (every library playlist)
			with timeout of 20 seconds
				repeat with pl in thePlaylists
					tell pl
						try
							set theTrack to first item in (every track whose database ID is theTrackID)
							if exists artworks of theTrack then
								return get data of artwork 1 of theTrack
							else
								-- search other album tracks
								set theAlbum to album of theTrack
								set theArtist to artist of theTrack
								set albumTracks to (search pl for theAlbum only albums)
								if albumTracks is not {} then
									repeat with theTrack in albumTracks
										if theArtist is (get artist of theTrack) then
											if exists artworks of theTrack then
												return get data of artwork 1 of theTrack
											end if
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
	return GetArtwork("Library", 3, 3099)
end run
