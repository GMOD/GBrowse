/*

 detailsSelect.js -- a DHTML library for drag/rubber-band selection in gbrowse
                      This class handles details-specific configuration.

 Sheldon McKay <mckays@cshl.edu>
 $Id$

*/

var detailsObject;
var detailBalloon;

// Constructor
var Details = function () {
  this.imageId    = 'Detail Scale_image';
  this.marginTop  = '35px';
  this.background = 'yellow';
  this.fontColor  = 'blue';
  this.border     = '1px solid black';
  this.menuWidth  = '200px';
  return this;
}

// Inherit from base class SelectArea
Details.prototype = new SelectArea();

// Details-specific config.
Details.prototype.initialize = function() {
  var self = new Details;
  
  var i = $(self.imageId);
  if (!i) return false;

  i = self.replaceImage(i);
  

  //var p = $('panels');
  var p = i.parentNode.parentNode;
  self.height      = self.elementLocation(i,'height');
  self.panelHeight = self.elementLocation(p,'height');
  self.width       = self.elementLocation(i,'width');
  self.selectLayer = p.parentNode.parentNode;

//   try {
//       detailBalloon = new Balloon();
//       detailBalloon.vOffset  = 1;
//       detailBalloon.showOnly = 2; // just show twice
//       var helpFunction = function(event) {
// 	  if (!event) {
// 	      event = window.event;
// 	  }
// 	  var help = '<b>Scalebar:</b> Click here to recenter or click and drag left or right to select a region';
// 	  detailBalloon.showTooltip(event,help,0,250);
//       }
//       i.onmouseover = helpFunction;
//   }
//   catch(e) {
//       i.setAttribute('title','click and drag to select a region');
//   }

  self.scalebar = i;
  self.addSelectMenu('detail');
  self.addSelectBox('detail');
  detailsObject = self;
}

Details.prototype.startSelection = function(event) {
  var self = detailsObject;
  var evt = event || window.event;
  SelectArea.prototype.startRubber(self,event);
}

Details.prototype.loadSegmentInfo = function() {
  // get the segment info from gbrowse CGI parameters
  var self = detailsObject;
  var i = $(self.imageId);
  
  var segment_info = Controller.segment_info;

  this.ref          = segment_info.ref;
  this.segmentStart = parseInt(segment_info.detail_start);
  this.segmentEnd   = parseInt(segment_info.detail_stop);
  this.flip         = segment_info.flip;
  this.padLeft      = parseInt(segment_info.image_padding);
  this.pixelToDNA   = parseFloat(segment_info.details_pixel_ratio);
  this.detailStart  = parseInt(segment_info.detail_start);
  this.detailEnd    = parseInt(segment_info.detail_stop);
  this.max_segment  = parseInt(segment_info.max_segment);

  // If the keystyle is left, there may been extra padding
  var actualWidth   = this.elementLocation(i,'width');
  var expectedWidth = parseInt(segment_info.detail_width);
  if (actualWidth > expectedWidth) {
    this.padLeft     += actualWidth - expectedWidth;
  }

  // We fetch the left margin again because the controller can change 
  // the size & position of the section after it is created.
  this.left       = this.elementLocation($(this.imageId),'x1') - this.elementLocation(this.selectLayer,'x1');

  this.pixelStart   = this.left  + this.padLeft;
}

Details.prototype.formatMenu = function() {
  this.menuHTML = this.selectMenu.innerHTML || '\
  <table style="width:100%">\
         <tr>\
           <th style="background:lightgrey;cell-padding:5">\
             SELECTION\
             <a style="right:0px;position:absolute" href="javascript:SelectArea.prototype.cancelRubber()">\
               [X]\
             </a>\
           </th>\
         </tr>\
         <tr>\
           <td>\
             <a href="javascript:SelectArea.prototype.clearAndSubmit()">' + Controller.translate('ZOOM_IN') + '</a>\
           </td>\
         </tr>\
         <tr>\
           <td>\
             <a href="javascript:SelectArea.prototype.clearAndRecenter()">' + Controller.translate('RECENTER_ON_REGION') + '</a>\
           </td>\
         </tr>\
         <tr>\
           <td onmouseup="SelectArea.prototype.cancelRubber()">\
             <a href="?plugin=FastaDumper;plugin_action=Go;name=SELECTION" target="_new">\
              ' + Controller.translate('DUMP_AS_FASTA') + '\
             </a>\
           </td>\
         </tr>\
       </table>';
}

