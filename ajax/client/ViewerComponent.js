// Written by Andrew Uzilov, November 2005 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//==================================================================================================
//
// The track dragging and off-screen image caching code is based mostly on Chapter 4 of
// "Pragmatic Ajax: A Web 2.0 Primer" (beta version) by Justin Gehtland, Ben Galbraith, and
// Dion Almaer, published by The Pragmatic Programmers (http://www.pragmaticprogrammer.com).
//
// TODO and NOTES:
//
// - Liberally wrap things in try/catch blocks (maybe remove for release version).
//
// - The right-edge (maybe even left?) and center nt output is not exact; also, the center jumps
//   slightly from zoom level to zoom level.
//
// - If labels are toggled "on" and you scroll them out of view, they dissappear, but when they
//   are "off", the label attaches to the topmost visible part of a track - the latter shoud be
//   done for when the labels are "on" as well.
//
// - Explain the event handler manipulation to handle dragging state (a departure from PA:AW2P).
//
// - Explain exception to "no globals" policy and warn about possible name clash.
//
// - Explain primary/overflow div mechanism.  Make sure the terms 'view' (visible view from absLeft
//   to absRight), 'landmark'*, 'relative', 'absolute',
//   'first' (i.e. leftmost), 'last' (i.e. rightmost) are well-defined and consistenly used (also
//   types of divs: drag, track, tile, etc...)
//
// * am I using "landmark" consistently with what BioPerl uses it for? NO - need to fix!
//
// IMPLEMENTATION ANNOYANCES TO FIX (non-essential):
//
// - Optimize for better memory usage... if that's even possible.
//
// - Use resizeBrowser() to set up dimensions when initializing browser (in constructor or
//   renderBrowser()) for consistency - this way, all code that computes layout according to Web
//   browser dimensions will be in one place.
//
// - Rewrite updateVertical() to be more elegant.
//
// - Aggregate duplicate code in 'startMove' drag functions.
//
// - Instead of manual offsets for track labels, use 'relative' positioning and just wrap them in
//   invisible divs (overflow hidden) whose height is same as track height, width is same as visible
//   view width... this way, to hide a label, just set its wrapping div to 0 instead of messing with
//   detaching/reinserting them into DOM subtree.
//
//   Actually, the same technique could be used for showing/hiding tracks!  Would make it much
//   easier, no need to find where to re-insert them... (too bad I wrote it the stupid way already).
//   This way, nothing ever leaves the DOM tree at all - no hiding stuff in internal data members.
//
//   (yet another side benefit of this might be less memory use?  probably not by much, though...)
//==================================================================================================


/*
  GLOBALS

  These are the only exception to The Rules, because dragging and other things speed up considerably
  if you eliminiate the reference chain overhead incurred when accessing non-global values.
*/

// dragging state variables; set on drag start
var dragging, dragStartTop, dragStartLeft, oldTop, oldLeft, newTop, newLeft;

// shortcuts to CSSStyleDeclaration objects of the draggable divs (see also: CSS2Properties objects);
// set in constructor
var dragDivPanelStyle, dragDivRulerStyle, dragDivMainStyle, dragDivTrackLabelsStyle;

/* scrolling bounds variables - set on first call to updateHorizontal() */

// the minimum value (max being 0) that the 'top' attributes of drag divs are allowed to have
var topmostBound;

// true if leftmost visible part of the view ('absLeft') is in the leftmost div
var inFirstDiv;

// the min value that the 'left' attributes of inner divs are allowed to have
// (keeps the view in bounds; max is always 0, but only checked when 'inFirstDiv' is on)
var leftmostBound;

// Flag to specify to use Ajax.Updater to download the html data for generating images and image maps
// setting this to 0 means it is backwards compatible with tile sources that have not had the html generated 
// by generate-tiles.pl
var htmlFiles=1;

//---------------------------------------
//     CONSTRUCTORS AND INITIALIZERS
//---------------------------------------

function ViewerComponent () {

    /* do "classic GBrowse" stuff (for demo only; TODO: remove when done) */

    var classicURLObj = taz.config.getElementsByTagName("classicurl")[0];
    if (classicURLObj === undefined) {  // just in case
	message ("PROBLEM! CANNOT GET URL OF CLASSIC GBROWSE! Bailing out... (check your XML file)");
	return;
    }
    this.classicURL = classicURLObj.getAttribute("url");

    /* associate internal refs with methods */
    // TODO: convert to prototypes!

    // initializers, constructors of elements, and the like
    this.renderComponent = ViewerComponent_renderComponent;
    this.addTrackDivs = ViewerComponent_addTrackDivs;
    this.makeOverflow = ViewerComponent_makeOverflow;

    // accessors
    this.getState = ViewerComponent_getState;
    this.getTracks = ViewerComponent_getTracks;
    this.getMainWidth = ViewerComponent_getMainWidth;
    this.getLandmarkWidth = ViewerComponent_getLandmarkWidth;

    // modifiers
    this.setState = ViewerComponent_setState;
    this.changeZoomLevel = ViewerComponent_changeZoomLevel;
    this.setCenter = ViewerComponent_setCenter;
    this.showTrack = ViewerComponent_showTrack;
    this.hideTrack = ViewerComponent_hideTrack;
    this.moveTrack = ViewerComponent_moveTrack;
    this.popupTrackLabel = ViewerComponent_popupTrackLabel;
    this.unpopupTrackLabel = ViewerComponent_unpopupTrackLabel;
    this.toggleTrackLabels = ViewerComponent_toggleTrackLabels;
    this.scrapAndRebuild = ViewerComponent_scrapAndRebuild;
    this.swapPrimaryAndOverflow = ViewerComponent_swapPrimaryAndOverflow;
    this.deleteOverflow = ViewerComponent_deleteOverflow;
    this.setViewHeight = ViewerComponent_setViewHeight;

    // updaters
    this.updateHorizontal = ViewerComponent_updateHorizontal;
    this.updateVertical = ViewerComponent_updateVertical;
    this.updateTiles = ViewerComponent_updateTiles;

    // event handlers
    this.resizeBrowser = ViewerComponent_resizeBrowser;
    this.centerView = ViewerComponent_centerView;

    // other functions
    this.pixelToNt = ViewerComponent_pixelToNt;
    this.ntToPixel = ViewerComponent_ntToPixel;

    /* holder for hiding things (tracks, track labels) */

    // NB: these are disordered - that is, the order of Node children is not necessarily
    // the same as the order of the tracks, so algorithms accessing these data structures
    // should not count on order
    //
    // DO NOT remove Nodes in pDivMain, dragDivPanel, or dragDivTrackLabels, EVER: they are
    // there to mirror the structure of the DOM subtrees.  For the same reason, oDivMain
    // should only contain a Node when there is overflow, 'null' otherwise.

    this.hidden = {};
    this.hidden.pDivMain = document.createElement ('div');
    this.hidden.oDivMain = null;
    this.hidden.dragDivPanel = document.createElement ('div');
    this.hidden.dragDivTrackLabels = document.createElement ('div');

    // to completely mirror the DOM structure, add attributes to the hiddens

    this.hidden.pDivMain.id = 'pDivMain';
    this.hidden.pDivMain.className = 'innerDiv';

    this.hidden.dragDivPanel.id = 'dragDivPanel';
    this.hidden.dragDivPanel.className = 'dragDiv';

    this.hidden.dragDivTrackLabels.id = 'dragDivTrackLabels';
    this.hidden.dragDivTrackLabels.className = 'dragDiv';

    // state variable for remembering if track labels are on or off (popup mode)
    this.trackLabelsOn = true;

    /* some misc internal data members */

    // path of the actual tiles at our current zoom level
    this.rulerTileCurrentPath = taz.rulerTilePath + "/" + view.currentZoomLevel + "/";

    // width of inner divs and overflow divs; must be a multiple of tile width
    //
    // IMPORTANT: make sure that divWidth >= (2 * cacheWindows + 1) * max_possible_outerDivMain_width
    // (otherwise things fall apart)
    //
    this.divWidth = taz.tileWidth * 10;

    /*
      'absLeft' is arguably the most important state variable, as without it the browser will become
      "lost" - we will have no idea what part of the genome we are looking at.  Many, many position
      calculations are based on it.
    */
    
    // the ABSOLUTE coordinate (in pixels) of the leftmost and rightmost visible parts of the view
    // ("absolute" is to distinguish them from coordinates RELATIVE to inner divs); should always be
    // an integer x such that 0 <= x < landmarkWidth; will be set on first call to updateHorizontal()
    //
    this.absLeft = this.absRight = null;

    // stores whether we are displaying all visible tracks vertically unbounded (true), or constraining
    // the view height to some fixed value (false)
    this.maxHeight = false;

    /* set up divs */

    var divs = ['Panel', 'Main', 'Ruler', 'TrackLabels'];  // loop instead of writing same thing N times
    for (var i = 0; i < divs.length; i++)
	{
	    // outer divs
	    if (divs[i] !== 'TrackLabels') {
		var outerDiv = document.createElement ('div');
		outerDiv.id = 'outerDiv' + divs[i];
		outerDiv.className = 'outerDiv';
		this['outerDiv' + divs[i]] = outerDiv;  // save ref for later use
	    }

	    // drag divs
	    var dragDiv = document.createElement ('div');
	    dragDiv.id = 'dragDiv' + divs[i];
	    dragDiv.className = 'dragDiv';
	    this['dragDiv' + divs[i]] = dragDiv;  // save ref for later use
    }

    // global shortcuts, to reduce reference chain overhead in dragging code
    // (TODO: hmm, I wonder if I can do this in the loop... JS masturbation, really)
    //
    dragDivPanelStyle = this.dragDivPanel.style;
    dragDivMainStyle = this.dragDivMain.style;
    dragDivRulerStyle = this.dragDivRuler.style;
    dragDivTrackLabelsStyle = this.dragDivTrackLabels.style;

    // set up primary divs
    this.pDivMain = document.createElement ('div');
    this.pDivRuler = document.createElement ('div');

    this.pDivMain.id = 'pDivMain';  this.pDivRuler.id = 'pDivRuler';
    this.pDivMain.className = this.pDivRuler.className = 'innerDiv';

    this.pDivMain.style.left = this.pDivRuler.style.left = '0px';

    // will hold refs to overflow divs, whenever these get created
    this.oDivMain = this.oDivRuler = null;

    /*
      for each track:
       - add it to panel;
       - create a hovering label for it
    */

    var trackNames = taz.getTrackNames();
    for (var i = 0; i < trackNames.length; i++) {
	var trackName = trackNames[i];

	// create silly panel div for vertical drag bar
	var panelDiv = document.createElement ('div');
	panelDiv.id = trackName + '_panelDiv';
	panelDiv.className = 'panelDiv';
	panelDiv.style.height = taz.getHeightOfTrack (trackName) + 'px';

	// color vertical drag bar with zebra stripes (TODO: this is temporary and should be replaced with
	// a real scroll bar)
	if (i % 2 == 0)
	    panelDiv.style.background = '#333333';
	else
	    panelDiv.style.background = '#CCCCCC';

	// create hovering track label
	var trackLabelDiv = document.createElement ('div');
	trackLabelDiv.id = trackName + '_trackLabelDiv';
	trackLabelDiv.className = 'trackLabelDiv';
	trackLabelDiv.style.background = '#' + colorArray[i % colorArray.length];  // wrap index, so we don't run out of colors
	trackLabelDiv.innerHTML = trackName;

	if (taz.isTrackVisible (trackName)) {
	    this.dragDivPanel.appendChild (panelDiv);
	    this.dragDivTrackLabels.appendChild (trackLabelDiv);
	}
	else {
	    this.hidden.dragDivPanel.appendChild (panelDiv);
	    this.hidden.dragDivTrackLabels.appendChild (trackLabelDiv);
	}
    }

    /* register event handlers */

    // N.B.: have to use ComponentInterface for some of these, to get 'this' keyword to properly
    // refer to ViewerComponent object when the event fires

    // handler for window resizing
    window.onresize = function (event) { cif.resizeBrowser (event); };

    // handlers for dragging - global scope and no function wrapper for efficiency reasons
    this.outerDivMain.onmousedown = ViewerComponent_startMoveXY;
    this.outerDivPanel.onmousedown = ViewerComponent_startMoveY;
    this.outerDivRuler.onmousedown = ViewerComponent_startMoveX;
    window.onmouseup = ViewerComponent_stopMove;  // code to stop dragging is the same for all

    // handler for double-clicking to center
    this.outerDivRuler.ondblclick = this.outerDivMain.ondblclick =
	function (event) { cif.centerView (event); };
}

//
// Construct and return DOM node for this Component.
//
function ViewerComponent_renderComponent () {

    /* set up outer div dimensions */

    var cssRules = document.styleSheets[0].cssRules;  // look up some CSS-specified dimensions

    for (var i = 0; i < cssRules.length; i++) {
	if (cssRules[i].selectorText === '#outerDivPanel') {
	    var panelWidth = stripPx (cssRules[i].style.width);
	    var panelHeightPx = cssRules[i].style.height;
	    break;
	}
    }
    
    this.outerDivPanel.style.width = panelWidth + 'px';  // stupid hack so I can access height easier
    this.outerDivPanel.style.height = panelHeightPx;     // (TODO: isn't there some computed height thingie?...)

    this.outerDivMain.style.height = panelHeightPx;
    this.outerDivRuler.style.height = taz.rulerCellHeight + 'px';

    // must go last, as it depends on panel width being set
    this.outerDivMain.style.width = this.outerDivRuler.style.width = this.getMainWidth () + 'px';

    // make height input box display the current height
    cif.setDisplayedViewHeight (stripPx (panelHeightPx));

    /* construct DOM node */
    var domNode = document.createElement ('table');
    domNode.id = 'ViewerComponent';

    var row1 = document.createElement ('tr');
    var row2 = document.createElement ('tr');

    var row1col1 = document.createElement ('td');  // empty placeholder
    var row1col2 = document.createElement ('td');
    var row2col1 = document.createElement ('td');
    var row2col2 = document.createElement ('td');

    /* description id for pop-up feature menu */
    var descDiv = document.createElement('div')
    descDiv.id = 'description';

    /* aggregate parts into the node subtree */    
    this.addTrackDivs (this.pDivMain);

    this.dragDivMain.appendChild (this.pDivMain);
    this.dragDivRuler.appendChild (this.pDivRuler);

    this.outerDivMain.appendChild (this.dragDivMain);
    this.outerDivMain.appendChild (this.dragDivTrackLabels);    
    this.outerDivPanel.appendChild (this.dragDivPanel);
    this.outerDivRuler.appendChild (this.dragDivRuler);


    row1col2.appendChild (this.outerDivRuler);
    row2col1.appendChild (this.outerDivPanel);
    row2col2.appendChild (this.outerDivMain);

    row1.appendChild (row1col1);  row1.appendChild (row1col2);
    row2.appendChild (row2col1);  row2.appendChild (row2col2);

    domNode.appendChild (row1);  domNode.appendChild (row2);
    
    domNode.appendChild(descDiv);

    /* initialize tile caching things (NB: make sure this is consistent with updateHorizontal()!) */

    this.absLeft = 0;  // start at the very left (TODO: maybe load starting point from XML?)

    // tile and feature cache size, i.e. the number of windows (outer div widths) to each side of 
    // visible portion that the cache should accomodate
    //
    // IMPORTANT: make sure that divWidth >= (2 * cacheWindows + 1) * max_possible_outerDivMain_width
    // (otherwise things fall apart)
    //
    this.cacheWindows = 2;

    // out-of-view amount (in pixels) to cache on each side of visible view
    this.cacheSize = this.cacheWindows * stripPx (this.outerDivMain.style.width);

    // bounds (in absolute pixel coordinates, inclusive) of the min area for which we must cache
    // tiles, features, etc.
    this.cacheBoundL = this.absLeft - this.cacheSize;
    this.cacheBoundR = this.absRight + this.cacheSize;

    // let's not go out of bounds of the landmark
    if (this.cacheBoundL < 0) this.cacheBoundL = 0;
    if (this.cacheBoundR >= this.getLandmarkWidth ()) this.cacheBoundR = this.getLandmarkWidth () - 1;

    this.firstCachedTile = this.lastCachedTile = -1;  // hack to force all tiles to cache anew

    /* initialize everything else */

    this.updateHorizontal (1, 0);  // set up horizontal state components and render the tiles
    this.updateVertical ();  // set up vertical state components, such as track heights, etc.

    return domNode;
}

//
// Construct track divs; add visible tracks to the main (primary or overflow) div passed in,
// hidden tracks to the internal storage.
//
function ViewerComponent_addTrackDivs (div) {
    //debug ('addTrackDivs(' + div.id + ')');
    
    if (!div) bugAlert ('bad arg to addTrackDivs(' + div + ')');

    if (div.id.match (/^pDiv/))  // is the div primary or overflow?
	var overflow = false;
    else
	var overflow = true;

    var trackNames = taz.getTrackNames ();

    for (var i = 0; i < trackNames.length; i++) {
	var trackName = trackNames[i];

	// create empty track div - tiles will be added to it on first call to updateTiles()
	var trackDiv = document.createElement ('div');
	trackDiv.className = 'trackDiv';

	if (overflow)
	    trackDiv.id = trackName + '_trackDivO';
	else
	    trackDiv.id = trackName + '_trackDivP';

	trackDiv.style.height = taz.getHeightOfTrack (trackName) + 'px';

	// event handlers (made using closures) - for popping up hovering track labels
	trackDiv.onmouseover = ViewerComponent_makeOnTrackDivHandler (trackName);
	trackDiv.onmouseout = ViewerComponent_makeOffTrackDivHandler (trackName);

	if (taz.isTrackVisible (trackName)) {  // if track is visible, render track div
	    div.appendChild (trackDiv);
	}
	else {
	    // if track is hidden, don't render, but store for later
	    if (overflow)
		this.hidden.oDivMain.appendChild (trackDiv);
	    else
		this.hidden.pDivMain.appendChild (trackDiv);
	}
    }
}

//
// Closure to construct event handler for track div 'onmouseover'
//
function ViewerComponent_makeOnTrackDivHandler (trackName) {
    return function () {
	if (!cif.areTrackLabelsOn ())
	    cif.popupTrackLabel (trackName);
    }
}
//
// Closure to construct event handler for track 'onmouseout'
//
function ViewerComponent_makeOffTrackDivHandler (trackName) {
    return function () {
	if (!cif.areTrackLabelsOn ())
	    cif.unpopupTrackLabel (trackName);
    }
}

//
// Construct overflow and append to DOM tree (also take care of hiddens).
//
// side:
//   -1 = append overflow divs on the LEFT of primary divs
//   1 = append overflow divs on the RIGHT of primary divs
//
function ViewerComponent_makeOverflow (side) {

    if (!side || ((side !== -1) && (side !== 1))) bugAlert ('bad arg: makeOverflow (' + side + ')');
    
    var divM = document.createElement ('div');
    var divR = document.createElement ('div');

    divM.id = 'oDivMain';
    divR.id = 'oDivRuler';

    divM.className = divR.className = 'innerDiv';

    divM.style.left = divR.style.left = (side * this.divWidth) + 'px';

    // create storage Node for hidden tracks in overflow
    this.hidden.oDivMain = document.createElement ('div');
    this.hidden.oDivMain.id = 'oDivMain';
    this.hidden.oDivMain.className = 'innerDiv';

    this.addTrackDivs (divM);  // must go after you assign the id and construct hidden.oDivMain

    this.oDivMain = this.dragDivMain.appendChild (divM);
    this.oDivRuler = this.dragDivRuler.appendChild (divR);
}


//-------------------
//     ACCESSORS
//-------------------

//
// TODO: stub for "return state" for bookmarking feature - every Component must
// implement one of these!
//
function ViewerComponent_getState () {
}

//
// Returns ALL track divs anywhere in the browser (except ruler track) as an array of Node objects.
//
// If you set 'visibleOnly', returns only the visible tracks.
//
// Tracks will be in the following order:
//   - those from visible inner div
//   - those from visible overflow div (if any)
//   - those from hidden inner div (if any)
//   - those from hidden overflow div (if any)
//
// Thus, visible tracks can be operated before hidden ones, for a smoother UI.
//
// TODO: replace with calls to Prototype 'getElementsByClassName()'?
//
function ViewerComponent_getTracks (visibleOnly) {
    var tracks = [];

    // visible inner div
    var children = this.pDivMain.childNodes;
    for (var childNum = 0; childNum < children.length; childNum++)
	tracks.push (children[childNum]);

    // visible overflow div
    if (this.oDivMain) {
	children = this.oDivMain.childNodes;
	for (childNum = 0; childNum < children.length; childNum++)
	    tracks.push (children[childNum]);
    }

    if (!visibleOnly) {
	// hidden inner div
	children = this.hidden.pDivMain.childNodes;
	for (childNum = 0; childNum < children.length; childNum++)
	    tracks.push (children[childNum]);

	// hidden overflow div
	if (this.hidden.oDivMain) {
	    children = this.hidden.oDivMain.childNodes;
	    for (childNum = 0; childNum < children.length; childNum++)
		tracks.push (children[childNum]);
	}
    }
    
    return tracks;
}


//
// Computes and returns the optimal outerDiv{Main,Ruler} width, in pixels.
//
function ViewerComponent_getMainWidth () {

    // start by computing the maximum possible width
    // (subtract Meaning of Life because a spacer on the right looks nicer)
    var width = window.innerWidth - stripPx (this.outerDivPanel.style.width) - 42;

    //debug ('old width: ' + stripPx (this.outerDivMain.style.width));

    // if the whole landmark width is smaller than the view, bind view borders to landmark width
    if (this.getLandmarkWidth () < width)
	return this.getLandmarkWidth ();
    else
	return width;
}

//
// Computes whole landmark width, in pixels.
//
function ViewerComponent_getLandmarkWidth () {

    // units_in_landmark / (units / tile) * tile_width = total_width_of_entire_landmark
    
    return Math.ceil ((view.landmarkEnd - view.landmarkStart + 1) / taz.getUnitsPerTile() * taz.tileWidth);
}


//-------------------
//     MODIFIERS
//-------------------

//
// TODO: stub for "restore state" for bookmarking feature - every Component must implement one!
//
function ViewerComponent_setState (stateObj) {
    // not implemented yet
}

//
// Called to change the zoom level
//
// TOTO: make it hold the vertical position
//
function ViewerComponent_changeZoomLevel (newZoomLevel) {

    // when zooming, we will keep the genomic coordinates of the center point the same
    var centerX = view.centerNt;

    document.getElementById (view.currentZoomLevel).selected = false;  // deselect old zoom level in menu
    document.getElementById (newZoomLevel).selected = true;       // select new zoom level in menu

    view.currentZoomLevel = newZoomLevel;  // update internal state storing current zoom level

    this.rulerTileCurrentPath = taz.rulerTilePath + "/" + view.currentZoomLevel + "/";

    /* clear old zoom level images from drag divs */

    // do all the visible tiles
    var tileDivs = document.getElementsByClassName ('tileDiv');
    tileDivs.each (function (tile) { tile.parentNode.removeChild (tile) });
    
    // do hidden primary div tiles
    tileDivs = document.getElementsByClassName ('tileDiv', this.pDivMain);
    tileDivs.each (function (tile) { tile.parentNode.removeChild (tile) });

    // do hidden overflow div tiles
    tileDivs = document.getElementsByClassName ('tileDiv', this.oDivMain);
    tileDivs.each (function (tile) { tile.parentNode.removeChild (tile) });

    /* do other stuff */

    // align divs to top (TODO: the vertical state must be preserved, not reset)
    dragDivMainStyle.top = dragDivPanelStyle.top = dragDivTrackLabelsStyle.top = '0px';
    if (this.oDivMain)
	this.oDivMain.style.top = '0px';

    this.firstCachedTile = -1;  // hack to make new zoom level tiles load into cache in updateTiles()
    this.lastCachedTile = -1;

    this.setCenter (centerX, 1);  // preserve center nt; also calls updateHorizontal()

    this.updateVertical ();
}

//
// Horizontally centers the view on the specified nucleotide.
//
// When this function is called upon zoom level change, 'afterZoomChange' should be set, so that we
// may pass it to updateHorizontal().
//
function ViewerComponent_setCenter (center, afterZoomChange) {

    var newAbsLeft = this.ntToPixel (center) - Math.floor (stripPx (this.outerDivMain.style.width) / 2);

    if (afterZoomChange)
	this.updateHorizontal (1, newAbsLeft);
    else
	this.updateHorizontal (3, (newAbsLeft - this.absLeft));
}

//
// Makes a track (specified by its string name) visible.
//
function ViewerComponent_showTrack (trackName) {
    //debug ('showing ' + trackName);

    /* get parts of the hidden track from internal data members */

    var trackP = findAndRemoveChild (this.hidden.pDivMain, trackName + '_trackDivP');
    if (!trackP)
	bugAlert ('showTrack(' + trackName + '): primary track div not hidden');

    if (this.oDivMain) {
	var trackO = findAndRemoveChild (this.hidden.oDivMain, trackName + '_trackDivO');

	if (!trackO)
	    bugAlert ('showTrack(' + trackName + '): overflow track div not hidden');
    }

    var panelDiv = findAndRemoveChild (this.hidden.dragDivPanel, trackName + '_panelDiv');
    if (!panelDiv)
	bugAlert ('showTrack(' + trackName + '): panel div not hidden');

    var trackLabelDiv = findAndRemoveChild (this.hidden.dragDivTrackLabels, trackName + '_trackLabelDiv');
    if (!trackLabelDiv)
	bugAlert ('showTrack(' + trackName + '): track label not hidden');
    
    /* locate where the track is to be inserted */

    taz.setTrackVisible (trackName);  // MUST go before getting visible tracks

    var tracks = taz.getVisibleTrackNames ();
    var insertAfterTrack = null;

    for (var i = 0; i < tracks.length; i++)
	{
	    if (tracks[i] === trackName)
		break;

	    // maintain last visible track, which is the one we will insert after
	    insertAfterTrack = tracks[i];
	}

    /* insert track parts into DOM tree */

    if (insertAfterTrack) {
	// track is not the first; insert after some other track

	insertAfter (this.pDivMain, trackP,
		     getChild (this.pDivMain, (insertAfterTrack + '_trackDivP')));

	if (trackO)
	    insertAfter (this.oDivMain, trackO,
			 getChild (this.oDivMain, (insertAfterTrack + '_trackDivO')));

	insertAfter (this.dragDivPanel, panelDiv,
		     getChild (this.dragDivPanel, (insertAfterTrack + '_panelDiv')));

	insertAfter (this.dragDivTrackLabels, trackLabelDiv,
		     getChild (this.dragDivTrackLabels, (insertAfterTrack + '_trackLabelDiv')));
    }
    else {
	// special case: track is the first one (no preceeding track found)

	this.pDivMain.insertBefore (trackP, this.pDivMain.childNodes[0]);
	if (trackO)
	    this.oDivMain.insertBefore (trackO, this.oDivMain.childNodes[0]);

	this.dragDivPanel.insertBefore (panelDiv, this.dragDivPanel.childNodes[0]);
	this.dragDivTrackLabels.insertBefore (trackLabelDiv,
					      this.dragDivTrackLabels.childNodes[0]);
    }

    // need this to re-compute the vertical offsets for track labels
    this.updateVertical ();
}

//
// Makes a track (specified by its string name) hidden.
//
function ViewerComponent_hideTrack (trackName) {
    //debug ('hiding ' + trackName);
    
    // find the nodes for the track we want to hide, detach from DOM tree and save them internally

    var trackP = findAndRemoveChild (this.pDivMain, trackName + '_trackDivP');
    if (!trackP)
	bugAlert ('hideTrack(' + trackName + '): track not visible (primary div)');
    this.hidden.pDivMain.appendChild (trackP);

    if (this.oDivMain) {
	var trackO = findAndRemoveChild (this.oDivMain, trackName + '_trackDivO');
	if (!trackO)
	    bugAlert ('hideTrack(' + trackName + '): track not visible (overflow div)');
	this.hidden.oDivMain.appendChild (trackO);
    }

    var panelDiv = findAndRemoveChild (this.dragDivPanel, trackName + '_panelDiv');
    if (!panelDiv)
	bugAlert ('hideTrack(' + trackName + '): panel div not visible');
    this.hidden.dragDivPanel.appendChild (panelDiv);

    var trackLabelDiv = findAndRemoveChild (this.dragDivTrackLabels, trackName + '_trackLabelDiv');
    if (!trackLabelDiv)
	bugAlert ('hideTrack(' + trackName + '): track label div not visible');
    this.hidden.dragDivTrackLabels.appendChild (trackLabelDiv);

    // update state
    taz.setTrackHidden (trackName);
    this.updateVertical ();
}

//
// Move the track to a new position (i.e. change track order).
// 'newPos' is 1-based indexing.
//
// NB:
// - This function requires that the track ordering in 'taz' has been updated already.
// - This function does not error check any arguments passed to it, so the caller
//   is responsible for verifying their validity.
//
function ViewerComponent_moveTrack (trackName, newPos)
{
    // if track is hidden, don't need to modify DOM - because the track ordering in 'taz'
    // has been updated already, the track will be placed in the new location when it is
    // made visible

    if (taz.isTrackVisible (trackName)) {
       newPos--;  // convert to 0-based indexing

       var movedTrackP = findAndRemoveChild (this.pDivMain, trackName + '_trackDivP');
       if (this.oDivMain)
           var movedTrackO = findAndRemoveChild (this.oDivMain, trackName + '_trackDivO');

       var movedPanel = findAndRemoveChild (this.dragDivPanel, trackName + '_panelDiv');
       var trackLabel = findAndRemoveChild (this.dragDivTrackLabels, trackName + '_trackLabelDiv');

       if (newPos == 0) {
           // insert at the very beginning
           this.pDivMain.insertBefore (movedTrackP, this.pDivMain.childNodes[0]);
           if (movedTrackO)
               this.oDivMain.insertBefore (movedTrackO, this.oDivMain.childNodes[0]);
           this.dragDivPanel.insertBefore (movedPanel, this.dragDivPanel.childNodes[0]);
           this.dragDivTrackLabels.insertBefore (trackLabel,
                                                 this.dragDivTrackLabels.childNodes[0]);
       }
       else {
           // find the last visible track after which we can insert the moved one
           var insertAfterTrack = null;
           var tracks = taz.getTrackNames();
           for (var i = newPos - 1; i >= 0; i--)
               if (taz.isTrackVisible (tracks[i])) {
                   insertAfterTrack = tracks[i];  break;
               }
           
           if (insertAfterTrack) {
               // insert after some track
               insertAfter (this.pDivMain, movedTrackP,
                            getChild (this.pDivMain, (insertAfterTrack + '_trackDivP')));
               if (movedTrackO)
                   insertAfter (this.oDivMain, movedTrackO,
                                getChild (this.oDivMain, (insertAfterTrack + '_trackDivO')));
               insertAfter (this.dragDivPanel, movedPanel,
                            getChild (this.dragDivPanel, (insertAfterTrack + '_panelDiv')));
               insertAfter (this.dragDivTrackLabels, trackLabel,
                            getChild (this.dragDivTrackLabels, (insertAfterTrack + '_trackLabelDiv')));
           }
           else {
               // insert at the very beginning
               this.pDivMain.insertBefore (movedTrackP, this.pDivMain.childNodes[0]);
               if (movedTrackO)
                   this.oDivMain.insertBefore (movedTrackO, this.oDivMain.childNodes[0]);
               this.dragDivPanel.insertBefore (movedPanel, this.dragDivPanel.childNodes[0]);
               this.dragDivTrackLabels.insertBefore (trackLabel,
                                                     this.dragDivTrackLabels.childNodes[0]);
           }
       }

       this.updateVertical();
    }
}

//
// Pops up the label for the particular track.
//
function ViewerComponent_popupTrackLabel (trackName) {
    getChild (this.dragDivTrackLabels, trackName + '_trackLabelDiv').style.visibility = 'visible';
}

//
// Hides the track label that is (presumably) temporarily popped up.
//
function ViewerComponent_unpopupTrackLabel (trackName) {
    getChild (this.dragDivTrackLabels, trackName + '_trackLabelDiv').style.visibility = 'hidden';
}

//
// Toggle track labels on/off.
//
function ViewerComponent_toggleTrackLabels () {

    var labels = $A (this.dragDivTrackLabels.childNodes);

    if (this.trackLabelsOn)
	{
	    labels.each
		(function (label) {
		    label.style.visibility = 'hidden';
		});

	    this.trackLabelsOn = false;
	}
    else
	{
	    labels.each
		(function (label) {
		    label.style.visibility = 'visible';
		});
	    
	    this.trackLabelsOn = true;
	}
}

//
// Helper for ViewerComponent_updateHorizontal() (TODO: write up)
//
// divL = number (i.e. div offset) of left div (always will be the inner div) - REQUIRED argument
// divR = number (i.e. div offset) of right div (always will be the overflow div) - OPTIONAL argument
//
function ViewerComponent_scrapAndRebuild (divL, divR) {
    //debug ('scrapAndRebuild(' + divL + ',' + divR + ')');
    
    dragDivMainStyle.left = dragDivRulerStyle.left = -(this.absLeft - (divL * this.divWidth)) + 'px';

    if (divR !== undefined) {
	// need overflow
	if (this.oDivMain)
	    // if overflow already exists, just move to the right of primary divs
	    this.oDivMain.style.left = this.oDivRuler.style.left = this.divWidth + 'px';
	else
	    // no overflow divs, so make them
	    this.makeOverflow (1);
    }
    else if (this.oDivMain) {
	// overflow exists but no longer needed; remove
	this.deleteOverflow ();
    }
}

function ViewerComponent_swapPrimaryAndOverflow () {
    //debug ('SWAP PRIMARY AND OVERFLOW');

    // ugh... need to recurse through ALL THE TRACKS everywhere and rename P to O and vice versa
    // in the 'id' attributes... maybe I can get rid of this damn method altogether? (TODO: tink about it)
    //
    var trackNameRE = /^(.*)_trackDiv([PO])/;
    var tracks = this.getTracks ();
    tracks.each
	(function (track) {
	    var matches = track.id.match (trackNameRE);
	    if (matches[2] === 'P')
		track.id = matches[1] + '_trackDivO';
	    else
		track.id = matches[1] + '_trackDivP';
	});

    // adjust coordinates of drag divs
    dragDivMainStyle.left = dragDivRulerStyle.left =
	(stripPx (dragDivMainStyle.left) + stripPx (this.oDivMain.style.left)) + 'px';

    /* swap visible */

    this.pDivMain.style.left = -stripPx (this.oDivMain.style.left) + 'px';  // swap locations
    this.oDivMain.style.left = '0px';

    this.pDivRuler.style.left = -stripPx (this.oDivRuler.style.left) + 'px';
    this.oDivRuler.style.left = '0px';

    this.pDivMain.id = 'oDivMain';    this.oDivMain.id = 'pDivMain';  // swap IDs
    this.pDivRuler.id = 'oDivRuler';  this.oDivRuler.id = 'pDivRuler';

    var tempRef = this.pDivMain;  // swap internal references
    this.pDivMain = this.oDivMain;
    this.oDivMain = tempRef;

    tempRef = this.pDivRuler;
    this.pDivRuler = this.oDivRuler;
    this.oDivRuler = tempRef;

    /* swap hidden */

    this.hidden.pDivMain.id = 'oDivMain';
    this.hidden.oDivMain.id = 'pDivMain';

    tempRef = this.hidden.pDivMain;
    this.hidden.pDivMain = this.hidden.oDivMain;
    this.hidden.oDivMain = tempRef;
}

//
// Completely remove all overflow from everywhere.
//
function ViewerComponent_deleteOverflow () {
    if (!this.dragDivMain.removeChild (this.oDivMain))
	bugAlert ('deleteOverflow(): trying to remove overflow from main, but there is none');

    if (!this.dragDivRuler.removeChild (this.oDivRuler))
	bugAlert ('deleteOverflow(): trying to remove overflow from ruler, but there is none');

    this.oDivMain = this.oDivRuler = null;
    this.hidden.oDivMain = null;
}


//
// Changes the view height to the specified value, in pixels.
//
// The 'noUpdateVertical' arg is there because we sometimes call this function from updateVertical()
// itself, so setting it to 'true' prevents infinite recursion.
//
function ViewerComponent_setViewHeight (newHeightPx, noUpdateVertical) {
    if ((newHeightPx === undefined) ||
	(parseInt (newHeightPx) != newHeightPx) ||
	(newHeightPx < 0))
	bugAlert ('setViewHeight(' + newHeightPx + '): bad param');

    this.outerDivMain.style.height = this.outerDivPanel.style.height = newHeightPx + 'px';

    if (!noUpdateVertical)
	this.updateVertical ();

    // update value in the height control box... base it on post-updateVertical() height, just in case
    // it gets changed there for some reason
    cif.setDisplayedViewHeight (stripPx (this.outerDivMain.style.height));
}

//--------------------
//     "UPDATERS"
//--------------------

//
// Updates browser state components that relate to horizontal things.  Corrects the horizontal
// position if we jumped out of bounds.
//
// This should be called after anything happens that might affect such state components, such as:
//   - drag and release (when dragging occurs along horizontal axis),
//   - jump to some location,
//   - scroll (i.e. using left/right buttons)
//   - recenter,
//   - browser resize (this actually should cause recentering automatically, so no need to call this
//     method explicitly after browser resize),
//   - zoom level change,
// and anything else that causes horizontal motion/change of the drag divs.
//
// This function ALWAYS calls updateTiles() to update the tile cache after it is done.
//
// TODO: write up how this works, either here or in some separate document!
//
// Arguments:
//
// motionType:
//   1 - zoom level change (scrap and rebuild all divs), interpret deltaX as new absLeft
//     TODO: this can be figured out by looking at whether the landmark width changed, and ELIMINATED
//   2 - horizontal motion by dragging (don't update div offsets, dragging code did that already)
//   3 - horizontal motion by everything EXCEPT dragging: centering, scrolling, jumping (update div offsets)
//
// TODO: write a little formula sheet, e.g. with how to go from drag div offset to absolute, ALWAYS, etc.
//
function ViewerComponent_updateHorizontal (motionType, deltaX) {
    ///debug ('===UPDATING HORIZONTAL...=== (deltaX = ' + deltaX + ' motionType = ' + motionType + ')');

    if (motionType === undefined) {
	bugAlert ('no motionType passed to ViewerComponent_updateHorizontal');
    }
    else if ( (motionType !== 1) && (motionType !== 2) && (motionType !== 3) ) {
	bugAlert ('wrong motionType (' + motionType + ') passed to ViewerComponent_updateHorizontal');
    }

    if (deltaX === undefined) { bugAlert ('no deltaX passed to ViewerComponent_updateHorizontal'); }

    var landmarkWidth = this.getLandmarkWidth ();  // save local copy

    //bugAlert ('after zoom change is: ' + afterZoomChange);

    // resize view, in case the new landmark width is smaller than the view width
    this.outerDivMain.style.width = this.outerDivRuler.style.width = this.getMainWidth () + 'px';

    /*
    debug ('new landmarkWidth = ' + landmarkWidth + ', new view width = ' +
	   this.outerDivMain.style.width);
    */

    var oldAbsLeft = this.absLeft;

    if (motionType === 1) this.absLeft = deltaX;
    else                  this.absLeft += deltaX;

    this.absRight = this.absLeft + stripPx (this.outerDivMain.style.width) - 1;

    /*
    debug ('new absLeft/Right: ' + this.absLeft + ' (tile ' + Math.floor (this.absLeft / taz.tileWidth) +
	   ') ' + this.absRight + ' (tile ' + Math.floor (this.absRight/ taz.tileWidth) + ') deltaX ' +
	   deltaX);
    */

    // correct absLeft and deltaX to ensure no motion out of bounds can occur
    if (this.absLeft < this.divWidth) {
	//debug ('absLeft IN (or before) FIRST DIV!');
	inFirstDiv = true;  // absLeft is in leftmost div

	if (this.absLeft < 0) {
	    // if we jumped out of bounds (left of the landmark), align to bound
	    this.absLeft = 0;
	    this.absRight = this.absLeft + stripPx (this.outerDivMain.style.width) - 1;  // recompute

	    deltaX = -oldAbsLeft;
	}
    }
    else {
	inFirstDiv = false;
    }

    /*
    debug ('corrected (1) absLeft/Right: ' + this.absLeft + ' (tile ' + Math.floor (this.absLeft / taz.tileWidth) +
	   ') ' + this.absRight + ' (tile ' + Math.floor (this.absRight/ taz.tileWidth) + ') deltaX ' +
	   deltaX);
    */

    if (this.absRight >= landmarkWidth) {
	// if we jumped out of bounds (right of the landmark), align to bound
	this.absRight = landmarkWidth - 1;
	this.absLeft = this.absRight - stripPx (this.outerDivMain.style.width) + 1;
	
	deltaX = this.absLeft - oldAbsLeft;
    }

    /*
    debug ('corrected (2) absLeft/Right: ' + this.absLeft + ' (tile ' + Math.floor (this.absLeft / taz.tileWidth) +
	   ') ' + this.absRight + ' (tile ' + Math.floor (this.absRight/ taz.tileWidth) + ') deltaX ' +
	   deltaX);
    */

    // save ORIGINAL cache area bounds for comparison
    var oldCacheBoundL = this.cacheBoundL;
    var oldCacheBoundR = this.cacheBoundR;

    // update how much to cache (in pixels) on each side of visible view
    this.cacheSize = this.cacheWindows * stripPx (this.outerDivMain.style.width);

    // update bounds (in absolute pixel coordinates, inclusive) for min area to be covered by cache
    this.cacheBoundL = this.absLeft - this.cacheSize;
    this.cacheBoundR = this.absRight + this.cacheSize;

    // let's not go out of bounds of the landmark
    if (this.cacheBoundL < 0) this.cacheBoundL = 0;
    if (this.cacheBoundR >= landmarkWidth) this.cacheBoundR = landmarkWidth - 1;

    //debug ('cache left bound = ' + this.cacheBoundL + ' right bound = ' + this.cacheBoundR);

    // figure out which divs (absolute, numbered from 0 at start of landmark) WERE, and which
    // should NOW BE, covered by cache
    var oldAbsDivL = Math.floor (oldCacheBoundL / this.divWidth);
    var oldAbsDivR = Math.floor (oldCacheBoundR / this.divWidth);
    var newAbsDivL = Math.floor (this.cacheBoundL / this.divWidth);
    var newAbsDivR = Math.floor (this.cacheBoundR / this.divWidth);
	
    if (oldAbsDivL === oldAbsDivR) oldAbsDivR = null;  // cache fits neatly into a single div
    if (newAbsDivL === newAbsDivR) newAbsDivR = null;

    // NB: this method of computing divs ensures that no divs will be COMPLETELY outside of cache bounds
    // (this used to be a "problem"... or rather an annoyance...)
    
    if (motionType === 1) {
	if (newAbsDivR !== null)
	    this.scrapAndRebuild (newAbsDivL, newAbsDivR);  // need overflow
	else
	    this.scrapAndRebuild (newAbsDivL);  // don't need overflow
    }
    else {
	var oldPrimaryDivNum;  // div number prior to motion
	if (motionType === 2)
	    oldPrimaryDivNum = (this.absLeft + stripPx (dragDivRulerStyle.left)) / this.divWidth;
	else
	    oldPrimaryDivNum = (this.absLeft - deltaX + stripPx (dragDivRulerStyle.left)) / this.divWidth;

	// should always divide by divWidth evenly (if it doesn't, it's a bug)
	if (Math.floor (oldPrimaryDivNum) !== oldPrimaryDivNum)
	    bugAlert ('oldPrimaryDivNum ' + oldPrimaryDivNum + ' not an integer');

	//debug ('old inner div # = ' + oldInnerDivNum);
	
	if (oldAbsDivR) {
	    // FROM 2 DIVS...

	    if (newAbsDivR) {
		// FROM 2 TO 2 DIVS

		// cases:

		// - both divs are same
		if ( (oldAbsDivL === newAbsDivL) && (oldAbsDivR === newAbsDivR) ) {
		    if (motionType === 3)
			dragDivMainStyle.left = dragDivRulerStyle.left =
			    (stripPx (dragDivRulerStyle.left) - deltaX) + 'px';
		}
		// - one div same, one diff
		else if (oldAbsDivL === newAbsDivR) {
		    //debug ('2->2, 1 same + 1 diff');

		    // put overflow on other side of primary div
		    this.oDivMain.style.left = this.oDivRuler.style.left = -this.divWidth + 'px';

		    if (motionType === 3) {
			if (newAbsDivR === oldPrimaryDivNum)
			    dragDivMainStyle.left = dragDivRulerStyle.left =
				-(this.absLeft - (newAbsDivR * this.divWidth)) + 'px';  // same div is primary div
			else
			    dragDivMainStyle.left = dragDivRulerStyle.left =
				-(this.absLeft - (newAbsDivL * this.divWidth)) + 'px';  // same div is overflow div
		    }		    
		}
		else if (oldAbsDivR === newAbsDivL) {
		    //debug ('2->2, 1 same + 1 diff');

		    // put overflow on other side of primary div
		    this.oDivMain.style.left = this.oDivRuler.style.left = -this.divWidth + 'px';

		    if (motionType === 3) {
			if (newAbsDivL === oldPrimaryDivNum)
			    dragDivMainStyle.left = dragDivRulerStyle.left =
				-(this.absLeft - (newAbsDivL * this.divWidth)) + 'px';  // same div is primary div
			else
			    dragDivMainStyle.left = dragDivRulerStyle.left =
				-(this.absLeft - (newAbsDivR * this.divWidth)) + 'px';  // same div is overflow div
		    }
		}
		// - both divs diff (scrap & rebuild)
		else if ((oldAbsDivL !== newAbsDivL) && (oldAbsDivR !== newAbsDivR)) {
		    ///debug ('2->2, scrap+rebuild');
		    this.scrapAndRebuild (newAbsDivL, newAbsDivR);
		}
		else {
		    // UNREACHABLE
		    bugAlert ('this should not occur');
		}
	    }  // closes if (newAbsDivR)
	    else {
		// FROM 2 TO 1 DIV

		// cases:
		// - div is same as one of the original 2
		if (newAbsDivL === oldAbsDivL) {
		    //debug ('2->1, nL = oL');

		    if (oldPrimaryDivNum !== oldAbsDivL) {
			// same div is overflow div; swap them, because it's easier to deal with
			this.swapPrimaryAndOverflow ();
		    }

		    // now, same div MUST be the primary div; remove overflow
		    this.deleteOverflow ();

		    if (motionType === 3) {
			dragDivMainStyle.left = dragDivRulerStyle.left =
			    (stripPx (dragDivRulerStyle.left) - deltaX) + 'px';
		    }
		}
		else if (newAbsDivL === oldAbsDivR) {
		    //debug ('2->1, nL = oR');

		    if (oldPrimaryDivNum !== oldAbsDivR) {
			// same div is overflow div; swap them, because it's easier to deal with
			this.swapPrimaryAndOverflow ();
		    }
		    
		    // now, same div MUST be the primary div; remove overflow
		    this.deleteOverflow ();

		    if (motionType === 3) {
			dragDivMainStyle.left = dragDivRulerStyle.left =
			    (stripPx (dragDivRulerStyle.left) - deltaX) + 'px';
		    }

		    //debug ('removed overflow, style points to: ' + innerDivRulerStyle.left);
		}
		// - div is diff (scrap & rebuild)
		else {
		    this.scrapAndRebuild (newAbsDivL);
		}
	    }
	}  // closes if (oldAbsDivR)
	else {
	    // FROM 1 DIV...

	    if (newAbsDivR) {
		// FROM 1 TO 2 DIVS

		// cases:
		// - one of 2 divs is same as original
		if (newAbsDivL === oldAbsDivL) {
		    //debug ('1->2, add overflow to RIGHT');

		    // add an overflow div to the RIGHT of primary div
		    this.makeOverflow (1);

		    if (motionType === 3)
			dragDivMainStyle.left = dragDivRulerStyle.left =
			    (stripPx (dragDivRulerStyle.left) - deltaX) + 'px';
		}
		else if (newAbsDivR === oldAbsDivL) {
		    //debug ('1->2, add overflow to LEFT');
		    
		    // add an overflow div to the LEFT of primary div
		    this.makeOverflow (-1);
		    
		    if (motionType === 3)
			dragDivMainStyle.left = dragDivRulerStyle.left =
			    (stripPx (dragDivRulerStyle.left) - deltaX) + 'px';
		}
		// - both divs are diff (scrap & rebuild)
		else {
		    //debug ('1->2, scrap+rebuild');
		    this.scrapAndRebuild (newAbsDivL, newAbsDivR);
		}
	    }
	    else {
		// FROM 1 TO 1 DIV

		// cases:

		if (oldAbsDivL === newAbsDivL) {
		    // - div is same
		    if (motionType === 3) {
			dragDivMainStyle.left = dragDivRulerStyle.left =
			    (stripPx (dragDivRulerStyle.left) - deltaX) + 'px';
		    }
		}
		else {
		    // - div is diff (scrap & rebuild)
		    this.scrapAndRebuild (newAbsDivL);
		}
	    }
	}
    }

    // update scroll bounds for dragging

    var primaryDivNum = (this.absLeft + stripPx (dragDivRulerStyle.left)) / this.divWidth;
    
    leftmostBound = -(landmarkWidth - (primaryDivNum * this.divWidth) -
		      stripPx (this.outerDivMain.style.width));

    //debug ('new scroll bound: ' + leftmostBound);

    // update tile cache after all state components are nice and consistent
    this.updateTiles();
}

//
// Updates browser state components that relate to vertical things, e.g. heights of tracks, their
// vertical layout, etc.
//
// This should be called after anything happens that might affect such state components, such as:
//   - zoom level change;
//   - hiding or unhiding a track.
//
// TODO: instead of having multiple loops, I could just iterate over track names and use 'getElementByID()'
// to fetch everything... but that might be (imperceptably) slower?  Although I would reduce overhead on many
// other operations...
//
function ViewerComponent_updateVertical () {
    //debug ('=== updateVertical() ===');

    /* make sure we are within bounds (must do this before ANYTHING else) */

    // compute total height of all visible tracks
    var visibleTrackHeight = 0;

    taz.getVisibleTrackNames ().each
	(function (track) {
	    visibleTrackHeight += taz.getHeightOfTrack (track);
	});

    //debug ('total track height = ' + visibleTrackHeight);

    // if we are displaying all tracks without vertical bounding the view, update the view height
    if (this.maxHeight)
	this.setViewHeight (visibleTrackHeight, true);

    // update vertical scroll bound
    if (visibleTrackHeight > stripPx (this.outerDivPanel.style.height))
	topmostBound = -(visibleTrackHeight - stripPx (this.outerDivPanel.style.height));
    else
	topmostBound = 0;  // if entire height fits into browser, don't allow vertical scrolling

    // vertical boundary check - if for some reason we jumped outside the vertical scroll bound, fix it
    if (stripPx (dragDivMainStyle.top) > 0)
	dragDivMainStyle.top = dragDivPanelStyle.top = dragDivTrackLabelsStyle.top = '0px';
    else if (stripPx (dragDivMainStyle.top) < topmostBound)
	dragDivMainStyle.top = dragDivPanelStyle.top = dragDivTrackLabelsStyle.top = topmostBound + 'px';

    /* update offsets of hovering track labels */

    // we'll need these to find the topmost visible track
    var topmostPixel = -stripPx (dragDivMainStyle.top);

    var trackNameRE = /(.*)_trackLabelDiv$/;  // for converting track label IDs to name of track

    var trackLabels = this.dragDivTrackLabels.childNodes;
    var heightSoFar = 0;
    for (var labelNum = 0; labelNum < trackLabels.length; labelNum++)
	{
	    var trackName = (trackLabels[labelNum].id.match (trackNameRE))[1];
	    trackLabels[labelNum].style.top = heightSoFar + 'px';

	    // maintain what the top visible track is, so we can correct its label positioning
	    if (heightSoFar <= topmostPixel)
		var topmostTrackLabel = trackLabels[labelNum];

	    heightSoFar += taz.getHeightOfTrack (trackName);
	}

    // topmostTrackLabel will be undefined if no tracks shown, so check for it
    if (topmostTrackLabel)
	// top of top track might go out of bounds, so correct its label to bind tightly to top of view
	topmostTrackLabel.style.top = topmostPixel + 'px';

    /* update track div heights */

    trackNameRE = /(.*)_trackDiv[PO]$/;  // for converting track IDs to name of track

    var allTracks = this.getTracks ();
    for (var trackNum = 0; trackNum < allTracks.length; trackNum++)
	{
	    var track = allTracks[trackNum];
	    trackName = (track.id.match (trackNameRE))[1];

	    track.style.height = taz.getHeightOfTrack (trackName) + 'px';
	}

    /* re-color the zebra stripes on vertical drag bar, since stripe layout could have changed */

    trackNameRE = /(.*)_panelDiv$/;

    var panelDivs = this.dragDivPanel.childNodes;
    for (divNum = 0; divNum < panelDivs.length; divNum++)
	{
	    trackName = (panelDivs[divNum].id.match (trackNameRE))[1];  // update height
	    panelDivs[divNum].style.height = taz.getHeightOfTrack (trackName) + 'px';

	    if (divNum % 2 == 0)
		panelDivs[divNum].style.background = '#333333';
	    else
		panelDivs[divNum].style.background = '#CCCCCC';
	}
}

//
// Updates the browser tile cache.  This is ALWAYS called at the end of updateHorizontal().
//
// This is because more or less tiles may become visible as a result of a horizontal state change, so the
// tile cache may need to be updated.  A 'cached tile' is just a tile that is appended to a track div,
// forcing the browser to load it.  Tiles that are too far outside of the visible area are detached from
// track divs and are no longer part of the document, therefore not 'cached' (and hopefully removed from
// memory by the browser).
//
// Note that tiles in hidden tracks are still cached, because the user might pop open that track on a
// moment's notice, although the hidden tile caching is done after visible tile caching completes, for a
// smoother UI.
//
// Tile div IDs are of the form:
//     <tile num>_<track name>_tileDiv
// where <tile num> must match the RE: [0-9]+
//
// NB: 'View' needs to be notified at the end so that the feature cache can be updated, among other things
// (whenever that is implemented, anyway...)
//
// TODO:
//   - tiles in surrounding zoom levels should be cached also, but AFTER the current zoom level is
//     fully cached (tricky to implement - is this worthwhile?);
//
function ViewerComponent_updateTiles () {
    //debug ('===UPDATING TILES...=== (absLeft = ' + this.absLeft + ')');

    //var start = new Date ();  // for profiling

    // make local copies of stuff we'll be using often, to try to reduce reference chain overhead
    // (esp. in loops)

    var divWidth = this.divWidth;
    var rulerTileCurrentPath = this.rulerTileCurrentPath;

    var oldFirstCachedTile = this.firstCachedTile;
    var oldLastCachedTile = this.lastCachedTile;

    //debug ('old cached tiles are ' + oldFirstCachedTile + ' ' + oldLastCachedTile);

    // compute which tiles should be cached
    var newFirstCachedTile = Math.floor (this.cacheBoundL / taz.tileWidth);
    var newLastCachedTile = Math.floor (this.cacheBoundR / taz.tileWidth);

    //debug ('cache should be tile # ' + newFirstCachedTile + ' through ' + newLastCachedTile);

    // figure out what tile range is covered by the primary divs (i.e., tiles outside of that range
    // will be appended to overflow divs)
    //
    var divFirstTile = Math.floor ((this.absLeft + stripPx (dragDivRulerStyle.left)) / taz.tileWidth);
    var divLastTile = divFirstTile + (divWidth / taz.tileWidth) - 1;

    //debug ('primary div spans tiles # ' + divFirstTile + ' through ' + divLastTile);

    /* REMOVE all tiles that should not be cached from the DOM tree */

    var tileNumRE = /^(\d+)_/;  // for extracting the tile number from the ID

    var allTiles = document.getElementsByClassName ('tileDiv', document.getElementById ('ViewerComponent'));
    allTiles.each
	(function (tile) {
	    var tileNum = (tile.id.match (tileNumRE))[1];
	    
	    if ((tileNum < newFirstCachedTile) || (tileNum > newLastCachedTile))
		tile.parentNode.removeChild (tile);  // out of range, needs to be removed
	});
    
    /* Cache the new RULER TILES */

    // iterate through tiles that should be cached
    for (var tileNum = newFirstCachedTile; tileNum <= newLastCachedTile; tileNum++)
	{
	    // only append tiles that aren't cached already (i.e. outside of old cached tiles interval)
	    if ((tileNum < oldFirstCachedTile) || (tileNum > oldLastCachedTile))
		{
		    var tileDiv = document.createElement ('div');
		    tileDiv.id = tileNum + '_ruler_tileDiv';
		    tileDiv.className = 'tileDiv';

		    tileDiv.style.left = ((tileNum * taz.tileWidth) % divWidth) + 'px';
		    tileDiv.style.top = '2px';  // offset a bit from top because it looks nicer

		    var img = document.createElement ('img');
		    img.id = tileNum + '_ruler_tileImg';
		    img.className = 'tileImg';
		    img.src = rulerTileCurrentPath + 'rulertile' + tileNum + '.png';

		    tileDiv.appendChild (img);

		    if ((tileNum >= divFirstTile) && (tileNum <= divLastTile))
			this.pDivRuler.appendChild (tileDiv);  // tile should be on primary div
		    else
			this.oDivRuler.appendChild (tileDiv);  // tile should be on overflow div
		}
	}

    /* Cache the new TRACK TILES */

    var tracks = this.getTracks ();
    var numTracks = tracks.length;
    var trackNameRE = /(.*)_trackDiv[PO]$/;  // for converting track IDs to name of track

    for (var trackNum = 0; trackNum < numTracks; trackNum++)
	{
	    var track = tracks[trackNum];
	    var trackName = (track.id.match (trackNameRE))[1];
	    var tilePrefix = taz.getTilePrefix (trackName);

	    // iterate through tiles that should be cached
	    for (var tileNum = newFirstCachedTile; tileNum <= newLastCachedTile; tileNum++)
		{
		    // only append tiles that aren't cached already (i.e. outside of cached tiles interval)
		    if ((tileNum < oldFirstCachedTile) || (tileNum > oldLastCachedTile))
			{
			    var tileDiv = document.createElement ('div');
			    tileDiv.id = tileNum + '_' + trackName + '_tileDiv';
			    tileDiv.className = 'tileDiv';
			    

			    tileDiv.style.left = ((tileNum * taz.tileWidth) % divWidth) + 'px';
		            track.appendChild (tileDiv);			    

			    
			    if (htmlFiles==1) {
			    	    // update the div element with html generate from generate tiles
				    var pars = '';
				    var url = tilePrefix + 'tile' + tileNum + '.html';
				    var imgURL = tilePrefix + 'tile' + tileNum + '.png';
				    var myAjax = new Ajax.Updater(
					tileDiv, 
					url, 
					{
						method: 'get', 
						parameters: pars,
						onComplete:ViewerComponent_UpdateData(),
						onFailure:ViewerComponent_Error(),
					}
				    );
			   } else {
				    var img = document.createElement ('img');
                        	    img.id = tileNum + '_' + trackName + '_tileImg';
                        	    img.className = 'tileImg';
                        	    img.src = tilePrefix + 'tile' + tileNum + '.png';
                        	    tileDiv.appendChild (img);
                        	    track.appendChild (tileDiv)
			    }
			    
			}
		}

	} // ends iteration over track divs

    this.firstCachedTile = newFirstCachedTile;
    this.lastCachedTile = newLastCachedTile;

    view.updateView();
 
    /*
    // for profiling
    var end = new Date ();
    var divs = this.oDivMain ? '(2 divs)' : '(1 div)';  // is there overflow?
    debug ('updateTiles() took ' + (end - start) + ' ms ' + divs);
    */
}

function ViewerComponent_Error (url) {
    /* Place holder for something to do when handling errors using the updater*/
}

function ViewerComponent_UpdateData (tile) {
   /*
   Place holder for further actions on loading the map data 
   One idea is to load in only the minimum image map data (the area info and coords)
   and then append the mouseover events etc
   */   

}
//------------------------
//     EVENT HANDLERS
//------------------------

//
// When user resizes window, we must resize browser contents.
//
// TODO: this will potentially get much more complex if more component dimensions/layout become based
// on the window dimensions.
//
function ViewerComponent_resizeBrowser (event) {

    // TODO: resize tracks control panel table width if it becomes window-size dependent!

    // make sure we preserve center nt; this calls updateHorizontal() downsteam, which will fix up the
    // view bounds per the new Web browser window size
    //
    this.setCenter (view.centerNt, 0);
}

/*
  NB:
  There is a lot of duplicate code across the drag functions.  I don't want to wrap it up in functions
  in order to avoid function call overhead - dragging must be as speedy as possible.  Be careful when
  changing any code, and make sure to change its duplicates!

  TODO: well... it really SHOULDN'T be a problem to aggregate at least the 'startMove' functions, no?
*/

//
// Handler for starting of horizontal-only dragging
//
function ViewerComponent_startMoveX (event) {
    dragging = true;

    window.onmousemove = ViewerComponent_processMoveX;  // assign event handler for horizontal-only motion
    dragStartLeft = event.clientX;  // get mouse coordinate of where we started dragging

    oldLeft = stripPx (dragDivMainStyle.left);  // save coordinate of div at drag start;
    oldTop = stripPx (dragDivMainStyle.top);    // yes, we NEED to save both left and top, because
                                                // they are both checked in stopMove()

    newLeft = oldLeft;  // so that they're never 'undefined'
    newTop = oldTop;

    // change the mouse cursor
    dragDivRulerStyle.cursor = dragDivMainStyle.cursor = '-moz-grab';
    // TODO: how to make cursor same EVERYWHERE in the document when dragging?
    //document.getElementById('browserBody').cursor = '-moz-grab';  // an unsuccessful attempt

    return false;  // necessary to prevent default browser action in responce to click
}

//
// Handler for starting of vertical-only dragging
//
function ViewerComponent_startMoveY (event) {
    dragging = true;

    window.onmousemove = ViewerComponent_processMoveY;  // assign event handler for vertical-only motion
    dragStartTop = event.clientY;  // get mouse coordinate of where we started dragging

    oldLeft = stripPx (dragDivMainStyle.left);  // save coordinate of div at drag start;
    oldTop = stripPx (dragDivMainStyle.top);    // yes, we NEED to save both left and top, because
                                                // they are both checked in stopMove()

    newLeft = oldLeft;  // so that they're never 'undefined'
    newTop = oldTop;

    // change the mouse cursor
    dragDivPanelStyle.cursor = dragDivMainStyle.cursor = '-moz-grab';
    // TODO: how to make cursor same EVERYWHERE in the document when dragging?
    //document.getElementById('browserBody').cursor = '-moz-grab';  // an unsuccessful attempt

    return false;  // necessary to prevent default browser action in responce to click
}

//
// Handler for starting of dragging via both horizonal and vertical axes
//
function ViewerComponent_startMoveXY (event) {
    dragging = true;

    window.onmousemove = ViewerComponent_processMoveXY;  // assign event handler
    dragStartLeft = event.clientX;  // get mouse coordinates of where we started dragging
    dragStartTop = event.clientY;

    oldLeft = stripPx (dragDivMainStyle.left);  // save coordinate of div at drag start;
    oldTop = stripPx (dragDivMainStyle.top);    // yes, we NEED to save both left and top, because
                                                // they are both checked in stopMove()

    newLeft = oldLeft;  // so that they're never 'undefined'
    newTop = oldTop;

    // change the mouse cursor
    dragDivPanelStyle.cursor = dragDivRulerStyle.cursor = dragDivMainStyle.cursor =
	'-moz-grab';
    // TODO: how to make cursor same EVERYWHERE in the document when dragging?
    //document.getElementById('browserBody').cursor = '-moz-grab';  // an unsuccessful attempt

    return false;  // necessary to prevent default browser action in responce to click
}

//
// Handler for processing horizontal-only dragging
//
function ViewerComponent_processMoveX (event) {
    //debug ('oldLeft: ' + oldLeft + ' eventX: ' + event.clientX + ' dragStart: ' + dragStartLeft);

    newLeft = oldLeft + event.clientX - dragStartLeft;

    //debug ('newLeft orig: ' + newLeft);

    // check for dragging out of bounds
    if (inFirstDiv && (newLeft > 0)) {
	// out of bounds (left of landmark), align left edge of landmark on the bound
	dragDivRulerStyle.left = dragDivMainStyle.left = '0px';
	newLeft = 0;
    }
    else if (newLeft < leftmostBound) {
	// out of bounds (right of landmark), align right edge of landmark on the bound
	dragDivRulerStyle.left = dragDivMainStyle.left = leftmostBound + 'px';
	newLeft = leftmostBound;
    }
    else {
	dragDivRulerStyle.left = dragDivMainStyle.left = newLeft + 'px';
    }

    //debug ('newLeft corr: ' + newLeft);
}

//
// Handler for processing vertical-only dragging
//
function ViewerComponent_processMoveY (event) {
    newTop = oldTop + event.clientY - dragStartTop;

    // check for dragging out of bounds
    if (newTop > 0) {
	dragDivPanelStyle.top = dragDivMainStyle.top = dragDivTrackLabelsStyle.top = '0px';
	newTop = 0;
    }
    else if (newTop < topmostBound) {
	dragDivPanelStyle.top = dragDivMainStyle.top = dragDivTrackLabelsStyle.top = topmostBound + 'px';
	newTop = topmostBound;
    }
    else {
	dragDivPanelStyle.top = dragDivMainStyle.top = dragDivTrackLabelsStyle.top = newTop + 'px';
    }
}

//
// Handler for starting of dragging via both horizonal and vertical axes
//
function ViewerComponent_processMoveXY (event) {
    newLeft = oldLeft + event.clientX - dragStartLeft;
    newTop = oldTop + event.clientY - dragStartTop;

    // check for dragging out of bounds (horizontal)
    if (inFirstDiv && (newLeft > 0)) {
	dragDivRulerStyle.left = dragDivMainStyle.left = '0px';
	newLeft = 0;
    }
    else if (newLeft < leftmostBound) {
	dragDivRulerStyle.left = dragDivMainStyle.left = leftmostBound + 'px';
	newLeft = leftmostBound;
    }
    else {
	dragDivRulerStyle.left = dragDivMainStyle.left = newLeft + 'px';
    }

    // check for dragging out of bounds (vertical)
    if (newTop > 0) {
	dragDivPanelStyle.top = dragDivMainStyle.top = dragDivTrackLabelsStyle.top = '0px';
	newTop = 0;
    }
    else if (newTop < topmostBound) {
	dragDivPanelStyle.top = dragDivMainStyle.top = dragDivTrackLabelsStyle.top = topmostBound + 'px';
	newTop = topmostBound;
    }
    else {
	dragDivPanelStyle.top = dragDivMainStyle.top = dragDivTrackLabelsStyle.top = newTop + 'px';
    }
}

//
// Handler for 'window.onmouseup'
//
function ViewerComponent_stopMove() {
    if (dragging) {
	dragging = false;
	window.onmousemove = undefined;  // disable mouse-motion event handling

	//debug ('old left, top: ' + oldLeft + ' ' + oldTop);
	//debug ('new left, top: ' + newLeft + ' ' + newTop);

	// vertical scrolling occured
	if (oldTop != newTop)
	    cif.updateVertical ();

	// horizontal scrolling occured
	if (oldLeft != newLeft)
	    cif.updateHorizontal (2, (oldLeft - newLeft));  // update horizontal state and cached tiles

	// reset cursor only after all of the above completes
	dragDivPanelStyle.cursor = dragDivRulerStyle.cursor = dragDivMainStyle.cursor = '';
    }
}

//
// Center the view horizontally on the double-clicked spot.
//
// TODO: make it center vertically as well
//
function ViewerComponent_centerView (event) {

    // event source coordinates are relative to the tile img... so we have to offset them using
    // the tile number to get the absolute pixel coordinate

    var tileNum = (event.target.id.match (/^(\d+)_/))[1];

    var centerXnew = event.layerX + tileNum * taz.tileWidth;
    var centerXold = this.absLeft + Math.floor (stripPx (this.outerDivMain.style.width) / 2);

    this.updateHorizontal (3, (centerXnew - centerXold));
}


//-------------------------
//     OTHER FUNCTIONS
//-------------------------

//
// Converts an absolute horizontal pixel value (0-based) to an integer genomic coordinate (1-based),
// i.e. returns the leftmost (lowest/first) nucleotide on which that pixel resides.
//
function ViewerComponent_pixelToNt (pixelValue) {
    // pixels * (units / pixel) = units
    return Math.floor (pixelValue * taz.getUnitsPerPixel()) + 1;
}

//
// Converts an integer genomic coordinate (1-based) to an absolute horizontal pixel value (0-based),
// i.e. returns the leftmost (lowest/first) pixel of that nucleotide.
//
function ViewerComponent_ntToPixel (nt) {
    // units / (units/tile) * (pixels/tile) = pixels
    return Math.floor ((nt / taz.getUnitsPerTile()) * taz.tileWidth);
}

