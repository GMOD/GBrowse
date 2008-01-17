/*

 detailsSelect.js -- a DHTML library for drag/rubber-band selection in gbrowse
                      This class handles details-specific configuration.

 Sheldon McKay <mckays@cshl.edu>
 $Id: detailSelect.js,v 1.1.2.1 2008-01-17 22:11:32 sheldon_mckay Exp $

*/

var verviewObject;

// Constructor
var Details = function () {
  this.imageId    = '__scale___image';
  this.imageName  = 'detail___scale__';
  this.marginTop  = '35px';
  this.background = 'blue';
  this.fontColor  = 'white';
  this.menuWidth  = '200px';
  return this;
}

// Inherit from base class SelectArea
Details.prototype = new SelectArea();

// Details-specific config.
Details.prototype.initialize = function() {
  var self = new Details;
  var images = document.getElementsByName(self.imageName);
  var i;
  for (var n=0;n<images.length;n++) {
    if (images[n].id == self.imageId) {
      i = images[n];
    }
  }
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

  if (balloon) {
    var helpFunction = function(event) { 
      if (!event) {
        event = window.event;
      }
      var help = '<b>Scalebar:</b> Click here to recenter or click and drag left or right to select a region';
      balloon.showTooltip(event,help,0,250);
    }
    i.onmouseover = helpFunction;
  }
  else {
    i.setAttribute('title','click and drag to select a region');
  }

  self.scalebar = i;
  self.getSegment();
  self.addSelectMenu('detail');
  self.addSelectBox('detail');
  detailsObject = self;
}

Details.prototype.startSelection = function(event) {
  var self = detailsObject;
  var evt = event || window.event;
  SelectArea.prototype.startRubber(self,event);
}

Details.prototype.getSegment = function() {
  // get the segment info from gbrowse CGI parameters
  this.ref          = document.mainform.ref.value;
  this.segmentStart = parseInt(document.mainform.start.value);
  this.segmentEnd   = parseInt(document.mainform.stop.value);
  this.flip         = document.mainform.flip.checked;
  this.padLeft      = parseInt(document.mainform.image_padding.value);
  this.pixelToDNA   = parseFloat(document.mainform.details_pixel_ratio.value);
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
             <a href="javascript:SelectArea.prototype.clearAndSubmit()">Zoom in</a>\
           </td>\
         </tr>\
         <tr>\
           <td>\
             <a href="javascript:SelectArea.prototype.clearAndRecenter()">Recenter on this region</a>\
           </td>\
         </tr>\
         <tr>\
           <td onmouseup="SelectArea.prototype.cancelRubber()">\
             <a href="?plugin=FastaDumper;plugin_action=Go;name=SELECTION" target="_new">\
              Dump selection as FASTA\
             </a>\
           </td>\
         </tr>\
       </table>';
}

