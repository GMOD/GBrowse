/*

 rubber.js -- a DHTML library for drag/rubber-band selection in gbrowse

 Sheldon McKay <mckays@cshl.edu>
 $Id: rubber.js,v 1.1.2.1 2007-07-24 17:14:27 sheldon_mckay Exp $

*/

// Just two variable to keep track of which object is active
var currentSelectArea;
var selectAreaIsActive;

// Constructor
var SelectArea = function () {
  this.imageName  = 'detailedView';
  this.padLeft    = 25;
  this.padRight   = 25;
  currentSelectArea = this;
}

SelectArea.prototype.getSelectArea = function() {
  var images = document.getElementsByName(this.imageName);
  var i = images[0];
  this.height = this.elementLocation(i,'height');
  this.width  = this.elementLocation(i,'width');
  var src    = i.src
  var parent = i.parentNode;

  // We replace the image with a <span> that has the image as its background
  // This relieves the image drag side-effect and also helps with getting
  // the proper image coordinates
  parent.removeChild(i);
  var newImage = this.createAndAppend('span',parent,this.imageName);

  YAHOO.util.Dom.setStyle(newImage,'width',this.width+'px');
  YAHOO.util.Dom.setStyle(newImage,'height',this.height+'px');
  YAHOO.util.Dom.setStyle(newImage,'background', 'url('+src+') top left no-repeat');
  //YAHOO.util.Dom.setStyle(newImage,'border','5px solid purple'); // temporary tracer
  YAHOO.util.Dom.setStyle(newImage,'display','block');

  this.top     = this.elementLocation(newImage,'y1');
  this.bottom  = this.elementLocation(newImage,'y2');
  this.left    = this.elementLocation(newImage,'x1');
  this.right   = this.elementLocation(newImage,'x2');

  this.getSegment();
  this.addSelectMenu();
  this.addSelectBox();
}

SelectArea.prototype.getSegment = function () {
  // get the segment from the boilerplate.  We can;t rely on the 'name' input element
  var segment;
  var allH2 = document.getElementsByTagName('h2');
  var i=0;
  while (!segment) {
    var text = allH2[i].innerHTML;
    segment = text.match(/from\s+(\S+),\s+positions\s+(\S+)\s+to\s+(\S+)/);
    i++
  }
 
  if (!segment) return false;

  this.ref   = segment[1];
  // remove commas and convert to numbers
  this.segmentStart = segment[2].replace(/\D/g,'') * 1;
  this.segmentEnd   = segment[3].replace(/\D/g,'') * 1; 

  // pixel to base-pair conversion factor
  this.pixelStart   = this.left  + this.padLeft;
  var pixelEnd      = this.right - this.padRight;
  var pixelLength   = pixelEnd - this.pixelStart;
  var segmentLength = this.segmentEnd - this.segmentStart;
  this.pixelToDNA   = segmentLength/pixelLength; 

  // remeber the original lanmark so it can be reset
  this.originalLandmark = document.mainform.name.value;
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
  self.selectPixelStart = self.eventLocation(event,'x');
  YAHOO.util.Dom.setStyle(self.selectBox,'visibility','hidden');
  YAHOO.util.Dom.setStyle(self.selectMenu,'visibility','hidden');
  YAHOO.util.Dom.setStyle(self.selectBox,'left',self.selectPixelStart+'px');
  self.selectBox.innerHTML = ' ';
  selectAreaIsActive = true;
}

SelectArea.prototype.cancelRubber = function() {
  var self = currentSelectArea;

  YAHOO.util.Dom.setStyle(self.selectBox,'visibility','hidden');
  YAHOO.util.Dom.setStyle(self.selectMenu,'visibility','hidden');
  selectAreaIsActive = false;
  document.mainform.name.value = self.originalLandmark;
}

SelectArea.prototype.moveRubber = function(event) {
  if (!selectAreaIsActive) return false;

  var self = currentSelectArea;
  var selectPixelStart = self.selectPixelStart;

  var selectPixelEnd = self.eventLocation(event,'x');
  var selectPixelWidth = Math.abs(selectPixelStart - selectPixelEnd);
  if (selectPixelStart > selectPixelEnd) {
    selectPixelStart = selectPixelEnd;
    selectPixelEnd = selectPixelStart + selectPixelWidth;
  } 

  // Coordinates of selected sequence
  var deltaPixelStart      = selectPixelStart - self.pixelStart;
  var deltaSequenceStart   = deltaPixelStart * self.pixelToDNA;
  self.selectSequenceStart = Math.round(self.segmentStart + deltaSequenceStart);
  var selectSequenceWidth  = Math.round(selectPixelWidth * self.pixelToDNA);
  self.selectSequenceEnd   = self.selectSequenceStart + selectSequenceWidth;

  // reset the value of the 'name' input box
  self.currentSegment = self.ref +':'+self.selectSequenceStart+'..'+self.selectSequenceEnd;
  document.mainform.name.value = self.currentSegment;

  // size and appearance of the "rubber band" select box
  YAHOO.util.Dom.setStyle(self.selectBox,'width','1px');
  YAHOO.util.Dom.setStyle(self.selectBox,'left',selectPixelStart+'px');
  YAHOO.util.Dom.setStyle(self.selectBox,'width',selectPixelWidth+'px');
  YAHOO.util.Dom.setStyle(self.selectBox,'visibility','visible');

  if (selectPixelWidth > 40) {
    self.selectBox.innerHTML = '\
      <br><h2 style="text-align:center">'+selectSequenceWidth+' bp</h3>';
  }
  else {
    self.selectBox.innerHTML = ' ' ;
  }

  self.selectPixelStart = selectPixelStart;
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
  //YAHOO.util.Dom.setStyle(menu,'width','150px');
  YAHOO.util.Dom.setStyle(menu,'font-family','sans-serif');
  YAHOO.util.Dom.setStyle(menu,'font-size','12px');
  YAHOO.util.Dom.setStyle(menu,'background-color','lightyellow');
  self.selectMenu = menu;

  var URL = window.location; 
  URL = new String(URL);
  URL = URL.replace(/\?\S+/, ''); 
  var FASTA  = '?plugin=FastaDumper;plugin_action=Go;name=SELECTION'
  var GFF    = '?plugin=GFFDumper;plugin_action=Go;name=SELECTION'

  self.menuHTML = '\
  <table style="font-size:small">\
   <tr>\
    <th style="background-color:lightgrey;cell-padding:5">SELECTION</th>\
   </tr>\
   <tr onmousedown="SelectArea.prototype.clearAndSubmit()">\
     <td><a href="javascript:void()">Zoom in</a></td>\
   </tr>\
   <tr>\
     <td><a href="'+FASTA+'" target="_new">Dump as FASTA</a></td>\
   </tr>\
   <tr>\
     <td><a href="'+GFF+'" target="_new">Dump as GFF</a></td>\
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

  if (self.selectBox = document.getElementById('selectBox')) {
    return false;
  }
  
  var box = self.createAndAppend('div',document.body,'selectBox');

  YAHOO.util.Dom.setStyle(box,'position','absolute');
  YAHOO.util.Dom.setStyle(box,'display', 'inline');
  YAHOO.util.Dom.setStyle(box,'top',self.top+'px');
  YAHOO.util.Dom.setStyle(box,'height',self.height+'px');
  YAHOO.util.Dom.setStyle(box,'left','0px');
  YAHOO.util.Dom.setStyle(box,'border-left','2px solid blue');
  YAHOO.util.Dom.setStyle(box,'border-right','2px solid blue');
  YAHOO.util.Dom.setStyle(box,'visibility','hidden');
  YAHOO.util.Dom.setStyle(box,'background-color','#BABABA');
  YAHOO.util.Dom.setStyle(box,'z-index',100);
  self.setOpacity(box,0.5);


  // Also create a 100% width box that will have the event handlers
  var outerBox = self.createAndAppend('div',document.body,'outerBox');
  YAHOO.util.Dom.setStyle(outerBox,'position','absolute');
  YAHOO.util.Dom.setStyle(outerBox,'top',self.top+'px');
  YAHOO.util.Dom.setStyle(outerBox,'height',self.height+'px');
  YAHOO.util.Dom.setStyle(outerBox,'left','0px');
  YAHOO.util.Dom.setStyle(outerBox,'width','100%');
  //YAHOO.util.Dom.setStyle(outerBox,'border','2px solid red');

  outerBox.onmousedown = self.startRubber;
  outerBox.onmousemove = self.moveRubber;
  document.onmouseup   = self.stopRubber;  

  self.selectBox = box;
  self.outerBox  = outerBox;
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

  selectAreaIsActive = false;
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
  opc = parseFloat(opc);
  YAHOO.util.Dom.setStyle(el,'opacity',opc);
  YAHOO.util.Dom.setStyle(el,'filter','alpha(opacity= '+(100*opc)+')');
  YAHOO.util.Dom.setStyle(el,'MozOpacity',opc);
  YAHOO.util.Dom.setStyle(el,'KhtmlOpacity',opc);
}
