// Written by Andrew Uzilov, November 2005 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//==================================================================================================
//
// This is the genome browser library that "ties everything together."  It loads the browser
// configuration XML and, after ensuring all of it loaded completely, instantiates all necessary
// objects in the correct order, then initializes and renders everything necessary to actually
// start using the genome browser.
//
// The 'loadBrowser()' function is intended to be the 'onload' event handler/listener for the body
// of the genome browser XHTML.  It initiates a cascade of functions in this library that perform
// the above functions.  Because this library's function is to make all the other libraries work
// with each other to provide the genome browser, this library MUST BE LOADED LAST in the XHTML
// file, so that the contents of all the other libraries are available to it.
//
//==================================================================================================


//
// This is the 'onload' event handler for 'body' in the genome browser XHTML; this function is just a
// driver that sets up the genome browser by launching a cascade of functions that:
//   - load settings from the XML file (TODO: or maybe multiple XML files or via XHR);
//   - once those are loaded, instantiates the global objects in the proper order;
//   - configures those objects, etc. to make the browser ready for use.
//
function loadBrowser() {

    debugMessageNum = 0;  // reset debugging message box from 'Other.js'

    // reset text boxes
    document.getElementById("debugMessage").value = "";

    // for debugging only - if you remove the XHTML element, this will not crash
    var toTileBoxContents = document.getElementById("toTile");
    if (toTileBoxContents) {
	toTileBoxContents.value = 0;
    }

    // the second argument is the function we want to execute when the XML file completes loading
    loadXML(xmlFilePath, configureBrowser);

    // TODO: maybe create and append a "loading XML file..." thingie to the page?
}

//
// Loads the XML file; 'handlerFunction()' executes when loading is complete
// (function code taken mostly from O'Reilly's "JavaScript: The Definitive Guide" 4th Edition,
// pp 301-302)
//
function loadXML(xmlURL, handlerFunction) {

    var xmlDoc;

    // check for DOM Level 2 compatibility
    if (document.implementation && document.implementation.createDocument) {
	// create a new Document object
	xmlDoc = document.implementation.createDocument("", "", null);

	// specify what to do when it finishes loading
	xmlDoc.onload = function () { 
            landmarks = $A(xmlDoc.getElementsByTagName('landmark'));
            configs = $A(xmlDoc.getElementsByTagName('config'));
            handlerFunction(configs[0], landmarks[0], xmlURL) 
        }

	// load the XML document
	xmlDoc.load(xmlURL);
    }
    // otherwise, use Microsoft's proprietary API for IE
    else if (window.ActiveXObject) {
	xmlDoc = new ActiveXObject("Microsoft.XMLDOM");  // create doc
	xmlDoc.onreadystatechange = function() {  // specify onload
	    if (xmlDoc.readyState == 4) {
                landmarks = $A(xmlDoc.getElementsByTagName('landmark'));
                configs = $A(xmlDoc.getElementsByTagName('config'));
                handlerFunction(configs[0], landmarks[0], xmlURL) 
            }
	}
	xmlDoc.load(xmlURL);  // load the XML document
    }
    else {
	debug("ERROR: cannot load " + xmlURL + " (not supported by browser)!");
	// TODO: this should really instead redirect to a detailed error/bug report page
	return;
    }
}

//
// Lays out and prepares the browser for use by instantiating the global objects and configuring
// them.
//
// As this is currently the 'onload' handler for a single XML configuration file, this gets
// executed ONLY when the XML is completely loaded.  TODO: if/when we move to multiple XML files,
// and/or to using XHR, this clearly will need to change, as the point of this function is to
// execute ONLY WHEN ALL THE BROWSER CONFIGURATION DATA IS LOADED!
//
function configureBrowser(config, landmark, xmlURL) {

    // test to see if the page actually loaded by checking for the expected head node
    if (config.getElementsByTagName("tile").length == 0) {
	debug("ERROR: cannot load " + xmlURL + " (error reading file)!");
	// TODO: this should really instead redirect to a detailed error/bug report page
	// (or at least render a "error" on the main page by appending to DOM)
	return;
    }

    // TODO: for now, I will just assume all variables load correctly... although this may NOT be true,
    // and we NEED to check this and redirect to error page if that is the case
    
    // TODO: also note we are assuming there is only 1 of each tag we pull up in the XML file (so the
    // array index is always 0) - but will this always be the case?  Should this be done better?

    /* instantiate globals that are dependent on XML */

    view = new View (config, landmark);
    taz = new TracksAndZooms (config, landmark);
    cif = new ComponentInterface ();

    /* instantiate all the components */

    // TODO: eventually this code should be automated (autoload all the accessor methods into
    // ComponentInterface instance somehow) - but for now, everything is hardcoded: we manually
    // add refs to components to the ComponentInterface object

    cif.viewerComponent = new ViewerComponent ();
    cif.navigationComponent = new NavigationComponent ();
    cif.trackControlComponent = new TrackControlComponent ();
    cif.debugComponent = new DebugComponent ();

    // create the hardcoded accessors in ComponentInterface
    cif.createRefs ();

    // some things need to be run AFTER the references through ComponentInterface are built...
    // so we run them here (TODO: this will be replaced by an automated call to renderComponent()
    // of ALL Components, which will return the DOM tree node to be appended to document)

    var placeholder = document.getElementById ('ViewerComponent');

    placeholder.parentNode.replaceChild (cif.viewerComponent.renderComponent (),
					 placeholder);

    cif.navigationComponent.renderComponent ();  // (ignore return value for now)

    //debug('current zoom level is: ' + view.currentZoomLevel);
    //debug('tracks are: ' + taz.getTrackNames());
    //debug('zoom levels are: ' + taz.getZoomLevelNames());

    message ('GENOME BROWSER LOADED SUCCESSFULLY... welcome!');
}
