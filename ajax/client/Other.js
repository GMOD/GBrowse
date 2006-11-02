// Written by Andrew Uzilov, November 2005 - current
// Laboratory of Dr. Ian Holmes
// Department of Bioengineering
// University of California - Berkeley
// Berkeley, CA, USA
//

// HODGE-PODGE - helpers for other libraries and debugging stuff (TODO: explain and organize !!!)

/*
  declare globals here, cuz this "library" gets "included" first
  (until I can figure out a better way to do this)
*/
var view, taz, cif;
var xmlFilePath = "tileinfo.xml";  // stores track and tile info, and other settings

// color gradient for the track control panel backgrounds (THIS IS TEMPORARY !!! - we intend to make the track
// labels "hover" over the tracks themselves, so the backgrounds will be transparent
var colorArray = new Array("000000",
			   "000033",
			   "000066",
			   "000099",
			   "0000CC",
			   "0000FF",
			   "003300",
			   "003333",
			   "003366",
			   "003399",
			   "0033CC",
			   "0033FF",
			   "006600",
			   "006633",
			   "006666",
			   "006699",
			   "0066CC",
			   "0066FF");

var debugMessageNum;  // for debugging

// Displays debug messages (those that are for DEVELOPMENT ONLY) in the message console
function debug(text) {
    var debugMessage = document.getElementById("debugMessage");
    debugMessage.value = debugMessageNum + ") " + text + "\n" + debugMessage.value;
    debugMessageNum++;
}

// Displays messages for user (those that SHOULD GO TO PRODUCTION) in the message console
function message(text) {
    var debugMessage = document.getElementById("debugMessage");
    debugMessage.value = debugMessageNum + ") " + text + "\n" + debugMessage.value;
    debugMessageNum++;
}

// Pops up a 'bug alert' thing encouraging user to report a bug.
//
// TODO: this is more or less a stub for an automated bug-reporting function that can redirect
// the user to a bug report page, or just collect state info and send it to us.
function bugAlert(text) {
    var bugMessage =
	'OOPS! An internal Genome Browser error has occured (this is not your fault).\n\n' +
	'You may want to report this error, and the conditions under which it occured, ' +
	'to the programmer (http://biowiki.org/AndrewUzilov) so he can fix it.\n\n' +
	'The error is:\n' +
	text;

    alert(bugMessage);
}

// This is supposed to be used solely to remove the suffix 'px' from the end of 'value'
//
// TODO: this should really use a regexp to correct for potential caller misuse...
//
function stripPx(value) {
    if (value == "") return 0;
    return parseInt (value.substring(0, value.length - 2), 10);
}

//
// Returns the first child of DOM Node 'node' whose id attribute matches 'id',
// or null if there is no such child or if there is some other error.
//
// There SHOULDN'T be multiple nodes with the same id, so this SHOULD be
// equivalent to 'getElementById()' restricted to only children.
//
// TODO: this should be a Node "class" method (if possible) instead of a stupid
// global func, i.e. invoked like:
//   someNode.getChild (id);
//
// TODO: make more error-safe (e.g. no childNodes? not found?)
//
function getChild (node, id) {
    if ((!node) || (!id)) {
	bugAlert ('no node or id passed to getChild()');
	return null;
    }

    var children = node.childNodes;
    for (var i = 0; i < children.length; i++)
	if (children[i].id === id)
	    return children[i];

    return null;
}

//
// Removes and returns the first child of DOM Node 'node' whose id attribute matches 'id',
// or null if no such child or some other error.
//
// There SHOULDN'T be multiple children with the same 'id', so first child = only child,
// but this is never checked for.
//
// TODO: this should be a Node "class" method (if possible) instead of a stupid
// global func, i.e. invoked like:
//   someNode.findAndRemoveChild (id);
//
// TODO: make more error-safe (e.g. no childNodes? not found?)
//
function findAndRemoveChild (node, id) {
    if ((!node) || (!id)) {
	bugAlert ('getChild(' + node + ',' + id + '): no node or id passed in');
	return null;
    }

    var children = node.childNodes;
    for (var i = 0; i < children.length; i++)
	if (children[i].id === id)
	    return node.removeChild (children[i]);

    return null;    
}

//
// Inserts 'node' after 'referenceNode' in the children of 'parent'.
//
// Not mine, got it from: http://www.webknowhow.net/dir/Advanced/articles/top10JSfunctionsDiaz.html
//
// TODO: this should be a Node "class" method, if possible.
//
function insertAfter (parent, node, referenceNode) {
    if ((!parent) || (!node) || (!referenceNode)) {
	bugAlert ('insertAfter(' + parent + ',' + node + ',' + referenceNode + '): an argument is missing');
	return;
    }
    else {
        parent.insertBefore (node, referenceNode.nextSibling);
    }
}

// Computes the overlap of two integer intervals.  Returns the overlap as a 2-item array of the start and
// end indices (start <= end, always), or empty array if no overlap.
//
// Note there is no input correctness checking, so make sure start <= end in your input intervals.
//
// TODO: this works but there is something wrong with parsing return values on the caller end...
//
function getOverlap(inter1_start, inter1_end, inter2_start, inter2_end) {
    debug ('must find overlap of [' + inter1_start + ',' + inter1_end + '] and [' + inter2_start + ',' + inter2_end + ']');
    var retinter = [];
    if ( (inter1_start <= inter2_end) && (inter1_end >= inter2_start) ) {  // is there any overlap?
	retinter[0] = ((inter1_start < inter2_start) ? inter2_start : inter1_start);
	retinter[1] = ((inter1_end < inter2_end) ? inter1_end : inter2_end);
	debug ('computed overlapping interval of [' + retinter[0] + ',' + retinter[1] + ']');
    }
    else {
	debug ('no overlapping interval');
    }
    return retinter;
}