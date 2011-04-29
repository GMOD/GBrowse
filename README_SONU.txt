Gbrowse 2 Readme File 
Date  : Apr 29/2011
Author: Sonu Lall
Topics: -Ipad touch compatibility
	-Favorites dev
	-Snapshots dev


1) Ipad Touch Compatibility 
  -needed to get Gbrowse 2 to work with the Ipad
	-foundation was simply to patch scriptaculous with the touch events
	-Everything works fine, is currently released, no current bugs


2) Favorites Development
  -user clicks star,
  -javascript toggles image between blank and yellow -- triggers ajax request
  -ajax request calls perl action which adds a hash to the current settings containing a list of the favorites
  -Again, working well, currently released 



3) Snapshots Development
  Incomplete

What works?
  -User can click the save session button
      -small prompt window will fade in 
	  -THIS IS NOT A POP UP
	  -simply a div which becomes visibile with a fade in effect
  -User can input name and name goes to hash inside the snapshot properly called 'snapshots'
  -Name will be inputed when the user presses enter -- more intuitive
  -Snapshots are also displayed nicely in the Saved Snapshots tab
  -Snapshots have timestamps in [GMT] 
  -User can drag and sort the snapshots in the table
  -User can delete snapshots from the table 
  -If the user enters a blank name, it does not get saved to the server

What needs work?
  -Have an error check for when the user inputs the name of the snapshots 
      -no blanks, special characters, etc
  -Right now, the entire page will refresh everytime a new snapshot is saved
      -instead, it should only refresh the small div that contains the table asynchronously 
  -The user should be able to click on the headings of each column and sort that column 
  -Each snapshot should have a small thumbnail which contains a screen shot of that snapshot
      -currently, there is a placeholder
  -When the user actually selects a snapshots, it should not refresh the page, instead Gbrowse should
    go back to the 'Browser' tab and show that snapshot's information 
      -in other words, a partial refresh done asynchronously
  -User should be able to send snapshots to people and conversly load snapshots sent by other people

  


