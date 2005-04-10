tell application "iTunes"
	set allSources to (get every source whose kind is iPod) & (get every source whose kind is library)
	set out to {}
	with timeout of 10 seconds
		repeat with theSource in allSources
			tell theSource
				set allLists to (get every user playlist whose visible is true)
				
				repeat with theList in allLists
					set listName to name of theList as Unicode text
					-- the "does not contain" constraint makes sure we don't add dup playlists (from iTunes)
					if (smart of theList is true and out does not contain listName) then
						set out to out & {listName}
					end if
				end repeat
			end tell
		end repeat
	end timeout
	return out
end tell
