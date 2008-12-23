/*

 overviewSelect.js -- a DHTML library for drag/rubber-band selection in gbrowse
                      This class handles overview-specific configuration.

 Sheldon McKay <mckays@cshl.edu>
 $Id: overviewSelect.js,v 1.6 2008-12-23 08:07:12 lstein Exp $

*/

var overviewObject;
var overviewBalloon;

// Constructor
var Overview = function () {
  this.imageId    = 'Overview Scale_image';
  this.autoSubmit = true;
  this.marginTop  = '5px';
  this.background = 'yellow';
  this.opacity    = 0.7;
  this.fontColor  = 'blue';
  this.border     = '1px solid black';
  this.menuWidth  = '160px';
  return this;
}

// Inherit from base class SelectArea
Overview.prototype = new SelectArea();

// Overview-specific config.
Overview.prototype.initialize = function() {
  var self = new Overview;

  // not ready for non drag and drop implementation
  //var dnd = document.mainform.drag_and_drop;
  //if (!dnd || !dnd.checked) return false;

  var i = document.getElementById(self.imageId);
  if (!i) return false;

  var images = document.getElementsByName('region');
  
  var img = document.getElementsByName('overview');
  for (var n = 0;n < img.length; n++) {
    if (img[n].getAttribute('src')) {
      var nullFunc = function(){return false};
      img[n].onclick = nullFunc;
    }
  }

  var p = i.parentNode;
  i = self.replaceImage(i);

  self.top     = self.elementLocation(i,'y1');
  self.bottom  = self.elementLocation(i,'y2');
  self.left    = self.elementLocation(i,'x1');
  self.right   = self.elementLocation(i,'x2');
  self.selectLayer = p.parentNode.parentNode;

//   try {
//       overviewBalloon = new Balloon();
//       overviewBalloon.vOffset  = 1;
//       overviewBalloon.showOnly = 2; // just show twice
//       var helpFunction = function(event) {
// 	  if (!event) {
// 	      event = window.event;
// 	  }
// 	  var help = '<b>Overview:</b> Click here to recenter or click and drag left or right to select a region';
// 	  overviewBalloon.showTooltip(event,help,0,250);
//       }
//       i.onmouseover = helpFunction;
//   }
//   catch(e) {
//       i.setAttribute('title','click and drag to select a region');
//   }

  self.scalebar = i;
  self.addSelectMenu('overview');
  self.addSelectBox('overview');
  overviewObject = self;
}

Overview.prototype.startSelection = function(event) {
  var self = overviewObject;
  var evt = event || window.event;
  SelectArea.prototype.startRubber(self,event);
}

Overview.prototype.loadSegmentInfo = function() {
  // get the segment info from gbrowse CGI parameters
  
  var i = document.getElementById(self.imageId);

  var segment_info = Controller.segment_info;

  this.ref          = segment_info.ref;
  this.segmentStart = parseInt(segment_info.overview_start);
  this.segmentEnd   = parseInt(segment_info.overview_stop);
  this.flip         = 0;
  this.padLeft      = parseInt(segment_info.image_padding);
  this.pixelToDNA   = parseFloat(segment_info.overview_pixel_ratio);
  this.detailStart  = parseInt(segment_info.detail_start);
  this.detailEnd    = parseInt(segment_info.detail_stop);
  this.max_segment  = parseInt(segment_info.max_segment);

  // If the keystyle is left, there may be extra padding
  var actualWidth   = this.elementLocation(i,'width');
  var expectedWidth = parseInt(segment_info.overview_width);
  if (actualWidth > expectedWidth) {
    this.padLeft     += actualWidth - expectedWidth;
  }

  // We fetch the left margin again because the controller can change 
  // the size & position of the section after it is created.
  this.left       = this.elementLocation(document.getElementById(this.imageId),'x1');

  this.pixelStart = this.left  + this.padLeft;
}

Overview.prototype.formatMenu = function() {
  this.menuHTML = this.selectMenu.innerHTML || '\
   <div style="padding:5px;text-align:center">\
     <b>SELECTION</b><hr>\
     <a href="javascript:SelectArea.prototype.clearAndSubmit()">Zoom</a>\
     &nbsp;&nbsp;|&nbsp;&nbsp;\
     <a href="javascript:SelectArea.prototype.cancelRubber()">Cancel</a>\
  </div>';
}

