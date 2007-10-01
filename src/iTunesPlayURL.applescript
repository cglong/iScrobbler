on PlayURL(theURL)
	tell application "iTunes"
		open location theURL
	end tell
end PlayURL

(*
-- for testing within script editor
on run
	PlayURL("http://ws.audioscrobbler.com/radio")
end run
*)