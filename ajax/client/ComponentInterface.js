// Written by Andrew Uzilov, September 2006 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA


//---------------------
//     CONSTRUCTOR
//---------------------
//
// TODO: what should go in here?...
//
function ComponentInterface () {

    this.createRefs = ComponentInterface_createRefs;  // TEMPORARY FIX !!!
    this.addAccessor = ComponentInterface_addAccessor;
}


//------------------------
//     OTHER FUNCTIONS
//------------------------

//
// Create references to all the Component accessors... TODO: this is a TEMPORARY solution, as this
// kind of thing should be done automatically.
//
function ComponentInterface_createRefs () {

    /* ViewerComponent */

    // STUFF THAT SHOULD GO AWAY EVENTUALLY (XXX):
    this.getClassicURL = function () { return this.viewerComponent.classicURL; };

    // accessors for object properties
    //
    // TODO: it would be more robust to build these by iterating over object properties and making closures
    // for the accessors, but... I can't get closures to work right in JavaScript (dagnab it)

    this.getAbsLeft = function () { return this.viewerComponent.absLeft; };
    this.getAbsRight = function () { return this.viewerComponent.absRight; };
    this.areTrackLabelsOn = function () { return this.viewerComponent.trackLabelsOn; };

    this.getOuterDivRuler = function () { return this.viewerComponent.outerDivRuler; };
    this.getOuterDivPanel = function () { return this.viewerComponent.outerDivPanel; };
    this.getOuterDivMain = function () { return this.viewerComponent.outerDivMain; };

    this.getDragDivTrackLabels = function () { return this.viewerComponent.dragDivTrackLabels; };

    // object methods...

    // ...that are event handlers
    this.resizeBrowser = function (event) { this.viewerComponent.resizeBrowser (event); };
    this.centerView = function (event) { this.viewerComponent.centerView (event); };

    // ...that set values
    this.updateHorizontal = function (motionType, deltaX) {
	this.viewerComponent.updateHorizontal (motionType, deltaX);
    };
    this.setAbsLeft =
	function (newAbsLeft) { this.viewerComponent.absLeft = newAbsLeft; };  /* for use by ViewerComponent
										  globals and debugging only! */
    this.setViewHeight =
	function (newHeightPx) { this.viewerComponent.setViewHeight (newHeightPx); };
    this.setMaxHeight =
	function (bool) { bool ?  // "sanitize" the input
			  this.viewerComponent.maxHeight = true :
			  this.viewerComponent.maxHeight = false; };

    // ...that return values
    this.ntToPixel = 
	function (nt) { return this.viewerComponent.ntToPixel (nt); };
    this.pixelToNt = 
	function (pixelValue) { return this.viewerComponent.pixelToNt (pixelValue); };
    this.getMainWidth =
	function () { return this.viewerComponent.getMainWidth (); };

    // ...that just plain run
    this.updateVertical = function () { this.viewerComponent.updateVertical (); };
    this.updateTiles = function () { this.viewerComponent.updateTiles (); };
    this.changeZoomLevel =
	function (newZoomLevel) { this.viewerComponent.changeZoomLevel (newZoomLevel); };
    this.setCenter = function (center) { this.viewerComponent.setCenter (center); };
    this.showTrack = function (trackName) { this.viewerComponent.showTrack (trackName); };
    this.hideTrack = function (trackName) { this.viewerComponent.hideTrack (trackName); };
    this.moveTrack =
	function (trackName, newPos)
	{
	    // update track ordering data structure
	    taz.moveTrack (trackName, newPos);

	    // move the track itself, track labels, etc.
	    this.viewerComponent.moveTrack (trackName, newPos);
	    
	    // move the track button, update track control menus, etc.
	    this.trackControlComponent.moveTrack (trackName, newPos);
	    
	    message ('moved track [' + trackName + '] to position ' + newPos);
	}
    this.popupTrackLabel =
	function (trackName) { this.viewerComponent.popupTrackLabel (trackName); };
    this.unpopupTrackLabel =
	function (trackName) { this.viewerComponent.unpopupTrackLabel (trackName); };
    this.toggleTrackLabels = function () { this.viewerComponent.toggleTrackLabels (); };

    /* TrackControlComponent */

    // object methods...

    // ...that set values
    this.setDisplayedViewHeight =
	function (height) { this.trackControlComponent.setDisplayedViewHeight (height); };
}

//
// Adds an accessor reference to itself.
//
// TODO: for now this will not be implemented, but all refs will be hardcoded.
// Eventually, the Load class should add each accessor of each Component to
// this object using this function... or maybe pass the ref to Component to
// some "add all" function, and have it poll the Component?
//
function ComponentInterface_addAccessor (accessorRef) {
    // TODO: write me
    // - parse name of accessor ref
    // - add to internals
}
