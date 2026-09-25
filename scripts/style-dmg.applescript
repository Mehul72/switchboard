on run arguments
    set mountPath to item 1 of arguments
    set imageFolder to POSIX file mountPath as alias
    set backgroundFile to POSIX file (mountPath & "/.background/installer.tiff") as alias

    with timeout of 60 seconds
        tell application "Finder"
            set imageFolder to item imageFolder
            open imageFolder
            tell container window of imageFolder
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set pathbar visible to false
                set bounds to {120, 80, 920, 648}
            end tell
            set viewOptions to icon view options of container window of imageFolder
            tell viewOptions
                set arrangement to not arranged
                set icon size to 108
                set text size to 13
                set label position to bottom
                set shows item info to false
                set shows icon preview to false
                set background picture to backgroundFile
            end tell
            close container window of imageFolder
            open imageFolder
            delay 1
            set bounds of container window of imageFolder to {120, 80, 921, 649}
            set bounds of container window of imageFolder to {120, 80, 920, 648}
            tell imageFolder
                -- Background assets stay out of the composition even when hidden files are shown.
                set position of every item to {1100, 100}
                set position of item "Switchboard.app" to {220, 336}
                set extension hidden of item "Switchboard.app" to true
                set position of item "Applications" to {580, 336}
            end tell
            update imageFolder without registering applications
            delay 2
            close container window of imageFolder
        end tell
    end timeout
end run
