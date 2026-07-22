set destinationRows to {2, 3, 4, 5, 6, 8}
set originalRow to 2

tell application "System Events"
    tell first application process whose bundle identifier is "com.surgeprofilerelay.app"
        tell outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
            repeat with rowIndex in destinationRows
                if value of attribute "AXSelected" of row rowIndex is true then
                    set originalRow to rowIndex
                    exit repeat
                end if
            end repeat

            set value of attribute "AXSelected" of row 2 to true
            delay 0.4
            set baselinePosition to position of static text 1 of UI element 1 of row 2
            set baselineX to item 1 of baselinePosition

            try
                repeat with rowIndex in destinationRows
                    set value of attribute "AXSelected" of row rowIndex to true
                    delay 0.4
                    set currentPosition to position of static text 1 of UI element 1 of row 2
                    set currentX to item 1 of currentPosition
                    if currentX is not baselineX then
                        error "sidebar tabs shifted from x=" & baselineX & " to x=" & currentX & " after selecting row " & rowIndex number 1
                    end if
                end repeat
            on error errorMessage number errorNumber
                set value of attribute "AXSelected" of row originalRow to true
                error errorMessage number errorNumber
            end try

            set value of attribute "AXSelected" of row originalRow to true
        end tell
    end tell
end tell

return "sidebar tabs stable at x=" & baselineX
