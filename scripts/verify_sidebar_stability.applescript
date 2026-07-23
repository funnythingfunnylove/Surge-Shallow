set destinationRows to {2, 3, 4, 5, 6, 7, 9}
set originalRow to 2

tell application "System Events"
    tell first application process whose bundle identifier is "com.surgeprofilerelay.app"
        set appWindow to missing value
        repeat with candidateWindow in windows
            try
                if value of attribute "AXSubrole" of candidateWindow is "AXStandardWindow" then
                    set appWindow to candidateWindow
                    exit repeat
                end if
            end try
        end repeat
        if appWindow is missing value then error "Surge Shallow standard window not found"

        tell outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of appWindow
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

                set value of attribute "AXSelected" of row 3 to true
                delay 0.4
                set sourcesSplitterPosition to position of splitter 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of appWindow
                set sourcesSplitterX to item 1 of sourcesSplitterPosition

                set value of attribute "AXSelected" of row 6 to true
                delay 0.4
                set modulesSplitterPosition to position of splitter 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of appWindow
                set modulesSplitterX to item 1 of modulesSplitterPosition

                if modulesSplitterX is not sourcesSplitterX then
                    error "management detail split shifted from x=" & sourcesSplitterX & " to x=" & modulesSplitterX & " after selecting Modules"
                end if
            on error errorMessage number errorNumber
                set value of attribute "AXSelected" of row originalRow to true
                error errorMessage number errorNumber
            end try

            set value of attribute "AXSelected" of row originalRow to true
        end tell
    end tell
end tell

return "management tabs stable: sidebar x=" & baselineX & ", detail split x=" & sourcesSplitterX
