global itunes_active
set itunes_active to false

tell application "System Events"
	if (get name of every process) contains "iTunes" then set itunes_active to true
end tell

if itunes_active is true then
	tell application "iTunes"
		
		set allLists to get playlists
		set out to ""
		
		repeat with theList in allLists
			set listName to name of theList
			set listClass to class of theList
			if (listClass is user playlist and visible of theList is true and smart of theList is true) then
				set out to (out & listName & "$$$")
			end if
		end repeat
		return out
	end tell
end if

if itunes_active is false then return "INACTIVE"