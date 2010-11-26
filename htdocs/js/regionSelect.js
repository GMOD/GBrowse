/*

 regionSelect.js -- a DHTML library for drag/rubber-band selection in gbrowse
                      This class handles region-specific configuration.

 Sheldon McKay <mckays@cshl.edu>
 $Id$

*/

var regionObject;
var regionBalloon;

// Constructor
var Region = function () {
  this.imageId    = 'Region Scale_image';
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
Region.prototype = new SelectArea();

// Region-specific config.
Region.prototype.initialize = function() {
  var self = new Region;

  // not ready for non drag and drop implementation
  //var dnd = document.mainform.drag_and_drop;
  //if (!dnd || !dnd.checked) return false;


  var i = $(self.imageId);;
  if (!i) return false;


  var img = document.getElementsByName('region');
  for (var n = 0;n < img.length; n++) {
    if (img[n].getAttribute('src')) {
      var nullFunc = function(){return false};
      img[n].onclick = nullFunc;      
    }
  }


  var p = i.parentNode.parentNode;
  i = self.replaceImage(i);

  self.selectLayer = p.parentNode.parentNode;
  self.scalebar = i;
  self.addSelectMenu('region');
  self.addSelectBox('region');
  regionObject = self;
}

Region.prototype.startSelection = function(event) {
  var self = regionObject;
  var evt = event || window.event;
  SelectArea.prototype.startRubber(self,event);
}

Region.prototype.loadSegmentInfo = function() {
  // get the segment info from gbrowse CGI parameters
  var self = regionObject;
  var i = $(self.imageId);
  
  var segment_info = Controller.segment_info;
  
  this.ref          = segment_info.ref;
  this.segmentStart = parseInt(segment_info.region_start);
  this.segmentEnd   = parseInt(segment_info.region_stop);
  this.flip         = 0;
  this.padLeft      = parseInt(segment_info.image_padding);
  this.pixelToDNA   = parseFloat(segment_info.region_pixel_ratio);
  this.detailStart  = parseInt(segment_info.detail_start);
  this.detailEnd    = parseInt(segment_info.detail_stop);
  this.max_segment  = parseInt(segment_info.max_segment);

  // If the keystyle is left, there may been extra padding
  var actualWidth   = this.elementLocation(i,'width');
  var expectedWidth = parseInt(segment_info.overview_width);
  if (actualWidth > expectedWidth) {
    this.padLeft     += actualWidth - expectedWidth;
  }

  this.pixelStart   = this.padLeft;
}

Region.prototype.formatMenu = function() {
  this.menuHTML = this.selectMenu.innerHTML || '\
   <div style="padding:5px;text-align:center">\
     <b>SELECTION</b><hr>\
     <a href="javascript:SelectArea.prototype.clearAndSubmit()">' + Controller.translate('ZOOM') + '</a>\
     &nbsp;&nbsp;|&nbsp;&nbsp;\
     <a href="javascript:SelectArea.prototype.cancelRubber()">' + Controller.translate('CANCEL') + '</a>\
  </div>';
}

