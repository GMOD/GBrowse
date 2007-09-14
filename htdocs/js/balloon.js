/*
 balloon.js -- a DHTML library for balloon tooltips

 $Id: balloon.js,v 1.1.2.11 2007-09-14 21:15:54 sheldon_mckay Exp $

 See http://www.gmod.org/wiki/index.php/Popup_Balloons
 for documentation.

 Copyright (c) 2007 Sheldon McKay, Cold Spring Harbor Laboratory

 This balloon tooltip package and associated files not otherwise copyrighted are 
 distributed under the MIT-style license:
 
 http://opensource.org/licenses/mit-license.php

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.

 If publications result from research using this SOFTWARE, we ask that
 CSHL and the author be acknowledged as scientifically appropriate.

*/

// These global variables are necessary to avoid losing scope when
//setting the balloon timeout and for inter-object communication
var currentBalloonClass;
var balloonIsVisible
var balloonIsSticky;
var balloonInvisibleSelects;


// If using this library from dynamically generated HTML in IE, such as
// CGI scripts, set this variable to false.  It will prevent
// balloons from firing until the page is fully loaded in IE.  
var balloonOK = false;
window.onload = function(){ balloonOK = true; }

///////////////////////////////////////////////////
// Constructor for Balloon class                 //
// Balloon configuration                         //
// Reset these values for custom balloon designs //
///////////////////////////////////////////////////
var Balloon = function() {
  // Location of optional ajax handler that returns tooltip contents
  //this.helpUrl = '/cgi-bin/help.pl';

  // maxium allowed balloon width
  this.minWidth = 150;

  // minimum allowed balloon width
  this.maxWidth = 600;

  // Default tooltip text size
  this.balloonTextSize = '90%';

  // Delay (milliseconds) before balloon is displayed
  this.delayTime = 500;

  // Vertical Distance from cursor location
  this.vOffset  = 10;

  // text-padding within the balloon
  this.padding  = 10;

  // width of shadow (space aroung whole balloon)
  // This can be zero if there is no shadow and the
  // edges of the balloon are also the edges of the image
  this.shadow   = 20;

  // images of balloon body.  If the browser is IE < 7, png alpha
  // channels will not work.  An optional alternative image can be 
  // provided.  It should have the same dimensions as the default png image
  this.balloonImage  = '/images/balloons/balloon.png';    // with alpha channels
  this.ieImage       = '/images/balloons/balloon_ie.png'; // indexed color, transparent background

  // whether the balloon should have a stem
  this.stem          = true;

  // The height (px) of the stem and the extent to which the 
  // stem image should overlaps the balloon image.
  this.stemHeight  = 32;  
  this.stemOverlap = 3;
  
  // A stem for each of the four orientations
  this.upLeftStem    = '/images/balloons/up_left.png';
  this.downLeftStem  = '/images/balloons/down_left.png';
  this.upRightStem   = '/images/balloons/up_right.png';
  this.downRightStem = '/images/balloons/down_right.png';

  // A close button for sticky balloons
  this.closeButton   = '/images/balloons/close.png';
}


//////////////////////////////////////////////////////////////////////////
// This is the function that is called on mouseover.  It has a built-in //
// delay time to avoid balloons popping up on rapid mouseover events     //
//////////////////////////////////////////////////////////////////////////
Balloon.prototype.showTooltip = function(evt,caption,sticky,width) {
  // Awful IE bug, page load aborts if the balloon is fired
  // before the page is fully loaded.
  if (this.isIE() && !balloonOK) return false;

  // Check for mouseover (vs. mousedown or click)
  var mouseOver = evt.type.match('mouseover','i');  

  // Don't fire on mouseover if a non-sticky balloon is visible
  if (balloonIsVisible && !balloonIsSticky && mouseOver) return false;

  // Don't start a non-sticky balloon if a sticky one is visible
  if (balloonIsVisible && balloonIsSticky && !sticky) return false;
  
  // Ignore repeated firing of mouseover->mouseout events on 
  // the same element (Safari)
  var el = this.getEventTarget(evt);
  if (sticky && mouseOver && this.isSameElement(el,this.currentElement)) return false;
  this.firingElement = el;

  // A new sticky balloon can erase an old one
  if (sticky) this.hideTooltip(1);

  // attach a mouseout event handler to the target element
  var closeBalloon = function() { 
    var override = balloonIsSticky && !balloonIsVisible;
    Balloon.prototype.hideTooltip(override)
  }
  el.onmouseout = closeBalloon;;

  balloonIsSticky = sticky;

  // force balloon width and/or height if requested
  this.width  = width;

  // Set the active mousover coordinates
  this.setActiveCoordinates(evt);

  this.hideTooltip();

  // if this is IE < 7 use an alternative image id provided
  if (this.isOldIE() && this.ieImage) {
    this.balloonImage = this.ieImage;
    this.ieImage = null;
  }

  // look for a url in the balloon contents
  if (caption.match(/^url:/)) {
    var urlArray = caption.split(':');
    caption = '';
    this.activeUrl = urlArray[1];
  }
  // or if the contents are to be retrieved from an element
  else if (caption.match(/^load:/)) {
    var load = caption.split(':');
    if (!document.getElementById(load[1])) alert ('problem locating element '+load[1]);
    caption = document.getElementById(load[1]).innerHTML;
    this.loadedFromElement = true;
  }
  // or if the text is a bare hyperlink
  else if (caption.match(/^(https?:|\/|ftp:)\S+$/i)) {
    this.activeUrl = caption;
    caption = '';
  }

  // request the contents synchronously (ie wait for result)
  this.currentHelpText = this.getContents(caption);
  this.loadedFromElement = false;

  // Put the balloon contents and images into a visible (but offscreen)
  // element so they will be preloaded and have a layout to 
  // calculate the balloon dimensions
  if (!this.container) {
    this.container = document.createElement('div');
    document.body.appendChild(this.container);
    this.setStyle(this.container,'position','absolute');
    this.setStyle(this.container,'top',-8888);
    this.setStyle(this.container,'display','inline');
  }
  else {
    this.setStyle(this.container,'display','inline');
  }

  this.container.innerHTML = this.currentHelpText;

  // Also preload the balloon images
  if (!this.images) {
    this.images = document.createElement('div');
    document.body.appendChild(this.images);
    this.setStyle(this.images,'position','absolute');
    this.setStyle(this.images,'top',-8888);
    this.setStyle(this.images,'display','inline');
    if (this.upLeftStem)    this.images.innerHTML  = '<img src='+this.upLeftStem+'>';
    if (this.upRightStem)   this.images.innerHTML += '<img src='+this.upRightStem+'>';
    if (this.downLeftStem)  this.images.innerHTML += '<img src='+this.downLeftStem+'>';
    if (this.downRightStem) this.images.innerHTML += '<img src='+this.downRightStem+'>';
    this.images.innerHTML += '<img src='+this.balloonImage+'>';
    this.images.innerHTML += '<img src='+this.closeButton+'>';
  }
  else {
    this.setStyle(this.images,'display','none');
  }

  currentBalloonClass = this;

  // Balloon will be created after delayTime unless a mouseout happens first
  this.timeoutTooltip = window.setTimeout(this.doShowTooltip,this.delayTime);
}

/////////////////////////////////////////////////////////////////////
// Tooltip rendering function
/////////////////////////////////////////////////////////////////////
Balloon.prototype.doShowTooltip = function() {
  var bSelf = currentBalloonClass;

  // Stop firing if a balloon is already being displayed
  if (balloonIsVisible) return false;  

  // record which element owns the balloon
  bSelf.currentElement = bSelf.firingElement;

  // make sure user-configured numbers are not strings
  bSelf.parseIntAll();

  // Hide the off-screen contents container
  bSelf.setStyle(this.container,'display','none');

  // create the balloon object
  var balloon = bSelf.makeBalloon();

  // window dimensions
  var pageWidth  = YAHOO.util.Dom.getViewportWidth();
  var pageCen    = Math.round(pageWidth/2);
  var pageHeight = YAHOO.util.Dom.getViewportHeight();
  var pageLeft   = YAHOO.util.Dom.getDocumentScrollLeft();
  var pageTop    = YAHOO.util.Dom.getDocumentScrollTop();
  var pageMid    = pageTop + Math.round(pageHeight/2);

  // balloon orientation
  var vOrient = bSelf.activeTop > pageMid ? 'up' : 'down';
  var hOrient = bSelf.activeRight > pageCen ? 'left' : 'right';
  
  // get the preloaded balloon contents
  var helpText = bSelf.container.innerHTML;

  // sticky balloons need a close control
  if (balloonIsSticky) {
    var close = '<a onclick="Balloon.prototype.hideTooltip(1)" title="Close">';
    close    += '<img src="'+bSelf.closeButton+'" style="float:right;cursor:pointer"></a><br>';
    helpText = close + helpText; 
  }

  // add the contents to balloon
  document.getElementById('contents').innerHTML = helpText;

  // how and where to draw the balloon
  bSelf.setBalloonStyle(vOrient,hOrient,pageWidth,pageLeft);

  balloonIsVisible = true;
  
  // in IE < 7, hide <select> elements
  bSelf.showHideSelect();
}

// use a fresh object every time to make sure style 
// is not polluted
Balloon.prototype.makeBalloon = function() {
  var bSelf = currentBalloonClass;

  var balloon = document.getElementById('balloon');
  if (balloon) document.body.removeChild(balloon);

  balloon = document.createElement('div');
  balloon.setAttribute('id','balloon');
  document.body.appendChild(balloon);

  var parts = new Array('contents','topRight','bottomRight','bottomLeft');
  for (var i=0;i<parts.length;i++) {
    var child = document.createElement('div');
    child.setAttribute('id',parts[i]);
    balloon.appendChild(child);
  }

  bSelf.activeBalloon = balloon;
  return balloon;
}


Balloon.prototype.setBalloonStyle = function(vOrient,hOrient,pageWidth,pageLeft) {
  var bSelf = currentBalloonClass;
  var balloon = bSelf.activeBalloon;

  if (typeof(bSelf.shadow) != 'number') bSelf.shadow = 0;
  if (!bSelf.stem) bSelf.stemHeight = 0;

  var fullPadding   = bSelf.padding + bSelf.shadow;
  var insidePadding = bSelf.padding;

  bSelf.setStyle(balloon,'background','url('+bSelf.balloonImage+') top left no-repeat');
  bSelf.setStyle(balloon,'position','absolute');
  bSelf.setStyle(balloon,'padding-top',fullPadding);
  bSelf.setStyle(balloon,'padding-left',fullPadding);
  bSelf.setStyle(balloon,'top',-9999);
  // hopefully, on top of everything
  bSelf.setStyle(balloon,'z-index',999999);


  bSelf.setStyle('bottomRight','background','url('+bSelf.balloonImage+') bottom right no-repeat');
  bSelf.setStyle('bottomRight','position','absolute');
  bSelf.setStyle('bottomRight','right',0-fullPadding);
  bSelf.setStyle('bottomRight','bottom',0-fullPadding);
  bSelf.setStyle('bottomRight','height',fullPadding);
  bSelf.setStyle('bottomRight','width',fullPadding);

  bSelf.setStyle('topRight','background','url('+bSelf.balloonImage+') top right no-repeat');
  bSelf.setStyle('topRight','position','absolute');
  bSelf.setStyle('topRight','right',0-fullPadding);
  bSelf.setStyle('topRight','top',0);
  bSelf.setStyle('topRight','width',fullPadding);

  bSelf.setStyle('bottomLeft','background','url('+bSelf.balloonImage+') bottom left no-repeat');
  bSelf.setStyle('bottomLeft','position','absolute');
  bSelf.setStyle('bottomLeft','left',0);
  bSelf.setStyle('bottomLeft','bottom',0-fullPadding);
  bSelf.setStyle('bottomLeft','height',fullPadding);
  bSelf.setStyle('bottomLeft','z-index',-1); //IE

  if (this.stem) {
    var stem = document.createElement('img');
    bSelf.setStyle(stem,'position','absolute');
    balloon.appendChild(stem);    

    if (vOrient == 'up' && hOrient == 'left') {  
      stem.src = bSelf.upLeftStem;
      var height = bSelf.stemHeight + insidePadding - bSelf.stemOverlap;
      bSelf.setStyle(stem,'bottom',0-height);
      bSelf.setStyle(stem,'right',0);             
    }
    else if (vOrient == 'down' && hOrient == 'left') {
      stem.src = bSelf.downLeftStem;
      var height = bSelf.stemHeight - (bSelf.shadow + bSelf.stemOverlap);
      bSelf.setStyle(stem,'top',0-height);
      bSelf.setStyle(stem,'right',0);
    }
    else if (vOrient == 'up' && hOrient == 'right') {
      stem.src = bSelf.upRightStem;
      var height = bSelf.stemHeight + insidePadding - bSelf.stemOverlap;
      bSelf.setStyle(stem,'bottom',0-height);
      bSelf.setStyle(stem,'left',bSelf.shadow);
    }
    else if (vOrient == 'down' && hOrient == 'right') {
      stem.src = bSelf.downRightStem;
      var height = bSelf.stemHeight - (bSelf.shadow + bSelf.stemOverlap);
      bSelf.setStyle(stem,'top',0-height);
      bSelf.setStyle(stem,'left',bSelf.shadow);
    }

  }

  // flip left or right, as required
  if (hOrient == 'left') {
    var activeRight = pageWidth - bSelf.activeLeft;
    bSelf.setStyle(balloon,'right',activeRight);
  }
  else {
    bSelf.setStyle(balloon,'left',bSelf.activeRight);
  }

  if (!bSelf.width) {
    var width = bSelf.getLoc(balloon,'width');
    if (width > bSelf.maxWidth) width = bSelf.maxWidth;
    if (width < bSelf.minWidth) width = bSelf.minWidth;
    bSelf.setStyle(balloon,'width',width);
  }
  else {
    bSelf.setStyle(balloon,'width',bSelf.width);
  }

  // Make sure the balloon is not offscreen
  var balloonPad   = bSelf.padding + bSelf.shadow;
  var balloonLeft  = bSelf.getLoc(balloon,'x1');
  var balloonRight = bSelf.getLoc(balloon,'x2');
  if (hOrient == 'left')  balloonLeft  += balloonPad;
  if (hOrient == 'right') balloonRight += balloonPad;
  var pageRight    = pageLeft + pageWidth;

  if (hOrient == 'right' && balloonRight > (pageRight-30)) {
    bSelf.setStyle(balloon,'width',(pageRight - balloonLeft) - 50);
  }
  else if (hOrient == 'left' && balloonLeft < (pageLeft+30)) {
    bSelf.setStyle(balloon,'width',(balloonRight - pageLeft) - 50);
  }

  // Set the width/height for the right and bottom outlines
  var lineWidth  = bSelf.getLoc(balloon,'width');
  var lineHeight = bSelf.getLoc(balloon,'height');

  bSelf.setStyle('topRight','height',lineHeight);
  bSelf.setStyle('bottomLeft','width',lineWidth);

  // IE7 quirk -- look for unwanted overlap cause by an off by 1px error
  var vOverlap = bSelf.isOverlap('topRight','bottomRight');
  var hOverlap = bSelf.isOverlap('bottomLeft','bottomRight');
  if (vOverlap) bSelf.setStyle('topRight','height',lineHeight-vOverlap[1]);
  if (hOverlap) bSelf.setStyle('bottomLeft','width',lineWidth-hOverlap[0]);

  if (vOrient == 'up') {
    var activeTop = bSelf.activeTop - bSelf.vOffset - bSelf.stemHeight - lineHeight;
    bSelf.setStyle(balloon,'top',activeTop);
    bSelf.setStyle(balloon,'display','inline');
  }
  else {
    var activeTop = bSelf.activeTop + bSelf.vOffset + bSelf.stemHeight;
    bSelf.setStyle(balloon,'top',activeTop);
  }
}

Balloon.prototype.hideTooltip = function(override) {
  // some browsers pass the event object == we don't want it
  if (override && typeof override == 'object') override = false;
  if (balloonIsSticky && !override) return false;

  var bSelf = currentBalloonClass;
  currentBalloonClass = null;

  if (bSelf) window.clearTimeout(bSelf.timeoutTooltip);

  if (balloonIsSticky && bSelf) bSelf.currentElement = null;

  balloonIsVisible = false;
  balloonIsSticky  = false;

  if (!bSelf) {
    var hideBalloon  = document.getElementById('balloon');
    if (hideBalloon) Balloon.prototype.setStyle(hideBalloon,'display','none');
  }
  else if (bSelf.activeBalloon) {
    bSelf.setStyle(bSelf.activeBalloon,'display','none');
  }
  Balloon.prototype.showHideSelect(1);
}

// this function is meant to be called externally to clear
// any open balloons
hideAllTooltips = function() {
  var bSelf = currentBalloonClass;
  if (!bSelf) return;
  window.clearTimeout(bSelf.timeoutTooltip);
  if (bSelf.activeBalloon) bSelf.setStyle(bSelf.activeBalloon,'display','none');
  balloonIsVisible    = false;
  balloonIsSticky     = false;
  currentBalloonClass = null;
}


// Set the active mouseover coordinates
Balloon.prototype.setActiveCoordinates = function(evt) {
  var el = this.getEventTarget(evt);
  var XY = this.eventXY(evt);

  // is this an image map area?
  var area     = el.getAttribute('coords');
  var isImage  = el.tagName.match('img', 'i');
  var isTooBig = this.getLoc(el,'height') > 50;

  // prefer element vertical bounds if available
  // otherwise, use event's
  if (!area && !isImage && !isTooBig) {
    this.activeTop = this.getLoc(el,'y1') - 10;
  }
  else {
    this.activeTop =  XY[1] - 10;
  }

  this.activeLeft = XY[0] - 10;
  this.activeRight = this.activeLeft + 20;

  this.activeBottom = !area && this.getLoc(el,'y2');
  if (this.activeBottom) this.activeBottom += 10;
  else this.activeBottom = this.activeTop + 20;
}


////
// event XY and getEventTarget Functions based on examples by Peter-Paul
// Koch http://www.quirksmode.org/js/events_properties.html
Balloon.prototype.eventXY = function(event) {
  var XY = new Array(2);
  var e = event || window.event;
  XY[0] = e.pageX || e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
  XY[1] = e.pageY || e.clientY + document.body.scrollTop  + document.documentElement.scrollTop;
  return XY;
}

Balloon.prototype.getEventTarget = function(event) {
  var targ;
  var e = event || window.event;
  if (e.target) targ = e.target;
  else if (e.srcElement) targ = e.srcElement;
  if (targ.nodeType == 3) targ = targ.parentNode; // Safari
  return targ;
}
////


Balloon.prototype.setStyle = function(el,att,val) {
  if (val && att.match(/left|top|bottom|right|width|height|padding|margin/)) val += 'px'; 
  if (el) YAHOO.util.Dom.setStyle(el,att,val);
}

// Uses YAHOO's region class for element coordinates
Balloon.prototype.getLoc = function(el,request) {
  var region = YAHOO.util.Dom.getRegion(el);

  switch(request) {
    case ('y1') : return parseInt(region.top);
    case ('y2') : return parseInt(region.bottom);
    case ('x1') : return parseInt(region.left);
    case ('x2') : return parseInt(region.right);
    case ('width')  : return (parseInt(region.right) - parseInt(region.left));
    case ('height') : return (parseInt(region.bottom) - parseInt(region.top));
    case ('region') : return region; 
 }
}

// We don't know if numbers are overridden with strings
// so play it safe
Balloon.prototype.parseIntAll = function() {
  this.padding     = parseInt(this.padding);
  this.shadow      = parseInt(this.shadow);
  this.stemHeight  = parseInt(this.stemHeight);
  this.stemOverlap = parseInt(this.stemOverlap);
  this.vOffset     = parseInt(this.vOffset);
  this.delayTime   = parseInt(this.delayTime);
}


// IE select z-index bug
// improved method courtesy of Lincoln Stein
Balloon.prototype.showHideSelect = function(visible) {
  var bSelf = currentBalloonClass || new Balloon;
  if (!this.isOldIE()) return false;
  if (!visible) {
    var balloonSelects = document.getElementById('contents').getElementsByTagName('select');
    var myHash = new Object();
    for (var i=0; i<balloonSelects.length; i++) {
      var id = balloonSelects[i].id || balloonSelects[i].name;
      myHash[id] = 1;
    }
    balloonInvisibleSelects = new Array();
    var allSelects = document.getElementsByTagName('select');
    for (var i=0; i<allSelects.length; i++) {
      var id = allSelects[i].id || allSelects[i].name;
      if (bSelf.isOverlap(allSelects[i],bSelf.activeBalloon) && !myHash[id]) {
 	balloonInvisibleSelects.push(allSelects[i]);
 	bSelf.setStyle(allSelects[i],'visibility','hidden');
      }
    }
  }
  else if (balloonInvisibleSelects) {
    for (var i=0; i < balloonInvisibleSelects.length; i++) {
      var id = balloonInvisibleSelects[i].id || balloonInvisibleSelects[i].name;
      bSelf.setStyle(balloonInvisibleSelects[i],'visibility','visible');
    }
    balloonInvisibleSelects = null;
  }
}

// Try to find overlap 
Balloon.prototype.isOverlap = function(el1,el2) {
  if (!el1 || !el2) return false;
  var R1 = this.getLoc(el1,'region');
  var R2 = this.getLoc(el2,'region');
  if (!R1 || !R2) return false; 
 
  // being conservative; make the balloon area a bit bigger
  if (el2.id == 'balloon') {
    R2.top = R2.top - 30;
    R2.left = R2.left - 30;
    R2.right = R2.right + 30;
    R2.bottom = R2.bottom + 30;
  }

  var intersect = R1.intersect(R2);
  if (intersect) {
    // extent of overlap;
    intersect = new Array((intersect.right - intersect.left),(intersect.bottom - intersect.top));
  }
  return intersect;
}

// Coordinate-based test for the same element
Balloon.prototype.isSameElement = function(el1,el2) {
  if (!el1 || !el2) return false;
  var R1 = this.getLoc(el1,'region');
  var R2 = this.getLoc(el2,'region');
  var same = R1.contains(R2) && R2.contains(R1);
  return same ? true : false;
}


///////////////////////////////////////////////////////
// AJAX widget to fill the balloons
// requires prototype.js
///////////////////////////////////////////////////////
Balloon.prototype.getContents = function(section) {

  // just pass it back if no AJAX handler is required.
  if (!this.helpUrl && !this.activeUrl) return section;

  // or if the comntents are alreday loaded
  if (this.loadedFromElement) return section;

  // inline URL takes precedence
  var url = this.activeUrl || this.helpUrl;

  var pars = this.activeUrl ? '' : 'section='+section;
  var ajax  = new Ajax.Request( url,
                           { method:   'get',
                             asynchronous: false,
		             parameters:  pars,
                             onSuccess: function(t) { Balloon.prototype.updateResult(t.responseText) },
                             onFailure: function(t) { alert('AJAX Failure! '+t.statusText)}});

  // activeUrl is meant to be single-use only
  this.activeUrl = null;

  return this.helpText || section;
}

Balloon.prototype.updateResult = function(text) {
  this.helpText = text;
}

// test for internet explorer
Balloon.prototype.isIE = function() {
  return document.all && !window.opera;
}

// test for internet explorer (but not IE7)
Balloon.prototype.isOldIE = function() {
  if (navigator.appVersion.indexOf("MSIE") == -1) return false;
  var temp=navigator.appVersion.split("MSIE");
  return parseFloat(temp[1]) < 7;
}
