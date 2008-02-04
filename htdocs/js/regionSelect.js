/*

 regionSelect.js -- a DHTML library for drag/rubber-band selection in gbrowse
                      This class handles region-specific configuration.

 Sheldon McKay <mckays@cshl.edu>
 $Id: regionSelect.js,v 1.1.2.3 2008-02-04 21:51:05 sheldon_mckay Exp $

*/

var regionObject;

// Constructor
var Region = function () {
  this.imageId    = '__scale___image';
  this.imageName  = 'region';
  this.marginTop  = '5px';
  this.background = 'yellow';
  this.opacity    = 0.7;
  this.fontColor  = 'blue';
  this.border     = '1px solid black';
  this.menuWidth  = '160px';
  return this;
}

// Inherit from base class SelectArea
Region.prototype = new SelectArea();

// Region-specific config.
Region.prototype.initialize = function() {
  var self = new Region;

  // not ready for non drag and drop implementation
  var dnd = document.mainform.drag_and_drop;
  if (!dnd || !dnd.checked) return false;


  var images = document.getElementsByName(self.imageName);
  var i;
  for (var n=0; n < images.length; n++) {
    if (images[n].id == self.imageId) {
      i = images[n];
    }
    // disable other image buttons
    else if (images[n].getAttribute('src')) {
      var nullFunc = function(){return false};
      images[n].onclick = nullFunc;      
    }
  }
  if (!i) return false;

  var p = i.parentNode;
  i = self.replaceImage(i);

  self.top     = self.elementLocation(i,'y1');
  self.bottom  = self.elementLocation(i,'y2');
  self.left    = self.elementLocation(i,'x1');
  self.right   = self.elementLocation(i,'x2');
  self.selectLayer = p.parentNode.parentNode;

  if (balloon) {
    var helpFunction = function(event) { 
      if (!event) {
        event = window.event;
      }
      var help = '<b>Region:</b> Click here to recenter or click and drag left or right to select a region';
      balloon.showTooltip(event,help,0,250);
    }
    i.onmouseover = helpFunction;
  }
  else {
    i.setAttribute('title','click and drag to select a region');
  }

  self.scalebar = i;
  self.getSegment();
  self.addSelectMenu('region');
  self.addSelectBox('region');
  regionObject = self;
}

Region.prototype.startSelection = function(event) {
  var self = regionObject;
  var evt = event || window.event;
  SelectArea.prototype.startRubber(self,event);
}

Region.prototype.getSegment = function() {
  // get the segment info from gbrowse CGI parameters
  this.ref          = document.mainform.ref.value;
  this.segmentStart = parseInt(document.mainform.region_start.value);
  this.segmentEnd   = parseInt(document.mainform.region_stop.value);
  this.flip         = document.mainform.flip.checked;
  this.padLeft      = parseInt(document.mainform.image_padding.value);
  this.pixelToDNA   = parseFloat(document.mainform.region_pixel_ratio.value);
  this.pixelStart   = this.left  + this.padLeft;
}

Region.prototype.formatMenu = function() {
  this.menuHTML = this.selectMenu.innerHTML || '\
   <div style="padding:5px;text-align:center">\
     <b>SELECTION</b><hr>\
     <a href="javascript:SelectArea.prototype.clearAndSubmit()">Zoom</a>\
     &nbsp;&nbsp;|&nbsp;&nbsp;\
     <a href="javascript:SelectArea.prototype.cancelRubber()">Cancel</a>\
  </div>';
}

