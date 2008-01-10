/*

 rubber.js -- a DHTML library for drag/rubber-band selection in gbrowse

 Sheldon McKay <mckays@cshl.edu>
 $Id: rubber.js,v 1.1.2.8 2008-01-10 16:29:15 sheldon_mckay Exp $

*/

// Just two variable to keep track of which object is active
var currentSelectArea;
var selectAreaIsActive;

// Constructor
var SelectArea = function () {

  this.imageName  = 'detail___scale__'; 
  this.padLeft    = 25;
  this.padRight   = 25;

  currentSelectArea = this;
  return currentSelectArea;
}

SelectArea.prototype.initialize = function() {
  var self = new SelectArea;

  var images = document.getElementsByName(self.imageName);
  var i = images[0];
  if (!i) return false;

  var p = document.getElementById('panels');
  var details = document.getElementById('details_panel_hide');
  this.height = this.elementLocation(i,'height');
  this.panelHeight = this.elementLocation(p,'height');
  this.width  = this.elementLocation(i,'width');
  var src    = i.src
  var parent = i.parentNode;
  this.panels = p;

  // disable text selection 
  self.disableSelection(p);

  // We replace the scale-bar image with a <span> that has the image as its background
  // This relieves the image drag side-effect and also helps with getting
  // the proper image coordinates
  parent.removeChild(i);
  var newImage = self.createAndAppend('span',parent,self.imageName);

  YAHOO.util.Dom.setStyle(newImage,'width',self.width+'px');
  YAHOO.util.Dom.setStyle(newImage,'height',self.height+'px');
  YAHOO.util.Dom.setStyle(newImage,'background', 'url('+src+') top left no-repeat');
  //YAHOO.util.Dom.setStyle(newImage,'border','5px solid purple'); // temporary tracer
  YAHOO.util.Dom.setStyle(newImage,'display','block');

  self.top     = self.elementLocation(newImage,'y1');
  self.bottom  = self.elementLocation(p,'y2');
  self.left    = self.elementLocation(newImage,'x1');
  self.right   = self.elementLocation(newImage,'x2');

  if (balloon) {
    var helpFunction = function(event) { 
      if (!event) {
        event = window.event;
      }
      var help = '<b>Scalebar:</b> Click here to recenter or click and drag left or right to select a region';
      balloon.showTooltip(event,help,0,250);
    }
    newImage.onmouseover = helpFunction;
  }
  else {
    newImage.setAttribute('title','click and drag to select a region');
  }

  self.scalebar = newImage;  

  self.getSegment();
  self.addSelectMenu();
  self.addSelectBox();
}

SelectArea.prototype.recenter = function(event) {
  var self = currentSelectArea;
  var deltaPixelStart      = self.selectPixelStart - self.pixelStart;
  var deltaSequenceStart   = deltaPixelStart * self.pixelToDNA;

  var coord  = self.flip ? Math.round(self.segmentEnd - deltaSequenceStart)
                         : Math.round(self.segmentStart + deltaSequenceStart);
  var half   = Math.abs((self.segmentEnd - self.segmentStart)/2);
  var start  = coord - half;
  var end    = coord + half;
  document.mainform.name.value = self.ref + ':' + start + '..' + end;
  document.mainform.submit();
}

SelectArea.prototype.getSegment = function() {
  // get the segment from gbrowse CGI parameters
  this.ref          = document.mainform.ref.value;
  this.segmentStart = document.mainform.start.value.replace(/\D+/g, '') * 1;
  this.segmentEnd   = document.mainform.stop.value.replace(/\D+/g, '') * 1;
  this.flip         = document.mainform.flip.checked;

  // pixel to base-pair conversion factor
  this.pixelStart   = this.left  + this.padLeft;
  var pixelEnd      = this.right - this.padRight;
  var pixelLength   = pixelEnd - this.pixelStart;
  var segmentLength = this.segmentEnd - this.segmentStart;
  this.pixelToDNA   = segmentLength/pixelLength; 

  // remember the original landmark so it can be reset
  this.originalLandmark = this.ref + ':' + this.segmentStart + '..' + this.segmentEnd;
}


// Cross-browser element coordinates
SelectArea.prototype.elementLocation = function(el,request) {
  var region = YAHOO.util.Dom.getRegion(el);
  switch(request) {
    case ('y1') : return region.top;
    case ('y2') : return region.bottom;
    case ('x1') : return region.left;
    case ('x2') : return region.right;
    case ('width')  : return (region.right - region.left);
    case ('height') : return (region.bottom - region.top);
 }
}


// Cross-browser event coordinates
SelectArea.prototype.eventLocation = function(event,request) {
  var e = event || window.event;
  if (request == 'x') {
    return e.pageX || e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
  }
  else if (request == 'y') {
    return e.pageY || e.clientY + document.body.scrollTop  + document.documentElement.scrollTop;
  }
  else {  
    return false;
  }
}

// Fired when there is a mousedown between the top and bottom
// of the selectable image -- horizontal position does not matter
SelectArea.prototype.startRubber = function(event) {
  var self = currentSelectArea;

  // disable help balloon after first selection is made.
  if (balloon) {
    balloon.hideTooltip();
    var nullfunc = function(){return false};
    self.scalebar.onmouseover = nullfunc;
  }

  self.selectPixelStart = self.eventLocation(event,'x');
  YAHOO.util.Dom.setStyle(self.selectBox,'visibility','hidden');
  YAHOO.util.Dom.setStyle(self.selectBox,'left',self.selectPixelStart+'px');
  YAHOO.util.Dom.setStyle(self.selectBox,'width','2px');
  YAHOO.util.Dom.setStyle(self.selectBox,'padding-top','40px');
  YAHOO.util.Dom.setStyle(self.selectBox,'text-align', 'center');	
  //YAHOO.util.Dom.setStyle(self.selectBox,'visibility','visible');
  YAHOO.util.Dom.setStyle(self.selectMenu,'visibility','hidden');

  // height of select box to match height of detail panel
  var h = self.elementLocation(self.panels,'height');
  YAHOO.util.Dom.setStyle(self.selectBox,'height',h+'px');
  
  // vertical offset may also need adjusting
  var t = self.elementLocation(self.panels,'y1');
  YAHOO.util.Dom.setStyle(self.selectBox,'top',t+'px');

  self.selectBox.innerHTML = ' ';
  selectAreaIsActive = true;
}

SelectArea.prototype.cancelRubber = function() {
  var self = currentSelectArea || new SelectArea;

  if (!self.selectBox) return false;
  
  YAHOO.util.Dom.setStyle(self.selectBox,'visibility','hidden');
  YAHOO.util.Dom.setStyle(self.selectMenu,'visibility','hidden');
  selectAreaIsActive = false;

  if (self.originalLandmark) {
    document.mainform.name.value = self.originalLandmark;
  }
  self.moved = false;
}

SelectArea.prototype.round = function(nearest,num) {
  if (num > nearest) {
    num = Math.round(num/nearest)*nearest;
  }
  return num;
} 

SelectArea.prototype.moveRubber = function(event) {
  if (!selectAreaIsActive) return false;

  var self = currentSelectArea;
  var selectPixelStart = self.selectPixelStart;
  var selectPixelEnd   = self.eventLocation(event,'x');
  var selectPixelWidth = Math.abs(selectPixelStart - selectPixelEnd);

  var rev, left;
  if (selectPixelStart > selectPixelEnd) {
    rev  = true;
    left = selectPixelEnd;
    self.selectPixelStart = left;
  }
  else {
    left = selectPixelStart;
  }

  // Coordinates of selected sequence
  var deltaPixelStart      = left - self.pixelStart;
  var deltaSequenceStart   = deltaPixelStart * self.pixelToDNA;
  self.selectSequenceStart = self.flip ? Math.round(self.segmentEnd - deltaSequenceStart) 
                                       : Math.round(self.segmentStart + deltaSequenceStart);
  var selectSequenceWidth  = Math.round(selectPixelWidth * self.pixelToDNA);
  self.selectSequenceEnd   = self.flip ? self.selectSequenceStart - selectSequenceWidth 
                                       : self.selectSequenceStart + selectSequenceWidth;

  var segmentLength = Math.abs(self.segmentEnd - self.segmentStart);
  
  // Round the sequence coordinates to the nearest appropriate 10x
  if (segmentLength > 1000000) {
    self.selectSequenceStart = self.round(10000,self.selectSequenceStart);
    self.selectSequenceEnd = self.round(10000,self.selectSequenceEnd);
  }
  else if (segmentLength > 50000) {
    self.selectSequenceStart = self.round(1000,self.selectSequenceStart);
    self.selectSequenceEnd = self.round(1000,self.selectSequenceEnd);
  }
  else if (segmentLength > 5000) {
    self.selectSequenceStart = self.round(100,self.selectSequenceStart);
    self.selectSequenceEnd = self.round(100,self.selectSequenceEnd);
  }
  else if (segmentLength > 500) {
    self.selectSequenceStart = self.round(10,self.selectSequenceStart);
    self.selectSequenceEnd = self.round(10,self.selectSequenceEnd);
  }
  
  selectSequenceWidth = Math.abs(self.selectSequenceEnd - self.selectSequenceStart);


  // reset the value of the 'name' input box
  self.currentSegment = self.ref +':'+self.selectSequenceStart+'..'+self.selectSequenceEnd;
  document.mainform.name.value = self.currentSegment;

  // size and appearance of the "rubber band" select box
  YAHOO.util.Dom.setStyle(self.selectBox,'width','1px');
  YAHOO.util.Dom.setStyle(self.selectBox,'left',left+'px');
  YAHOO.util.Dom.setStyle(self.selectBox,'width',selectPixelWidth+'px');
  YAHOO.util.Dom.setStyle(self.selectBox,'visibility','visible');

  if (selectPixelWidth > 75) {
    self.selectBox.innerHTML = '\
      <h2>'+selectSequenceWidth+' bp</h2>';
  }
  else {
    self.selectBox.innerHTML = ' ' ;
  }

  self.selectPixelStart = selectPixelStart;
  self.moved = true;
}

// taken from http://ajaxcookbook.org/disable-text-selection/
// prevents ugly drag select side-effects
SelectArea.prototype.disableSelection = function(el) {
    el.onselectstart = function() {
        return false;
    };
    el.unselectable = "on";
    el.style.MozUserSelect = "none";
    el.style.cursor = "default";
}


// Builds the popup menu that appears when selection is complete
SelectArea.prototype.addSelectMenu = function() {
  var self = currentSelectArea;

  if (self.selectMenu = document.getElementById('selectMenu')) {
    return false;
  }

  var menu  = self.createAndAppend('div',document.body,'selectMenu');
  YAHOO.util.Dom.setStyle(menu,'position','absolute');
  YAHOO.util.Dom.setStyle(menu,'display','block');
  YAHOO.util.Dom.setStyle(menu,'z-index','101');
  YAHOO.util.Dom.setStyle(menu,'width','200px');
  YAHOO.util.Dom.setStyle(menu,'font-family','sans-serif');
  YAHOO.util.Dom.setStyle(menu,'font-size','12px');
  YAHOO.util.Dom.setStyle(menu,'background-color','lightyellow');
  YAHOO.util.Dom.setStyle(menu,'border','1px solid #003366');
  YAHOO.util.Dom.setStyle(menu,'visibility','visible');
  self.selectMenu = menu;

  var URL = window.location; 
  URL = new String(URL);
  URL = URL.replace(/\?\S+/, ''); 
  var FASTA  = '?plugin=FastaDumper;plugin_action=Go;name=SELECTION'

  self.menuHTML = '\
  <table style="width:100%">\
   <tr>\
    <th style="background:lightgrey;cell-padding:5">SELECTION</td>\
   </tr>\
   <tr onmousedown="SelectArea.prototype.clearAndSubmit()">\
     <td><a href="javascript:void()">Zoom in</a></td>\
   </tr>\
   <tr>\
     <td onmouseup="SelectArea.prototype.cancelRubber()">\
       <a href="'+FASTA+'" target="_new">Dump sequence as FASTA</a>\
     </td>\
   </tr>\
   <tr onmousedown="SelectArea.prototype.clearAndRecenter()">\
     <td><a href="javascript:void()">Recenter</a></td>\
   </tr>\
   <tr onmousedown="SelectArea.prototype.cancelRubber()">\
     <td><a href="javascript:void()">Clear selection</a></td>\
   </tr>\
  </table>';

}


// Initial creation of the select box
SelectArea.prototype.addSelectBox = function() {
  var self = currentSelectArea;

  if (self.selectBox) return false;
 
  var box = self.createAndAppend('div',this.panels,'selectBox');

  YAHOO.util.Dom.setStyle(box,'position','absolute');
  YAHOO.util.Dom.setStyle(box,'display', 'inline');
  YAHOO.util.Dom.setStyle(box,'visibility', 'hidden');
  YAHOO.util.Dom.setStyle(box,'top',self.top+'px');
  YAHOO.util.Dom.setStyle(box,'left','0px');
  YAHOO.util.Dom.setStyle(box,'border-left','2px solid blue');
  YAHOO.util.Dom.setStyle(box,'border-right','2px solid blue');
  YAHOO.util.Dom.setStyle(box,'z-index',100);
  self.setOpacity(box,0.5);

  // click on scalebar initializes selection
  this.scalebar.onmousedown = self.startRubber;

  // drag and mouseup on details panel fires menu
  this.panels.onmousemove   = self.moveRubber;
  this.panels.onmouseup     = self.stopRubber;  

  // allows drag-back
  box.onmousemove           = self.moveRubber;

  // 'esc' key aborts
  var abort = function(event){
    var evt = event || window.event;
    if (evt.keyCode == 27) self.cancelRubber();
    return true;
  }
  document.onkeydown        = abort;

  self.selectBox = box;
}


/////////////////////////////////////////////////////////////////////
// Create/append  elements
/////////////////////////////////////////////////////////////////////

SelectArea.prototype.createAndAppend = function(elTag,parent,id) {
  var node = this.justCreate(elTag);
  this.justAppend(node,parent);
  if (id) node.setAttribute('id',id);
  return node;
}

SelectArea.prototype.justCreate = function(elTag) {
  var tag = elTag || 'div';
  var node = document.createElement(tag);
  return node;
}

SelectArea.prototype.justAppend = function(child,parent) {
  var parentNode = parent || document.body;
  parentNode.appendChild(child);
}
  

SelectArea.prototype.stopRubber = function(event) {
  if (!selectAreaIsActive) return false;
  var self = currentSelectArea;
  if (!self.moved) {
    self.cancelRubber();
    self.recenter();
    return false;
  }

  selectAreaIsActive = false;
  self.moved = false;
  self.showMenu(event);
}

SelectArea.prototype.showMenu = function(event) {
  var self = currentSelectArea;
  
  self.selectMenu.innerHTML = self.menuHTML.replace(/SELECTION/g,self.currentSegment);

  // Center the popup menu on the cursor
  var hOffset = Math.round(self.elementLocation(self.selectMenu,'width')/4);
  var vOffset = Math.round(self.elementLocation(self.selectMenu,'height')/3);

  var eventX  = self.eventLocation(event,'x');
  var eventY  = self.eventLocation(event,'y');
  YAHOO.util.Dom.setStyle(self.selectMenu,'top', (eventY - vOffset)+'px'); 
  YAHOO.util.Dom.setStyle(self.selectMenu,'left',(eventX - hOffset)+'px');

  // Abort if there is no selection
  if (YAHOO.util.Dom.getStyle(self.selectBox,'visibility') == 'hidden') {
    self.cancelRubber;
    return false;
  }

  // But keep the popup menu in a reasonable position
  var menuTop   = self.elementLocation(self.selectMenu,'y1');
  var menuLeft  = self.elementLocation(self.selectMenu,'x1');
  var menuWidth = self.elementLocation(self.selectMenu,'width');
  var menuRight = self.elementLocation(self.selectMenu,'x2');
  var boxLeft   = self.elementLocation(self.selectBox,'x1');
  var boxRight  = self.elementLocation(self.selectBox,'x2');

  if (menuTop > self.bottom - 50) {
    YAHOO.util.Dom.setStyle(self.selectMenu,'top', (self.bottom  - 50)+'px');
  }
  if (menuLeft < hOffset) {
    YAHOO.util.Dom.setStyle(self.selectMenu,'left', self.left+'px');
  }
  if (menuRight > self.right) {
    YAHOO.util.Dom.setStyle(self.selectMenu,'left', (eventX - menuWidth)+'px');
  }
  if (menuTop < (self.top - 50)) {
    YAHOO.util.Dom.setStyle(self.selectMenu,'top', self.top+'px');
  }
  if (menuLeft > boxRight) {
    YAHOO.util.Dom.setStyle(self.selectMenu,'left', (boxRight - 50)+'px');
  }
  if (menuRight < boxLeft) {
    YAHOO.util.Dom.setStyle(self.selectMenu,'left', boxLeft+'px');
  }   

  YAHOO.util.Dom.setStyle(self.selectMenu,'visibility','visible');

}

SelectArea.prototype.hideMenu = function() {
  var self = currentSelectArea;

  YAHOO.util.Dom.setStyle(self.selectBox,'width',1);  
  YAHOO.util.Dom.setStyle(self.selectBox,'visibility','hidden');
  YAHOO.util.Dom.setStyle(self.selectMenu,'visibility','hidden');
}

SelectArea.prototype.clearAndSubmit = function(plugin,action) {
  this.hideMenu();
  if (plugin) {
    action = action || 'Go';
    var url = window.location;
    url += '?plugin='+plugin+';plugin_action='+action; 
    document.location = url;
  }
  else {
    document.mainform.submit();
  }
}

SelectArea.prototype.clearAndRecenter = function() {
  var self = currentSelectArea;
  
  var half    = Math.round((self.segmentEnd - self.segmentStart)/2);
  var middle  = Math.round((self.selectSequenceStart + self.selectSequenceEnd)/2);
  var newName = self.ref+':'+(middle-half)+'..'+(middle+half);
  document.mainform.name.value = newName;
  self.clearAndSubmit();
}

// Make best effort to set the opacity of the selectbox
// background color
SelectArea.prototype.setOpacity = function(el,opc) {
  if (!(el && opc)) return false;

  // Don't do anything for Konqueror
  if (navigator.userAgent.indexOf( 'Konqueror' ) != -1) return false;

  opc = parseFloat(opc);
  YAHOO.util.Dom.setStyle(el,'background-color','#BABABA');
  YAHOO.util.Dom.setStyle(el,'opacity',opc);
  YAHOO.util.Dom.setStyle(el,'filter','alpha(opacity= '+(100*opc)+')');
  YAHOO.util.Dom.setStyle(el,'MozOpacity',opc);
  YAHOO.util.Dom.setStyle(el,'KhtmlOpacity',opc);
}
