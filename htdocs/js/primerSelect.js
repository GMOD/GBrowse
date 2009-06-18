/*

 primersSelect.js -- a DHTML library for drag/rubber-band selection in gbrowse
                      This class handles primers-specific configuration.

 Sheldon McKay <mckays@cshl.edu>
 $Id: primerSelect.js,v 1.1.2.5 2009-06-18 11:22:25 sheldon_mckay Exp $

*/

var primersObject;

// Constructor
var Primers = function () {
  this.imageId    = 'detail_image';
  this.marginTop  = '35px';
  this.background = 'gray';
  this.fontColor  = 'blue';
  this.menuWidth  = '200px';
  return this;
}

// Inherit from base class SelectArea
Primers.prototype = new SelectArea();

// Primers-specific config.
Primers.prototype.initialize = function() {
  var self = new Primers;

  // If the primers have been designed, we are not needed
  if (document.mainform.configured && document.mainform.configured.value) return false;
  
  var i = document.getElementById(self.imageId);
  if (!i) return false;

  i = self.replaceImage(i);
  
  var p = document.getElementById('panels');
  self.height      = self.elementLocation(i,'height');
  self.panelHeight = self.elementLocation(p,'height');
  self.width       = self.elementLocation(i,'width');
  self.selectLayer = p;

  self.top     = self.elementLocation(i,'y1');
  self.bottom  = self.elementLocation(i,'y2');
  self.left    = self.elementLocation(i,'x1');
  self.right   = self.elementLocation(i,'x2');

  self.scalebar = i;
  self.getSegment(i);
  self.addSelectMenu('primer');
  self.addSelectBox('primer');

  self.image = i;

  // Get rid of top buttons if the image is not very tall and 
  // the bottom buttons are visible without scrolling down
  if (self.height < 600) {
    var buttons = document.getElementById('topButtons');
    if (buttons) {buttons.innerHTML = '';}	
  } 

  primersObject = self;
}

Primers.prototype.startSelection = function(event) {
  var self = primersObject;
  var evt = event || window.event;
  SelectArea.prototype.startRubber(self,event);
}

Primers.prototype.getSegment = function(i) {
    // get the segment info from gbrowse CGI parameters
    var segment      = document.mainform.segment.value;
    var myArray  = segment.match(/(\S+):([-0-9]+)\.\.([-0-9]+)/);
    this.ref          = myArray[1];
    this.segmentStart = parseInt(myArray[2]);
    this.segmentEnd   = parseInt(myArray[3]);
    this.padLeft      = parseInt(document.mainform.image_padding.value);
    this.pixelToDNA   = parseFloat(document.mainform.details_pixel_ratio.value);

    // If the keystyle is left, there may been extra padding
    var actualWidth   = this.elementLocation(i,'width');
    var expectedWidth = parseInt(document.mainform.detail_width.value);
    if (actualWidth > expectedWidth) {
	this.padLeft     += actualWidth - expectedWidth;
    }

    this.pixelStart   = this.left  + this.padLeft;
}

Primers.prototype.stopRubber = function(event) {
    balloonIsSuppressed = false;
    if (!selectAreaIsActive) {
	return false;
    }
    var self = currentSelectArea;
    document.mainform.lb.value = self.selectSequenceStart;
    document.mainform.rb.value = self.selectSequenceEnd;
    var width = self.selectSequenceEnd - self.selectSequenceStart;
    var rangeStart = width - 200;
    if (rangeStart < 50) {rangeStart = 50};
    var rangeEnd = width + 200;
    var sizeRange = rangeStart+ '-' +rangeEnd;
    document.mainform.PRIMER_PRODUCT_SIZE_RANGE.value = sizeRange;
    selectAreaIsActive = false;

    if (width) {
	var image = document.getElementById('panels');
        self.setOpacity(image,0.3,'black');
	document.mainform.submit();
    }
}

// null function
Primers.prototype.formatMenu = function() {}



