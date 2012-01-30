/*

 detailsSelect.js -- a DHTML library for drag/rubber-band selection in gbrowse
                      This class handles details-specific configuration.

 Sheldon McKay <sheldon.mckay@gmail.com>
 $Id$

*/

var detailsObject;
var detailBalloon;

// Constructor
var Details = function () {
  this.imageId    = 'Detail Scale_image';
  this.marginTop  = '35px';
  this.background = 'blue';
  this.fontColor  = 'black';
  this.border     = '1px solid black';
  this.menuWidth  = '200px';
  this.type       = 'details';
  this.opacity    = 0.6;
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

  // Uh oh! We must be in GBrowse_syn!
  if (Controller.gbrowse_syn) {
      this.getSegment(i);
      return true;
  }

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


Details.prototype.getSegment = function(i) {
    this.ref          = document.mainform.ref.value;
    this.segmentStart = parseInt(document.mainform.detail_start.value);
    this.segmentEnd   = parseInt(document.mainform.detail_stop.value);
    this.padLeft      = parseInt(document.mainform.image_padding.value);
    this.pixelToDNA   = parseFloat(document.mainform.detail_pixel_ratio.value);
    this.detailStart  = this.segmentStart;
    this.detailEnd    = this.segmentEnd;     

    this.flip         = 0;
    
    var actualWidth   = this.elementLocation(i,'width');
    var expectedWidth = parseInt(document.mainform.overview_width.value);
    if (actualWidth > expectedWidth) {
	this.padLeft     += actualWidth - expectedWidth;
    }
    this.pixelStart   = this.left  + this.padLeft;
}


Details.prototype.formatMenu = function() {
  this.menuHTML = this.selectMenu.innerHTML; 
  if (this.menuHTML) {
      return false;
  }

  this.menuHTML = '\
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
         </tr>';

  if (!Controller.gbrowse_syn) {       
    this.menuHTML += '\
         <tr>\
           <td onmouseup="SelectArea.prototype.cancelRubber()">\
             <a href="?plugin=FastaDumper;plugin_action=Go;name=SELECTION" target="_new">\
              ' + Controller.translate('DUMP_AS_FASTA') + '\
             </a>\
           </td>\
         </tr>\
       </table>';
  }
  else {
    this.menuHTML += '</table>';
  }
}

