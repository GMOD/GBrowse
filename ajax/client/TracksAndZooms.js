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
//   - the offset of each track from top of inner div;
//   - [TODO: what else?]
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
// - A lot of this crap should be pulled, or replaced with getting state info directy from the DOM
//   itself.  E.g., why isn't track ordering done this way?
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
function TracksAndZooms(xmlDoc) {

    // save a ref to the XML document for whoever wants it... JUST in case...
    this.xmlDoc = xmlDoc;

    // tile width in pixels
    this.tileWidth = parseInt (xmlDoc.getElementsByTagName('tile')[0].getAttribute('width'), 10);

    // get ruler info
    this.rulerCellHeight = parseInt (xmlDoc.getElementsByTagName("ruler")[0].getAttribute("height"), 10);
    this.rulerTilePath = xmlDoc.getElementsByTagName("ruler")[0].getAttribute("tiledir");   // path of the zoom level directories

    // Convert XML track and zoom level info to internal data structures

    var trackNodes = xmlDoc.getElementsByTagName('tracks')[0].getElementsByTagName('track');

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

// TODO:
// - Are the methods for returning hidden/visible tracks necessary?  Can't I just bypass them by
//   getting all the children of innerDivMain (that is, the track divs) for visible tracks, and
//   stuff stored in ViewerComponent.hiddenTrackDivs?

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
// Moves a track to the specified position, and adjusts the track order numbering and the offsets
// to compensate.
//
// This is useful anytime you want to change the track order.
//
// TODO: this needs to be rewritten... right?
//
function TracksAndZooms_moveTrack(trackName, newPosition) {
    var oldPosition = this.tracksNamed[trackName]['tracknum'];

    // Go through tracks between the old and new positions and adjust their order number and offset

    if (oldPosition < newPosition) {  // shift tracks left
	for (var i = oldPosition; i < newPosition; i++) {
	    // move track at 'i + 1' to 'i' (shift left)
	    var newTrack = tracksNumbered[i + 1];
	    tracksNumbered[i] = newTrack;
	    tracksNamed[newTrack]['tracknum'] = i;

	    // the offset needs to be lowered by the height of the moved track at each zoom level
	    for (var j in this.zoomsNumbered)
		tracksNamed[newTrack]['zoomlevels'][this.zoomsNumbered[j]]['offset'] -=
		    tracksNamed[trackName]['zoomlevels'][this.zoomsNumbered[j]]['height'];
	}
    }
    else if (oldPosition > newPosition) {  // shift tracks right
	for (var i = oldPosition; i > newPosition; i--) {
	    // move track at 'i - 1' to 'i' (shift right)
	    var newTrack = tracksNumbered[i - 1];
	    tracksNumbered[i] = newTrack;
	    tracksNamed[newTrack]['tracknum'] = i;

	    // the offset needs to be raised by the height of the moved track at each zoom level
	    for (var j in this.zoomsNumbered)
		tracksNamed[newTrack]['zoomlevels'][this.zoomsNumbered[j]]['offset'] +=
		    tracksNamed[trackName]['zoomlevels'][this.zoomsNumbered[j]]['height'];
	}
    }

    // put the moved track in its final place
    tracksNumbered[newPosition] = trackName;
    tracksNamed[trackName]['tracknum'] = newPosition;

    // the offset needs to be adjusted for each zoom level;
    if (newPosition == 0) {
	// first track, offset is always 0
	for (var i in this.zoomsNumbered)
	    tracksNamed[trackName]['zoomlevels'][zoomsNumbered[i]]['offset'] = 0;
    }
    else {
	// base current offset on the offset of the first track to the left (i.e. above, in the browser
	// view), plus that track's height
	for (var i in this.zoomsNumbered) {
	    var trackToLeft = tracksNamed[trackName]['tracknum'] - 1;
	    var currentZoom = zoomsNumbered[i];
	    tracksNamed[trackName]['zoomlevels'][currentZoom]['offset'] =
		tracksNamed[trackToLeft]['zoomlevels'][currentZoom]['offset'] +
		tracksNamed[trackToLeft]['zoomlevels'][currentZoom]['height'];
	}
    }
}

