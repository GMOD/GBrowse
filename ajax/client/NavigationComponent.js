// Written by Andrew Uzilov, November 2005 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//==================================================================================================
// TODO and NOTES:
//
// - Should this be split into separate "navigation" and "search" components?
//==================================================================================================


//----------------------------------------
//     CONSTRUCTORS AND INITIALIZERS
//----------------------------------------

function NavigationComponent () {

    // TODO: this should be added to DOM dynamically instead of getting it from XHTML
    this.zoomLevelsMenu = document.getElementById("zoomLevelsMenu");

    document.getElementById("searchInputBox").value = '';  // reset search input box

    // zoom levels menu
    $A(this.zoomLevelsMenu.childNodes).each(function(n) {  // clear old entries first
            $('zoomLevelsMenu').removeChild(n);
        });
    var zoomLevelNames = taz.getZoomLevelNames();
    for (var i = 0; i < zoomLevelNames.length; i++) {
	var menuOption = document.createElement("option");
	menuOption.setAttribute("id", zoomLevelNames[i]);  // the id is the same as the zoom level name
	menuOption.text = zoomLevelNames[i] + " per " + taz.tileWidth + " pixels";
	// if this is the current (default) zoom level, we select it
	if (zoomLevelNames[i] === view.currentZoomLevel)
	    menuOption.defaultSelected = true;
	else 
	    menuOption.defaultSelected = false;
	this.zoomLevelsMenu.appendChild(menuOption);
    }

    // landmark-switching menu
    $A($("landmarks").childNodes).each(function(n) {  // clear old entries first
            $("landmarks").removeChild(n);
        });
    landmarks.each(function(l) {
            var menuOption = document.createElement("option");
            menuOption.setAttribute("name", l.getAttribute("id"));
            menuOption.text = l.getAttribute("id");
            menuOption.onclick = NavigationComponent_makeLandmarkHandler(l);
	    if (l.getAttribute("id") == view.landmarkID) menuOption.defaultSelected = true;
            $("landmarks").appendChild(menuOption);
        });

    /* register event handlers */

    // event handlers for search box
    document.getElementById('searchButton').onclick = NavigationComponent_searchHandler;
    // TODO: hitting 'enter' in the box should also do the search
    
    // event handlers for zoom buttons
    document.getElementById('zoomOutButton').onclick = NavigationComponent_zoomOut;
    document.getElementById('zoomInButton').onclick = NavigationComponent_zoomIn;

    // event handlers for scroll buttons
    document.getElementById('goToStartButton').onclick = NavigationComponent_scrollToStart;
    document.getElementById('scrollFarLeftButton').onclick = NavigationComponent_scrollFarLeft;
    document.getElementById('scrollNearLeftButton').onclick = NavigationComponent_scrollNearLeft;
    document.getElementById('scrollFarRightButton').onclick = NavigationComponent_scrollFarRight;
    document.getElementById('scrollNearRightButton').onclick = NavigationComponent_scrollNearRight;
    document.getElementById('goToEndButton').onclick = NavigationComponent_scrollToEnd;

    // should add a ref to each internal accessor function to componentInterface
    // (TODO: this is not implemented yet)

    this.renderComponent = NavigationComponent_renderComponent;
    this.getState = NavigationComponent_getState;
    this.setState = NavigationComponent_setState;
}


//
// TODO: stub for constructing the DOM node for this Component; currently, things are
// more-or-less hardcoded in XHTML or in the constructor... ideally though, the Component
// should render itself based solely on info from XML and/or default values - the Load class
// will call this function, get the DOM node back, and append it to the document tree.
//
function NavigationComponent_renderComponent () {
    // TODO: write me!

    // event handlers for zoom level menu
    var zoomLevelOptions = this.zoomLevelsMenu.getElementsByTagName('option');
    for (var i = 0; i < zoomLevelOptions.length; i++) {
	var zoomLevel = zoomLevelOptions[i].getAttribute('id');
	//debug("assigning handler for " + zoomLevel);  // D!!!
	zoomLevelOptions[i].onclick =
	    NavigationComponent_makeZoomHandler (zoomLevel);  // closures are fun
    }

    //return domNode;
}


//-------------------
//     ACCESSORS
//-------------------

//
// TODO: stub for "return state" for bookmarking feature - every Component must implement one!
//
function NavigationComponent_getState () {
    // not implemented yet
}


//-------------------
//     MODIFIERS
//-------------------

//
// TODO: stub for "restore state" for bookmarking feature - every Component must implement one!
//
function NavigationComponent_setState (stateObj) {
    // not implemented yet
}


//------------------------
//     EVENT HANDLERS
//------------------------

//
// Process the input in the "search" box and jump to the desired coordinates.
//
// TODO: maybe some of this code could be moved to the 'setCenter()' ('centerOnIndex()'?) or
//       'centerOnRange()' functions, which would do all the error checking; have the error handling
//       clear the box only if they return a non-error code.  This function will get bulky when more
//       search options are added - it might be easier to have it just pass the searching onto something
//       else, i.e. just figure out what to call, instead of doing the view alteration itself.
//
function NavigationComponent_searchHandler(event) {
    var input = document.getElementById('searchInputBox').value;

    // only proceed if string contains something, otherwise ignore
    if (input.match (/\S+/)) {
	if (input.match (/^\s*\d+\s*$/)) {
	    // single decimal value; try to center on it
	    var center = parseInt (input, 10);

	    // do some bounds checking
	    if ( (center >= view.landmarkStart) && (center <= view.landmarkEnd) ) {
		cif.setCenter (center);
		message ('centered view on [' + center + ']');
		document.getElementById('searchInputBox').value = '';  // clear the input box
	    }
	    else {
		message ('ERROR: Cannot center on [' + center + ']: out of landmark range [' +
			 view.landmarkStart + ',' + view.landmarkEnd + ']');
	    }
	}
	else if (input.match (/^\s*(\d+)\.\.(\d+)\s*$/)) {
	    var range = input.match (/^\s*(\d+)\.\.(\d+)\s*$/);
	    var start = parseInt (range[1], 10);  // make sure to set radix to base-10 (prevents bugs where
	    var end = parseInt (range[2], 10);    // numbers starting with 0 are interpreted as base-8)

	    // TODO: tidy up the bounds checking code in ViewerComponent.js - see the 'TODO' in file header!!!

	    if (start < end) {
		// do some bounds checking
		if ( (start >= view.landmarkStart) && (end <= view.landmarkEnd) ) {
		    // find the highest zoom level that will fit the desired range
		    var rangeSize_units = end - start + 1;
		    var outerDivWidth_px = stripPx (cif.getOuterDivMain ().style.width);

		    var zoomLevelNames = taz.getZoomLevelNames();
		    var newZoomLevel;
		    for (var i = 0; i < zoomLevelNames.length; i++) {
			// units / (units / pixel) = pixels
			var rangeSize_px = rangeSize_units / taz.getUnitsPerPixel (zoomLevelNames[i]);
			newZoomLevel = zoomLevelNames[i];
			if (rangeSize_px <= outerDivWidth_px)
			    break;  // found a zoom level that entirely fits the range
		    }

		    // change zoom level and re-center
		    cif.changeZoomLevel(newZoomLevel);
		    cif.setCenter (Math.ceil (start + rangeSize_units / 2));

		    message ('centered view on range [' + start + ',' + end + ']');
		    document.getElementById('searchInputBox').value = '';  // clear the input box
		}
		else {
		    message ('ERROR: Cannot center on [' + start + ',' + end + ']: out of landmark range [' +
			   view.landmarkStart + ',' + view.landmarkEnd + ']');
		}
	    }
	    else if (start > end) {
		// flip the view, then center

		// TODO: flipping is not yet implemented, so write this when it will be !!!

		//message ('centered view on range [' + end + ',' + start + ']');
		//document.getElementById('searchInputBox').value = '';  // clear the input box

		message ('ERROR: Cannot center on range [' + end + ',' + start + ']: ' +
			 'flipping feature is not yet implemented.');
	    }
	    else {
		// start == end; just center on that index (but first, do some bounds checking)
		if ( (start >= view.landmarkStart) && (start <= view.landmarkEnd) ) {
		    cif.setCenter (start);
		    message ('centered view on range [' + start + ',' + end + ']');
		    document.getElementById('searchInputBox').value = '';  // clear the input box
		}
		else {
		    message ('ERROR: Cannot center on [' + start + ',' + end + ']: out of landmark range [' +
			     view.landmarkStart + ',' + view.landmarkEnd + ']');
		}		
	    }
	}
	else {
	    message ('ERROR: Cannot understand search term [' + input + ']... ' +
		   'this feature is probably not implemented yet.');
	}
    }
}

//
// Handlers for the scroll buttons
//
function NavigationComponent_scrollToStart() {
    // bit of a hack: center on left border, centering code will automatically adjust the view
    // to be in-bounds, so now we are at the beginning
    cif.setCenter (view.landmarkStart);
}
function NavigationComponent_scrollFarLeft() {
    cif.updateHorizontal (3, -stripPx (cif.getOuterDivMain().style.width));
}
function NavigationComponent_scrollNearLeft () {
    cif.updateHorizontal (3, -(Math.floor(stripPx(cif.getOuterDivMain().style.width) / 2)));
}
function NavigationComponent_scrollFarRight() {
    cif.updateHorizontal (3, stripPx(cif.getOuterDivMain().style.width));
}
function NavigationComponent_scrollNearRight() {
    cif.updateHorizontal (3, (Math.floor(stripPx(cif.getOuterDivMain().style.width) / 2)));
}
function NavigationComponent_scrollToEnd() {
    // bit of a hack: center on right border, centering code will automatically adjust the view
    // to be in-bounds, so now we are at the end
    cif.setCenter (view.landmarkEnd);
}

//
// Handlers for zooming in and out
//
function NavigationComponent_zoomOut () {
    // get index of the current zoom level
    var zoomLevelIndex;
    var zoomLevels = taz.getZoomLevelNames();
    var numberOfZoomLevels = zoomLevels.length;
    for (var i = 0; i < numberOfZoomLevels; i++)
	if (view.currentZoomLevel === zoomLevels[i])
	    zoomLevelIndex = i;
    
    // make sure we're not already at the maximum zoom level before zooming out
    if (zoomLevelIndex < (numberOfZoomLevels - 1)) cif.changeZoomLevel(zoomLevels[zoomLevelIndex + 1]);
}
function NavigationComponent_zoomIn () {
    // get index of the current zoom level
    var zoomLevelIndex;
    var zoomLevels = taz.getZoomLevelNames();
    var numberOfZoomLevels = zoomLevels.length;
    for (var i = 0; i < numberOfZoomLevels; i++)
	if (view.currentZoomLevel === zoomLevels[i])
	    zoomLevelIndex = i;
    
    // make sure we're not already at the minimum zoom level before zooming in
    if (zoomLevelIndex > 0) cif.changeZoomLevel(zoomLevels[zoomLevelIndex - 1]);
}


//-------------------------
//     OTHER FUNCTIONS
//-------------------------

//
// Closure to construct event handler for zoom levels drop-down menu
//
function NavigationComponent_makeZoomHandler(zoomLevel) {
    return function () { cif.changeZoomLevel (zoomLevel) };
}

function NavigationComponent_makeLandmarkHandler(landmark) {
    return function() {
        configureBrowser(taz.config, landmark);
    };
}

