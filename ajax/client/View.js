// Written by Andrew Uzilov, November 2005 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//==================================================================================================
//
// The duty of this class is to store information about the genome and the part of it that we are
// looking at.  That is, an instance of this is a container for genomic information (genomic
// indices, data on features in current view and cached off-screen, etc.) and is also responsible
// for using XHR and other means to udpate its internals as the user scrolls/zooms around.
//
// (TODO: the XHR functionality is not implemented yet, but will be eventually... the idea is that
// Components will use accessor methods to get information about what we are looking at from this
// class, and this class is a holder for all genome view state info, including features.)
//
// It is the responsibility of others to call 'updateView()' on an instance of this class whenever
// something affecting the view takes place.  An instance of this class will NOT update itself
// automatically otherwise.
//
// This class provides accessors to get information about the part of the genome, etc. that the
// user is looking at.
//
// TODOs and NOTES:
//
// - Put in a stub for saving and restoring a Browser or View object for bookmarking purposes.
//
// - Asynchrony will be a major issue here...
//
// - Direct reads of members of other objects should be replaced with calls to accessors, to prevent
//   accidentally changing the other objects properties.
//
//==================================================================================================


//---------------------
//     CONSTRUCTOR
//---------------------
//
// This constructor should only load stuff into 'View' object data members; it should NOT
// have any active function (i.e. do not cause other things to execute, just load data).
//
function View (xmlDoc) {

    /* initialize data members based on XML file data */

    // landmark dimensions ("name" is the human-readable name, "id" is the GFF(?)/etc.
    // landmark identifier)
    var landmark = xmlDoc.getElementsByTagName ("landmark")[0];
    this.landmarkName   = landmark.getAttribute ("name");
    this.landmarkStart  = parseInt (landmark.getAttribute ("start"), 10);
    this.landmarkEnd    = parseInt (landmark.getAttribute ("end"), 10);
    this.landmarkID     = landmark.getAttribute ("id")
    this.landmarkLength = this.landmarkEnd - this.landmarkStart + 1;

    // default zoom level specified by XML
    this.currentZoomLevel =
	xmlDoc.getElementsByTagName("defaults")[0].getAttribute("zoomlevelname");

    // what's visible in the genome view box (to to be initialized later)
    this.leftmostNt;
    this.rightmostNt;
    this.centerNt;  // for preserving horizontal centering when changing zoom levels
    // TODO: need state variables for keeping track of VERTICAL CENTERING

    // Associate methods

    // other methods
    this.updateView = View_updateView;

    // TODO:
    //
    // other data members we should definately have:
    //   - collection of all visible and off-screen-cached features and their info (hard)
}


//-------------------
//     ACCESSORS
//-------------------


//-------------------
//     MODIFIERS
//-------------------

//
// Updates state variables (TODO: and cached feature info); this should be called whenever an event
// takes place that changes the genome portion that the user is looking at, such as zoom level
// changes, scrolling, window resizing, etc.
//
function View_updateView() {

    // the nucleotide indices should be based on whatever pixel coordinates ViewerComponent stores
    // for left/right visible bounds (otherwise we might get a discontinuity between state of
    // ViewerComponent and View)

    this.leftmostNt = cif.pixelToNt (cif.getAbsLeft ());
    this.rightmostNt = cif.pixelToNt (cif.getAbsRight ());
    this.centerNt = this.leftmostNt + Math.floor ((this.rightmostNt - this.leftmostNt) / 2);

    // update the banner - TODO: this should go into a Component somewhere, no?
    document.getElementById('landmarkname').innerHTML =
	this.landmarkName +
	' (spans [' + this.landmarkStart + ',' + this.landmarkEnd + ']): showing [' + 
	this.leftmostNt + ',' + this.rightmostNt + '], centered on ' + this.centerNt + ' (view width: ' +
	stripPx (cif.getOuterDivMain().style.width) +
	' pixels)';
}
