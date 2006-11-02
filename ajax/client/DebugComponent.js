// Written by Andrew Uzilov, September 2006 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//==================================================================================================
// All the stuff for debugging goes here.  As such, most design rules don't apply to this
// Component - it's special.
//==================================================================================================


//------------------
//     GLOBALS
//------------------

var nudgeLeft = DebugComponent_nudgeLeft;
var nudgeRight = DebugComponent_nudgeRight;
var stupidTestBoxHandler = DebugComponent_stupidTestBoxHandler;


//----------------------------------------
//     CONSTRUCTORS AND INITIALIZERS
//----------------------------------------

function DebugComponent () {
    // should add a ref to each internal accessor function to componentInterface
    // (TODO: this is not implemented yet)

    this.renderComponent = DebugComponent_renderComponent;
    this.getState = DebugComponent_getState;
    this.setState = DebugComponent_setState;
}

//
// TODO: stub for constructing the DOM node for this Component; currently, things are
// more-or-less hardcoded in XHTML or in the constructor... ideally though, the Component
// should render itself based solely on info from XML and/or default values - the Load class
// will call this function, get the DOM node back, and append it to the document tree.
//
function DebugComponent_renderComponent () {
    // TODO: write me!

    //return domNode;
}


//-------------------
//     ACCESSORS
//-------------------

//
// TODO: stub for "return state" for bookmarking feature - every Component must implement one!
//
function DebugComponent_getState () {
    // not implemented yet
}


//-------------------
//     MODIFIERS
//-------------------

//
// TODO: stub for "restore state" for bookmarking feature - every Component must implement one!
//
function DebugComponent_setState (stateObj) {
    // not implemented yet
}


//------------------------
//     EVENT HANDLERS
//------------------------

//
// Handlers for nudging the view left/right by just one pixel
//
function DebugComponent_nudgeLeft () {
    debug ('nudging left...');
    cif.updateHorizontal (3, -1);
}
function DebugComponent_nudgeRight () {
    debug ('nudging right...');
    cif.updateHorizontal (3, 1);
}

//
// Handlers whatever damn thing I'm testing at the moment.
//
function DebugComponent_stupidTestBoxHandler (event) {
    var input = document.getElementById('stupidTestBox').value;

    /* now comes the "whatever I feel like" testing phase... */

    //debug ('cif.getAbsLeft () returns: ' + cif.getAbsLeft ());
    //debug ('setting absLeft to ' + value);    
}


//-------------------------
//     OTHER FUNCTIONS
//-------------------------

