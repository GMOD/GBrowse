// Written by Andrew Uzilov, September 2006 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//==================================================================================================
//
// A template for how Component classes should be constructed.
//
// The internals of an instance of a Component store the "nitty-gritty", such as:
//   - internal references to all often-accessed elements (e.g. nodes of the DOM tree, so we don't
//     have to search the tree every time we need some element)
//   - properties, dimensions, etc. of the Component
//   - event handlers for the Component
//   - everything necessary for rendering/layout
//   TODO:
//   - a function or some other system to give ComponentInterface some automated way of creating
//     interface to this Component
//   - a method for constructing and returning the DOM node for this Component
//   - a method to return state information for bookmarking
//   - a method to set state (i.e. restore from bookmark)
//
// Note that information about WHAT we're looking at (such as visible and cached features, genomic
// indices, etc.) are stored in an instance of the 'View' object, so components have to query it
// for things like:
//   - [TODO: write me!]
//
//==================================================================================================


//----------------------------------------
//     CONSTRUCTORS AND INITIALIZERS
//----------------------------------------

function WhateverComponent () {
    // should add a ref to each internal accessor function to componentInterface
    // (TODO: this is not implemented yet)

    this.renderComponent = WhateverComponent_renderComponent;
    this.getState = WhateverComponent_getState;
    this.setState = WhateverComponent_setState;
}

//
// TODO: stub for constructing the DOM node for this Component; currently, things are
// more-or-less hardcoded in XHTML or in the constructor... ideally though, the Component
// should render itself based solely on info from XML and/or default values - the Load class
// will call this function, get the DOM node back, and append it to the document tree.
//
function WhateverComponent_renderComponent () {
    // TODO: write me!

    //return domNode;
}


//-------------------
//     ACCESSORS
//-------------------

//
// TODO: stub for "return state" for bookmarking feature - every Component must implement one!
//
function WhateverComponent_getState () {
    // not implemented yet
}


//-------------------
//     MODIFIERS
//-------------------

//
// TODO: stub for "restore state" for bookmarking feature - every Component must implement one!
//
function WhateverComponent_setState (stateObj) {
    // not implemented yet
}


//------------------------
//     EVENT HANDLERS
//------------------------


//-------------------------
//     OTHER FUNCTIONS
//-------------------------

