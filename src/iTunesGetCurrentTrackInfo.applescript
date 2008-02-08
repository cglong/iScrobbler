-- TrackType_t enum in SongData.h
property trackTypeUnknown : 0
property trackTypeFile : 1
property trackTypeShared : 2
property trackTypeRadio : 3

set trackType to trackTypeUnknown
set trackPostion to -1
set trackID to -1
set trackRating to 0
set trackPlaylistID to -1
set trackSource to ""
set trackLastPlayed to current date
set trackPodcast to 0
set trackComment to ""
set trackPlayCount to 0
set trackPersistentID to ""
--set emtpyTrackInfo to {trackType, trackID, trackPostion, trackRating, trackLastPlayed, trackPlaylistID, trackSource}


tell application "iTunes"
	try
		-- for debugging
		--set theTrack to item 1 of the selection of browser window 1
		
		set theTrack to get current track
		
		set trackClass to (get class of theTrack)
		if trackClass is file track or trackClass is audio CD track then
			set trackType to trackTypeFile
		else
			-- device track is for a portable player (iPod) -- we treat it as a shared track since
			-- the file will not usually be directly accessible
			if trackClass is shared track or trackClass is device track then
				set trackType to trackTypeShared
			else
				if trackClass is URL track then
					--set trackType to trackTypeRadio
					set trackType to trackTypeShared
				end if
			end if
		end if
		
		try
			set trackID to database ID of theTrack
		end try
		set trackPostion to player position
		try
			set trackRating to rating of theTrack
		end try
		try
			-- iTunes 7.4+ only
			if rating kind of theTrack is equal to computed then
				set trackRating to 0
			end if
		end try
		try
			set trackLastPlayed to played date
		end try
		set trackPlaylistID to index of the container of theTrack
		set trackSource to name of the container of the container of theTrack as Unicode text
		try
			if podcast of theTrack is true then
				set trackPodcast to 1
			end if
		end try
		try
			set trackComment to comment of theTrack
		end try
		if (played count of theTrack is not missing value) then
			set trackPlayCount to played count of theTrack
		end if
		try
			set trackPersistentID to persistent ID of theTrack
		end try
	end try
	
end tell

set trackInfo to {trackType, trackID, trackPostion, trackRating, trackLastPlayed, trackPlaylistID, trackSource, trackPodcast, trackComment, trackPlayCount, trackPersistentID}
return trackInfo
