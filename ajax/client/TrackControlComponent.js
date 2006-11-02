// Written by Andrew Uzilov, November 2005 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//==================================================================================================


//----------------------------------------
//     CONSTRUCTORS AND INITIALIZERS
//----------------------------------------

function TrackControlComponent () {

    /* set up track control buttons */

    // TODO: this should be added to DOM dynamically instead of getting it from XHTML
    this.trackControls = document.getElementById('trackControls');  // track control elements (buttons, or whatever may be...)

    // set up/lay out track control elements (TODO: how much should be in renderComponent()?)
    var trackNames = taz.getTrackNames();
    for (var i = 0; i < trackNames.length; i++) {
	var trackName = trackNames[i];

	var controlElement = document.createElement('button');
	controlElement.setAttribute('id', trackName + '_tracktoggle');
	controlElement.setAttribute('trackname', trackName);
	controlElement.setAttribute('class', 'trackControlElement');
	controlElement.innerHTML = trackName;
	controlElement.style.background = '#' + colorArray[i % colorArray.length];  // wrap index, so we don't run out of colors
	this.trackControls.appendChild(controlElement);
	//debug('appended ' + controlElement.innerHTML);  // D!!!
    }

    /* register event handlers */

    // event handlers (made using closures) for track control elements
    var trackNames = taz.getTrackNames();
    for (var i = 0; i < trackNames.length; i++) {
	var trackName = trackNames[i];

	document.getElementById(trackName + '_tracktoggle').onclick =
	    TrackControlComponent_makeTrackControlHandler (trackName);
    }

    // track label on/off toggle
    document.getElementById('trackLabelToggle').onclick =
	function (event) { cif.toggleTrackLabels (event); }

    // track label transparency controls
    document.getElementById('raiseTransp').onclick = TrackControlComponent_raiseTransp;
    document.getElementById('lowerTransp').onclick = TrackControlComponent_lowerTransp;

    // view height controls
    document.getElementById ('maxHeightButton').onclick = TrackControlComponent_setMaxViewHeight;
    document.getElementById ('setHeightButton').onclick = TrackControlComponent_setViewHeight;

    // FOR DEMO ONLY (and doesn't really belong here, but where else to put it?)
    // TODO: remove when done!
    document.getElementById("goToClassic").onclick = TrackControlComponent_openClassicGBrowse;

    // should add a ref to each internal accessor function to componentInterface
    // (TODO: this is not implemented yet)

    this.renderComponent = TrackControlComponent_renderComponent;
    this.getState = TrackControlComponent_getState;
    this.setState = TrackControlComponent_setState;
    this.setDisplayedViewHeight = TrackControlComponent_setDisplayedViewHeight;
}

//
// TODO: stub for constructing the DOM node for this Component; currently, things are
// more-or-less hardcoded in XHTML or in the constructor... ideally though, the Component
// should render itself based solely on info from XML and/or default values - the Load class
// will call this function, get the DOM node back, and append it to the document tree.
//
function TrackControlComponent_renderComponent () {
    // TODO: write me!

    //return domNode;
}


//-------------------
//     ACCESSORS
//-------------------

//
// TODO: stub for "return state" for bookmarking feature - every Component must implement one!
//
function TrackControlComponent_getState () {
    // not implemented yet
}


//-------------------
//     MODIFIERS
//-------------------

//
// TODO: stub for "restore state" for bookmarking feature - every Component must implement one!
//
function TrackControlComponent_setState (stateObj) {
    // not implemented yet
}

//
// Sets the value displayed in the "view height" box.
//
function TrackControlComponent_setDisplayedViewHeight (height) {
    document.getElementById ('viewHeight').value = height;
}



//------------------------
//     EVENT HANDLERS
//------------------------

//
// FOR DEMO ONLY: remove when done!
// (yes, it doesn't really belong here, but where else to stick it?)
//
function TrackControlComponent_openClassicGBrowse(event) {
    message ("Opening original GBrowse...");

    // pixels * (tiles/pixel) * (units/tile) = units

    // construct list of tracks to show - THIS DOES NOT WORK PROPERLY !!!
    var openTracksString = '';
    var openTracksArray = taz.getVisibleTrackNames();
    for (var i = 0; i < openTracksArray.length; i++)
	openTracksString = openTracksString + openTracksArray[i] + '+';

    // remove trailing '+' character
    openTracksString = openTracksString.substring(0, openTracksString.length - 1);

    //debug("open tracks are: " + openTracksString);

    window.open(cif.getClassicURL () + '?name=' + view.landmarkID + ':' + view.leftmostNt +
		'..' + view.rightmostNt);
    //		+ ';type=Transp');// + openTracksString);
}

//
// Raise/lower track label transparency.
//
// This is the most 1337 CSS I've ever done... too bad it only works in Firefox.
//
function TrackControlComponent_raiseTransp (event) {
    var trackLabelDiv = cif.getDragDivTrackLabels ();

    var currentOpacity =
	parseFloat (window.getComputedStyle (trackLabelDiv, null).opacity);

    // can't lower opacity below 0
    if (currentOpacity >= 0.1) {
	trackLabelDiv.style.opacity = currentOpacity - 0.1;
    }

    return false;
}
function TrackControlComponent_lowerTransp (event) {
    var trackLabelDiv = cif.getDragDivTrackLabels ();

    var currentOpacity =
	parseFloat (window.getComputedStyle (trackLabelDiv, null).opacity);

    // can't raise opacity above 1
    if (currentOpacity <= 0.9) {
	trackLabelDiv.style.opacity = currentOpacity + 0.1;
    }

    return false;
}

//
// Sets the view height to maximum possible (i.e. the height of all visible tracks)
//
function TrackControlComponent_setMaxViewHeight (event) {
    //debug ('setMaxViewHeight ()');

    var allTracksHeight = 0;
    taz.getVisibleTrackNames ().each
	(function (trackName) {
	    allTracksHeight += taz.getHeightOfTrack (trackName);
	});
    cif.setMaxHeight (true);  // set state to "maximally display all visible tracks"
    cif.setViewHeight (allTracksHeight);  // MUST go after you change state!

    return false;
}

//
// Sets the view height to whatever is specified in the view height box.
//
function TrackControlComponent_setViewHeight (event) {
    //debug ('setViewHeight ()');

    var newHeight = document.getElementById ('viewHeight').value;
    var newHeightInt = parseInt (newHeight, 10);

    if ((newHeight != newHeightInt) || (newHeightInt < 0)) {
	message ('Invalid view height specified: ' + newHeight + ' px');
	// TODO: should I clear the box?  return to old value?  do nothing?
    }
    else {
	cif.setMaxHeight (false);  // set state to "use view height bound for tracks display"
	cif.setViewHeight (newHeightInt);  // MUST go after you change state!
    }

    return false;
}

//-------------------------
//     OTHER FUNCTIONS
//-------------------------

//
// Closure to construct event handler for track control buttons.
//
function TrackControlComponent_makeTrackControlHandler(trackName) {
    //debug ('making closure for track ' + trackName);

    return function () { 
	var button = document.getElementById (trackName + '_tracktoggle');

	// hide/show toggle
	if (taz.isTrackVisible (trackName)) {
	    cif.hideTrack (trackName);

	    // change button color to show the track is hidden
	    button.style.color = 'red';  // TODO: hardcode alert! should use CSS
	}
	else {
	    cif.showTrack (trackName);

	    // change button color to show the track is visible
	    button.style.color = '#FFFFFF';  // TODO: hardcode alert! should use CSS
	}
    }
}
