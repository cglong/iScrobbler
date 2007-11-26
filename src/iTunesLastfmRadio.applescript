on EmptyRadioPlaylst(targetPlaylist)
	tell application "iTunes"
		tell source "Library"
			set allPlaylists to (every user playlist whose name is targetPlaylist)
			if allPlaylists is not {} then
				set radioPlaylist to the first item of allPlaylists
				set allTracks to every track in radioPlaylist
				repeat with theTrack in allTracks
					tell radioPlaylist to delete theTrack
				end repeat
			end if
		end tell
	end tell
end EmptyRadioPlaylst

on RemoveRadioTrack(targetPlaylist, trackPersistentID)
	tell application "iTunes"
		tell source "Library"
			set allPlaylists to (every user playlist whose name is targetPlaylist)
			if allPlaylists is not {} then
				set radioPlaylist to the first item of allPlaylists
				tell radioPlaylist
					set theTrack to the first item of (every track whose persistent ID is trackPersistentID)
					delete theTrack
				end tell
			end if
		end tell
	end tell
end RemoveRadioTrack

on PlayNextRadioTrack(targetPlaylist)
	tell application "iTunes"
		-- 'next track' is only at the app level and operates on the current playlist; make sure we are current
		if the name of the current playlist is equal to targetPlaylist then
			next track
		else
			pause
		end if
		set isPlaying to player state is equal to playing
		return isPlaying
	end tell
end PlayNextRadioTrack

on PlayRadioPlaylist(targetPlaylist)
	tell application "iTunes"
		tell source "Library"
			set allPlaylists to (every user playlist whose name is targetPlaylist)
			if allPlaylists is not {} then
				set radioPlaylist to the first item of allPlaylists
				set allTracks to (every track in radioPlaylist)
				if allTracks is not {} then
					play the first item in allTracks
				end if
			end if
		end tell
		set isPlaying to player state is equal to playing
		return isPlaying
	end tell
end PlayRadioPlaylist

on AddRadioTrack(targetPlaylist, trackName, trackArtist, trackAlbum, trackURL, m3ufile)
	tell application "iTunes"
		tell source "Library"
			
			set allPlaylists to (every user playlist whose name is targetPlaylist)
			if allPlaylists is not {} then
				set radioPlaylist to the first item of allPlaylists
			else
				set radioPlaylist to make user playlist with properties {name:targetPlaylist, shuffle:false, smart:false, visible:false, song repeat:off}
			end if
			
			add (m3ufile as POSIX file as alias) to radioPlaylist
			
			tell radioPlaylist
				set newTrack to the first item of (every URL track whose address is trackURL)
				set artist of newTrack to trackArtist
				if trackAlbum is not "" then
					set album of newTrack to trackAlbum
				end if
				-- iScrobbler uses this to detect a radio track
				set genre of newTrack to "[last.fm]"
			end tell
			
			return persistent ID of newTrack
			
		end tell
	end tell
end AddRadioTrack

on RemoveRadioPlayList(targetPlaylist)
	tell application "iTunes"
		tell source "Library"
			set allPlaylists to (every user playlist whose name is targetPlaylist)
			if allPlaylists is not {} then
				set radioPlaylist to the first item of allPlaylists
				tell the container of radioPlaylist
					delete radioPlaylist
				end tell
			end if
		end tell
	end tell
end RemoveRadioPlayList

on GetPositionOfTrack(trackPersistentID)
	tell application "iTunes"
		set elapsedTime to -1
		if the persistent ID of the current track is equal to trackPersistentID then
			set elapsedTime to player position
		end if
		return elapsedTime
	end tell
end GetPositionOfTrack

on GetPersistentIDOfCurrentTrack()
	tell application "iTunes"
		return persistent ID of the current track
	end tell
end GetPersistentIDOfCurrentTrack

(*
-- testing
on run
	EmptyRadioPlaylst("iScrobbler Radio")
	
	set theFile to "/Users/brian/Desktop/test test.m3u"
	AddRadioTrack("iScrobbler Radio", "Living Dead Girl", "Rob Zombie", "Hellbilly Deluxe", "http://play.last.fm/user/e7c6219b87c03a7f27df36dc4806ac82.mp3", theFile)
end run
*)
