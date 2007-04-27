// Written by Andrew Uzilov, November 2005 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//
// This is just a collection of information about tracks and zoom levels, such as their:
//   - names;
//   - properties;
//   - visibility (visible or hidden) and order of layout (from top to bottom);
//   - tile dimensions and paths;
//
// This also provides accessor and modifier methods.
//
// An instance of this class is just a data storage collection, and thus doesn't update its state
// (i.e. any internal data members) unless explicitly told to via a modifier method.  It also does
// not execute anything (i.e. doesn't modify the DOM tree or change state of any other objects, etc.)
// So, it is UP TO THE CALLER/USER to ensure that the stuff in this collection is correct!
//
// TODO:
//
// - The 'tracksNumbered' array (to store track ordering) will become unnecessary if I ever
//   change track hiding to be done using CSS - that is, set div height to 0 to hide a track.
//   This way, tracks will never be detached/reappended to {p,o}DivMain, and the track ordering
//   would always be stored in the DOM.  The current problem that makes 'tracksNumbered'
//   necessary is that there is no way to figure out where to re-insert a hide->show track, so
//   we need to keep ordering here.  But if tracks are never detached/reappended, all ordering
//   could be maintained in the children of {p,o}DivMain (or the track label div or something).
//
// - We should make sure that zoom levels are sorted from highest to lowest, as some methods (such
//   as 'searchHandler()') depend on that ordering to work correctly.  We can't trust the XML to have
//   the correct order.


//-----------------------------------------------
//     CONSTRUCTOR FOR TracksAndZooms OBJECT
//-----------------------------------------------
//
// Initializes internal data members.  A chunk (or all?) of the data comes from the XML object
// passed in.
//
// TODO: note that there are NO SYNTAX CHECKS - should I put any in, or just assume XML is always
// correct?  Also, are we parsing the XML in a stupid way by taking the 0th item in each array
// where 'getElementsByTagName()' should return one thing? (also, should I make sure numerical values
// are actually numerical... am I too paranoid?)
//
function TracksAndZooms(config, landmark) {

    // save a ref to the config XML node for whoever wants it... JUST in case...
    this.config = config;

    // tile width in pixels
    this.tileWidth = parseInt (config.getElementsByTagName('tile')[0].getAttribute('width'), 10);

    // get ruler info
    this.rulerCellHeight = parseInt (landmark.getElementsByTagName("ruler")[0].getAttribute("height"), 10);
    this.rulerTilePath = landmark.getElementsByTagName("ruler")[0].getAttribute("tiledir");   // path of the zoom level directories

    // Convert XML track and zoom level info to internal data structures

    var trackNodes = landmark.getElementsByTagName('tracks')[0].getElementsByTagName('track');

    // load zoom level info that is the same for all tracks; it is stored in two data structures:
    //   - an associative array, indexed by zoom level name, stores:
    //       - units per tile
    //       - units per pixel
    //   - a numbered array containing zoom level names, in the order from top to bottom that they
    //     should be displayed in the zoom level selection menu
    //
    // the former should be used for indexing when you know the zoom level name and want to get its
    // properties, the latter for figuring out the proper zoom level order for layout
    //
    // TODO: this is done in a stupid way, by loading this info from the 1st track, under the
    //       assumption that they are all the same; once I change the XML format to match this
    //       data structure, this stupidity will have to be fixed

    this.zoomsNamed = {};
    this.zoomsNumbered = [];

    var zoomLevelNodes = trackNodes[0].getElementsByTagName('zoomlevel');  // TODO: change how this loads! (see above)
    for (var i = 0; i < zoomLevelNodes.length; i++) {
	var zoomLevelName = zoomLevelNodes[i].getAttribute('name');

	this.zoomsNumbered[i] = zoomLevelName;

	this.zoomsNamed[zoomLevelName] = [];
	this.zoomsNamed[zoomLevelName]['unitspertile'] = zoomLevelNodes[i].getAttribute('unitspertile');

	// (units/tile) / (pixels/tile) = units/pixel
	this.zoomsNamed[zoomLevelName]['unitsperpixel'] =
	    this.zoomsNamed[zoomLevelName]['unitspertile'] / this.tileWidth;
    }
    var zooms = this.zoomsNamed;
    this.zoomsNumbered.sort(function(a,b) {return zooms[a].unitspertile - zooms[b].unitspertile;});

    // track info is stored in two data structures:
    //   - a named (associative) array, indexed by track name, that stores:
    //       - a boolean that says whether it is visible (expanded) or not
    //       - its track number, i.e. its position in track list from top to bottom
    //       - an array of zoom levels for it, with zoom level info that is specific to the track/zoom
    //         level pair
    //   - a numbered array containing track names, in the order from top to bottom that they
    //     should be displayed
    //
    // the former should be used for indexing when you know the track name and want to get its
    // properties, the latter for figuring out the proper track order for layout

    this.tracksNamed = {};
    this.tracksNumbered = [];

    for (var i = 0; i < trackNodes.length; i++) {
	var trackName = trackNodes[i].getAttribute('name');

	this.tracksNumbered[i] = trackName;

	this.tracksNamed[trackName] = [];
	this.tracksNamed[trackName]['visible'] = true;  // TEMPORARY !!! (TODO: use the line below when show/hide is implemented in XML)
	//this.tracksNamed[trackName]['visible'] = trackNodes[i].getAttribute('visible');
	this.tracksNamed[trackName]['tracknum'] = i;
	this.tracksNamed[trackName]['zoomlevels'] = [];

	var zoomLevelNodes = trackNodes[i].getElementsByTagName('zoomlevel');  // shadows earlier declaration
	for (var j = 0; j < this.zoomsNumbered.length; j++) {
            if (j >= zoomLevelNodes.length) break;
	    var zoomLevelName = zoomLevelNodes[j].getAttribute('name');
		
	    // each zoom level has the following track-specific info stored about it in an
	    // associative array, indexed by zoom level name:
	    //   - filepath/name prefix for tile image addressing
	    //   - height of the tiles, in pixels
		
	    this.tracksNamed[trackName]['zoomlevels'][zoomLevelName] = [];
	    this.tracksNamed[trackName]['zoomlevels'][zoomLevelName]['tileprefix'] =
		zoomLevelNodes[j].getAttribute('tileprefix');

	    this.tracksNamed[trackName]['zoomlevels'][zoomLevelName]['height'] =
		parseInt (zoomLevelNodes[j].getAttribute('height'), 10);

	}  // closes zoom level iteration loop
    } // closes tracks iteration loop for visible tracks

    // Accessor methods

    // names
    this.getTrackNames        = TracksAndZooms_getTrackNames;
    this.getZoomLevelNames    = TracksAndZooms_getZoomLevelNames;

    // visibility
    this.getHiddenTrackNames  = TracksAndZooms_getHiddenTrackNames;
    this.getVisibleTrackNames = TracksAndZooms_getVisibleTrackNames;
    this.isTrackVisible       = TracksAndZooms_isTrackVisible;

    // dimensions
    this.getUnitsPerTile      = TracksAndZooms_getUnitsPerTile;
    this.getUnitsPerPixel     = TracksAndZooms_getUnitsPerPixel;
    this.getHeightOfTrack     = TracksAndZooms_getHeightOfTrack;

    // paths
    this.getTilePrefix        = TracksAndZooms_getTilePrefix;

    // Modifier methods

    // visibility
    this.setTrackHidden      = TracksAndZooms_setTrackHidden;
    this.setTrackVisible     = TracksAndZooms_setTrackVisible;

    // layout
    this.moveTrack           = TracksAndZooms_moveTrack;

    // TODO: write the following
    // - something to add/remove tracks (esp. add, if user wants to upload a track)
}


//----------------------------------------------------
//     ACCESSOR METHODS FOR TracksAndZooms OBJECT
//----------------------------------------------------

// TODO: a lot of these return the reference to the internal datastructure, but should maybe return
// a COPY instead?  Otherwise, caller can modify internal datastructure...
//
// Alternately, maybe not even care and allow access to internal data members instead?  Why wrap
// data members in accessors if they can be read directly anyway? (except maybe looks nicer to caller...)

//
// Returns an array of all the track names, in the order they should appear in the genome browser,
// from top to bottom (including hidden tracks, which go last)
//
function TracksAndZooms_getTrackNames() {
    return this.tracksNumbered;  // should copy to a separate array, and return THAT?
}

//
// Returns an array of zoom level names, in the order they appear in the zoom level selection menu,
// from top to bottom (i.e. most zoomed in to least zoomed in)
//
function TracksAndZooms_getZoomLevelNames() {
    return this.zoomsNumbered;  // should copy to a separate array, and return THAT?
}

//
// Returns an array of names of all the tracks that are hidden (collapsed) in the order they
// should appear below the visible part of genome browser, from top to bottom
//
function TracksAndZooms_getHiddenTrackNames() {
    var hiddenTrackNames = [];
    for (var i = 0; i < this.tracksNumbered.length; i++)
	if (!this.tracksNamed[this.tracksNumbered[i]]['visible'])
	    hiddenTrackNames.push(this.tracksNumbered[i]);
    
    return hiddenTrackNames;
}

//
// Returns an array of names of all the tracks that are visible (expanded) in the order they
// should appear in the genome browser, from top to bottom
//
function TracksAndZooms_getVisibleTrackNames() {
    var visibleTrackNames = [];
    for (var i = 0; i < this.tracksNumbered.length; i++)
	if (this.tracksNamed[this.tracksNumbered[i]]['visible'])
	    visibleTrackNames.push(this.tracksNumbered[i]);
    
    return visibleTrackNames;
}

//
// Returns boolean showing if a track is visible or not.
//
function TracksAndZooms_isTrackVisible(trackName) {
    return this.tracksNamed[trackName]['visible'];
}

//
// Get number of genomic units (usually bases) per tile at the current zoom level
//
function TracksAndZooms_getUnitsPerTile() {
    return this.zoomsNamed[view.currentZoomLevel]['unitspertile'];
}

//
// Get number of genomic units (usually bases) in a pixel at the current zoom level
//
function TracksAndZooms_getUnitsPerPixel() {
    return this.zoomsNamed[view.currentZoomLevel]['unitsperpixel'];
}

//
// Get height of track (in pixels) at the current zoom level
//
function TracksAndZooms_getHeightOfTrack(trackName) {
    return this.tracksNamed[trackName]['zoomlevels'][view.currentZoomLevel]['height'];
}

//
// Get filepath/name prefix for the tiles for the specified track at the current zoom level
//
function TracksAndZooms_getTilePrefix(trackName) {
    return this.tracksNamed[trackName]['zoomlevels'][view.currentZoomLevel]['tileprefix'];
}


//----------------------------------------------------
//     MODIFIER METHODS FOR TracksAndZooms OBJECT
//----------------------------------------------------

//
// Sets the boolean indicating track visibility to 'false'.
//
function TracksAndZooms_setTrackHidden(trackName) {
    this.tracksNamed[trackName]['visible'] = false;
}

//
// Sets the boolean indicating track visibility to 'true'.
//
function TracksAndZooms_setTrackVisible(trackName) {
    this.tracksNamed[trackName]['visible'] = true;
}

//
// Updates the track order numbering; ALWAYS call this BEFORE you move a track,
// as DOM-changing functions depend on this data structure being up-to-date.
// 'newPosition' is 1-based indexing, but 'tracksNamed', etc. store 0-based indexing.
//
function TracksAndZooms_moveTrack (trackName, newPosition)
{
    var oldPosition = this.tracksNamed[trackName]['tracknum'];
    newPosition--;  // convert to 0-based indexing

    // NB: updates only apply to tracks between/including oldPosition and newPosition

    if (oldPosition < newPosition)  // shift tracks left
    {
        for (var i = oldPosition; i < newPosition; i++)
        {
            var newTrack = this.tracksNumbered[i + 1];
            this.tracksNumbered[i] = newTrack;
            this.tracksNamed[newTrack]['tracknum'] = i;
        }
    }
    else if (oldPosition > newPosition)  // shift tracks right
    {
        for (var i = oldPosition; i > newPosition; i--)
        {
            var newTrack = this.tracksNumbered[i - 1];
            this.tracksNumbered[i] = newTrack;
            this.tracksNamed[newTrack]['tracknum'] = i;
        }
    }
    else { return;  /* old = new, nothing to do */ }

    // put the moved track in its final place
    this.tracksNumbered[newPosition] = trackName;
    this.tracksNamed[trackName]['tracknum'] = newPosition;
}

