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
--set emtpyTrackInfo to {trackType, trackID, trackPostion, trackRating, trackLastPlayed, trackPlaylistID, trackSource}


tell application "iTunes"
	--try
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
				set trackType to trackTypeRadio
			end if
		end if
	end if
	
	set trackID to database ID of theTrack
	set trackPostion to player position
	try
		set trackRating to rating of theTrack
	end try
	try
		set trackLastPlayed to played date
	end try
	set trackPlaylistID to index of the container of theTrack
	set trackSource to name of the container of the container of theTrack as Unicode text
	
end tell

set trackInfo to {trackType, trackID, trackPostion, trackRating, trackLastPlayed, trackPlaylistID, trackSource}
return trackInfo
