/*
 balloon.js -- a DHTML library for balloon tooltips

 $Id$

 See http://www.gmod.org/wiki/index.php/Popup_Balloons
 for documentation.

 Copyright (c) 2007,2008 Sheldon McKay, Cold Spring Harbor Laboratory

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

*/

// These global variables are necessary to avoid losing scope when
//setting the balloon timeout and for inter-object communication
var currentBalloonClass;
var balloonIsVisible;
var balloonIsSticky;
var balloonInvisibleSelects;
var balloonIsSuppressed;
var tooltipIsSuppressed;
var supportsTouch = ('createTouch' in document);

//////////////////////////////////////////////////////////////////////////
// This is constructor that is called to initialize the Balloon object  //
//////////////////////////////////////////////////////////////////////////
var Balloon = function () {
  // Cursor tracking enabled by default
  this.trackCursor = true;
  
  // Cursor tracking halts after one of these vertical
  // or horizontal thresholds are reached
  this.stopTrackingX = 100;
  this.stopTrackingY = 50;

  // Track the cursor every time the mouse moves
  document.onmousemove = this.setActiveCoordinates;

  // scrolling aborts unsticky balloons
  document.onscroll    = Balloon.prototype.hideTooltip;

  // for IE, the balloons can;t start until the page is finished loading
  // set a flag that will get toggled when loading is finished
  if (this.isIE()) {
      this.suppress = true;
  } else {
      // make balloons go away if the page is unloading or waiting
      // to unload. Note that we do not call this for IE because
      // IE8 has a bug which triggers beforeunload event every time
      // an anchor is clicked, and stopping event propagation doesn't
      // seem to fix it.
      window.onbeforeunload = function(){
            Balloon.prototype.hideTooltip(1);
            balloonIsSuppressed = true;
      };
  }

  return this;
}

//////////////////////////////////////////////////////////////////////////
// This is the function that is called on mouseover.  It has a built-in //
// delay time to avoid balloons popping up on rapid mouseover events    //
//////////////////////////////////////////////////////////////////////////
Balloon.prototype.showTooltip = function(evt,caption,sticky,width,height) {

  // If the object is not configured by now, fall back to default
  if (!this.configured) {
    BalloonConfig(this,'GBubble');
  }

  // Awful IE bug, page load aborts if the balloon is fired
  // before the page is fully loaded.
  if (this.isIE() && document.readyState.match(/complete/i)) {
    this.suppress = false;
  }

  // All balloons have been suppressed, go no further
  if (this.suppress || balloonIsSuppressed) {
    return false;
  }

  // Non-sticky balloons suppressed
  if (tooltipIsSuppressed && !sticky) {
    return false;
  }

  // We use 1-100 scale for opacity internally
  if (this.opacity && this.opacity < 1) {
    this.opacity = parseInt(parseFloat(this.opacity) * 100);
  }
  else if (this.opacity && this.opacity == 1) {
    this.opacity = 100;
  }
  else if (!this.opacity) {
    this.opacity == 100;
  }

  // Sorry Konqueror, no fade-in or translucency for you!
  if (this.isKonqueror()) {
    this.allowFade = false;
    this.opacity   = 100;
  }

  // With IE, fading and translucency are not very compatible
  // use opaque balloons if fadein is enabled
  if (this.isIE() && this.allowFade) {
    this.opacity = 100;
  }

  // Check for mouseover (vs. mousedown or click)
  var mouseOver = evt.type.match('mouseover','i');  

  // if the firing event is a click, fade-in and a non-sticky balloon make no sense
  if (!mouseOver) {
    sticky = true;
    this.fadeOK = false;
  }
  else {
    this.fadeOK = this.allowFade;
  }

  // Don't fire on mouseover if a non-sticky balloon is visible
  if (balloonIsVisible && !balloonIsSticky && mouseOver) {
    return false;
  }

  // Don't start a non-sticky balloon if a sticky one is visible
  if (balloonIsVisible && balloonIsSticky && !sticky) {
    return false;
  }

  // Ignore repeated firing of mouseover->mouseout events on 
  // the same element (Safari)
  var el = this.getEventTarget(evt);
  if (sticky && mouseOver && this.isSameElement(el,this.currentElement)) {
    return false;
  }  
  this.firingElement = el;

  // A new sticky balloon can erase an old one
  if (sticky) this.hideTooltip(1);

  // attach a mouseout event handler to the target element
  var closeBalloon = function() { 
    var override = balloonIsSticky && !balloonIsVisible;
    Balloon.prototype.hideTooltip(override)
  }
  if (!mouseOver) {
    el.onmouseup  = function() {return false};
  }
  el.onmouseout = closeBalloon;
  
  balloonIsSticky = sticky;

  this.hideTooltip();

  // request the contents synchronously (ie wait for result)
  this.currentHelpText = this.getAndCheckContents(caption);

  // no contents? abort.
  if (!this.currentHelpText) {
    return false;
  }

  this.width  = width;
  this.height = height;
  this.actualWidth = null;

  // make sure old balloons are removed
  this.cleanup();

  // Put the balloon contents and images into a visible (but offscreen)
  // element so they will be preloaded and have a layout to 
  // calculate the balloon dimensions
  this.container = document.createElement('div');
  this.container.id = 'container';
  document.body.appendChild(this.container);
  this.setStyle(this.container,'position','absolute');
  this.setStyle(this.container,'top',-8888);
  this.setStyle(this.container,'fontFamily',this.fontFamily);
  this.setStyle(this.container,'fontSize',this.fontSize);
  this.container.innerHTML = unescape(this.currentHelpText);

  // make sure balloon image path is complete
  if (this.images) {

    // main background image
    this.balloonImage  = this.balloonImage  ? this.images +'/'+ this.balloonImage  : false;
    this.ieImage       = this.ieImage       ? this.images +'/'+ this.ieImage       : false;

    // optional stems
    this.upLeftStem    = this.upLeftStem    ? this.images +'/'+ this.upLeftStem    : false;
    this.upRightStem   = this.upRightStem   ? this.images +'/'+ this.upRightStem   : false;
    this.downLeftStem  = this.downLeftStem  ? this.images +'/'+ this.downLeftStem  : false;
    this.downRightStem = this.downRightStem ? this.images +'/'+ this.downRightStem : false;

    this.closeButton   = this.closeButton   ? this.images +'/'+ this.closeButton   : false;

    this.images        = false;
  }

  // The PNG alpha channels (shadow transparency) are not 
  // handled properly by IE < 6.  Also, if opacity is set to
  // < 1 (translucent balloons), any version of IE does not
  // handle the image properly.
  // Google chrome is a bit dodgey too
  // If there is an IE image provided, use that instead.
  if (this.ieImage && (this.isIE() || this.isChrome())) {
    if (this.isOldIE() || this.opacity || this.allowFade) {    
      this.balloonImage = this.ieImage;
    }
  }

  // preload balloon images 
  if (!this.preloadedImages) {
    var images = new Array(this.balloonImage, this.closeButton);
    if (this.ieImage) {
      images.push(this.ieImage);
    }
    if (this.stem) {
      images.push(this.upLeftStem,this.upRightStem,this.downLeftStem,this.downRightStem);
    }
    var len = images.length;
    for (var i=0;i<len;i++) {
      if ( images[i] ) {
        this.preload(images[i]);
      }
    }
    this.preloadedImages = true;
  }

  currentBalloonClass = this;

  // Capture coordinates for mousedown or click
  if (!mouseOver) {
    this.setActiveCoordinates(evt);
  }

  // Remember which event started this
  this.currentEvent = evt;

  // prevent interaction with gbrowse drag and drop
  evt.cancelBubble  = true;

  // Make delay time short for onmousedown
  var delay = mouseOver ? this.delayTime : 1;
  this.timeoutTooltip = window.setTimeout(this.doShowTooltip,delay);
  this.pending = true;

  return false;
}


// Preload the balloon background images
Balloon.prototype.preload = function(src) {
  var i = new Image;
  i.src = src;

  // append to the DOM tree so the images have a layout,
  // then remove.
  this.setStyle(i,'position','absolute');
  this.setStyle(i,'top',-8000);
  document.body.appendChild(i);
  document.body.removeChild(i);
}


/////////////////////////////////////////////////////////////////////
// Tooltip rendering function
/////////////////////////////////////////////////////////////////////
Balloon.prototype.doShowTooltip = function() {
  var self = currentBalloonClass;

  // Stop firing if a balloon is already being displayed
  if (balloonIsVisible) return false;  

  if (!self.parent) {
    if (self.parentID) {
      self.parent = $(self.parentID);
    }
    else {
      self.parent = document.body;
    }
    self.xOffset = self.getLoc(self.parent, 'x1');
    self.yOffset = self.getLoc(self.parent, 'y1');
  }

  // a short delay time might cause some intereference
  // with fading
  window.clearTimeout(self.timeoutFade);
  self.setStyle('balloon','display','none');

  // make sure user-configured numbers are not strings
  self.parseIntAll();

  // create the balloon object
  var balloon = self.makeBalloon();

  // window dimensions
  var pageWidth   = document.viewport.getWidth();
  var pageCen     = Math.round(pageWidth/2);
  var pageHeight  = document.viewport.getHeight()
  var pageLeft    = document.viewport.getScrollOffsets().left;
  var pageTop     = document.viewport.getScrollOffsets().top;
  var pageMid     = pageTop + Math.round(pageHeight/2);
  self.pageBottom = pageTop + pageHeight;
  self.pageTop    = pageTop;
  self.pageLeft   = pageLeft;
  self.pageRight  = pageLeft + pageWidth;

  // do we have a cursor position?
  //  if (!(self.activeTop && self.activeRight)) {
  // self.setActiveCoordinates();
  // }

  // balloon orientation
  var vOrient = self.activeTop > pageMid ? 'up' : 'down';
  var hOrient = self.activeRight > pageCen ? 'left' : 'right';
  
  // get the preloaded balloon contents
  var helpText = self.container.innerHTML;
  self.actualWidth = self.getLoc(self.container,'width') + 20;
  self.parent.removeChild(self.container);
  var wrapper = document.createElement('div');
  wrapper.id = 'contentWrapper';
  self.contents.appendChild(wrapper);
  if ('createTouch' in document) {
      wrapper.innerHTML = helpText + Controller.translate('IPAD_BALLOON');
  }else{
    wrapper.innerHTML = helpText;
  }

  // run any javascript in the thing -- sorry Sheldon
  if (self.evalScripts) {
     helpText.evalScripts();
  }

  // how and where to draw the balloon
  self.setBalloonStyle(vOrient,hOrient,pageWidth,pageLeft);

  // close control for balloon or box
  if (balloonIsSticky) {
    self.addCloseButton();
  }

  balloonIsVisible = true;
  self.pending = false;  

  // in IE < 7, hide <select> elements
  self.showHide();

  self.startX = self.activeLeft;
  self.startY = self.activeTop;

  self.fade(0,self.opacity,self.fadeIn);

  return false;
}

Balloon.prototype.addCloseButton = function () {
  var self         = currentBalloonClass;
  var margin       = Math.round(self.padding/2);
  var closeWidth   = self.closeButtonWidth || 16;
  var balloonTop   = self.getLoc('balloon','y1') + margin + self.shadow;
  var BalloonLeft  = self.getLoc('topRight','x2') - self.closeButtonWidth - self.shadow - margin;
  var closeButton  = $('closeButton');

  if (!closeButton) {
    closeButton = new Image;
    closeButton.setAttribute('id','closeButton');
    closeButton.setAttribute('src',self.closeButton);
    closeButton.onclick = function() {
      Balloon.prototype.hideTooltip(1);
    };
    self.setStyle(closeButton,'position','absolute');
    document.body.appendChild(closeButton);
  }

  // I have no idea why
  if (self.isIE()) {
    BalloonLeft = BalloonLeft - 5;
  }

  self.setStyle(closeButton,'top',balloonTop);
  self.setStyle(closeButton,'left',BalloonLeft);
  self.setStyle(closeButton,'display','inline');
  self.setStyle(closeButton,'cursor','pointer');
  self.setStyle(closeButton,'zIndex',999999999);
}

// use a fresh object every time to make sure style 
// is not polluted
Balloon.prototype.makeBalloon = function() {
  var self = currentBalloonClass;

  var balloon = $('balloon');
  if (balloon) {
    self.cleanup();
  }

  balloon = document.createElement('div');
  balloon.setAttribute('id','balloon');
  self.parent.appendChild(balloon);
  self.activeBalloon = balloon;

  self.parts = new Array();
  var parts = new Array('contents','topRight','bottomRight','bottomLeft');
  for (var i=0;i<parts.length;i++) {
    var child = document.createElement('div');
    child.setAttribute('id',parts[i]);
    balloon.appendChild(child);
    if (parts[i] == 'contents') self.contents = child;
    self.parts.push(child);
  }
  //self.parts.push(balloon);

  if (self.displayTime)  {
      self.timeoutAutoClose = window.setTimeout(this.hideTooltip,self.displayTime);
  }
  return balloon;
}

Balloon.prototype.setBalloonStyle = function(vOrient,hOrient,pageWidth,pageLeft) {
  var self = currentBalloonClass;
  var balloon = self.activeBalloon;

  if (typeof(self.shadow) != 'number') self.shadow = 0;
  if (!self.stem) self.stemHeight = 0;

  var fullPadding   = self.padding + self.shadow;
  var insidePadding = self.padding;
  var outerWidth    = self.actualWidth + fullPadding;
  var innerWidth    = self.actualWidth;  

  self.setStyle(balloon,'position','absolute');
  self.setStyle(balloon,'top',-9999);
  self.setStyle(balloon,'zIndex',1000000);

  if (self.height) {
    self.setStyle('contentWrapper','height',self.height-fullPadding);
  }

  if (self.width) {
    self.setStyle(balloon,'width',self.width);  
    innerWidth = self.width - fullPadding;
    if (balloonIsSticky) {
      innerWidth -= self.closeButtonWidth;
    }
    self.setStyle('contentWrapper','width',innerWidth);
  }
  else {
    self.setStyle(balloon,'width',outerWidth);
    self.setStyle('contentWrapper','width',innerWidth);
  }

  // not too big...
  if (!self.width && self.maxWidth && outerWidth > self.maxWidth) {
    self.setStyle(balloon,'width',self.maxWidth);
    self.setStyle('contentWrapper','width',self.maxWidth-fullPadding);
  }
  // not too small...
  if (!self.width && self.minWidth && outerWidth < self.minWidth) {
    self.setStyle(balloon,'width',self.minWidth);
    self.setStyle('contentWrapper','width',self.minWidth-fullPadding);
  }
  
  self.setStyle('contents','zIndex',2);
  self.setStyle('contents','color',self.fontColor);
  self.setStyle('contents','fontFamily',self.fontFamily);
  self.setStyle('contents','fontSize',self.fontSize);
  self.setStyle('contents','background','url('+self.balloonImage+') top left no-repeat');
  self.setStyle('contents','paddingTop',fullPadding);
  self.setStyle('contents','paddingLeft',fullPadding);

  self.setStyle('bottomRight','background','url('+self.balloonImage+') bottom right no-repeat');
  self.setStyle('bottomRight','position','absolute');
  self.setStyle('bottomRight','right',0-fullPadding);
  self.setStyle('bottomRight','bottom',0-fullPadding);
  self.setStyle('bottomRight','height',fullPadding);
  self.setStyle('bottomRight','width',fullPadding);
  self.setStyle('bottomRight','zIndex',-1);

  self.setStyle('topRight','background','url('+self.balloonImage+') top right no-repeat');
  self.setStyle('topRight','position','absolute');
  self.setStyle('topRight','right',0-fullPadding);
  self.setStyle('topRight','top',0);
  self.setStyle('topRight','width',fullPadding);

  self.setStyle('bottomLeft','background','url('+self.balloonImage+') bottom left no-repeat');
  self.setStyle('bottomLeft','position','absolute');
  self.setStyle('bottomLeft','left',0);
  self.setStyle('bottomLeft','bottom',0-fullPadding);
  self.setStyle('bottomLeft','height',fullPadding);
  self.setStyle('bottomLeft','zIndex',-1);

  if (this.stem) {
    var stem = document.createElement('img');
    self.setStyle(stem,'position','absolute');
    balloon.appendChild(stem);
 
    if (vOrient == 'up' && hOrient == 'left') {  
      stem.src = self.upLeftStem;
      var height = self.stemHeight + insidePadding - self.stemOverlap;
      self.setStyle(stem,'bottom',0-height);
      self.setStyle(stem,'right',0);             
    }
    else if (vOrient == 'down' && hOrient == 'left') {
      stem.src = self.downLeftStem;
      var height = self.stemHeight - (self.shadow + self.stemOverlap);
      self.setStyle(stem,'top',0-height);
      self.setStyle(stem,'right',0);
    }
    else if (vOrient == 'up' && hOrient == 'right') {
      stem.src = self.upRightStem;
      var height = self.stemHeight + insidePadding - self.stemOverlap;
      self.setStyle(stem,'bottom',0-height);
      self.setStyle(stem,'left',self.shadow);
    }
    else if (vOrient == 'down' && hOrient == 'right') {
      stem.src = self.downRightStem;
      var height = self.stemHeight - (self.shadow + self.stemOverlap);
      self.setStyle(stem,'top',0-height);
      self.setStyle(stem,'left',self.shadow);
    }
    if (self.fadeOK && self.isIE()) {
      self.parts.push(stem);
    }
  }

  if (self.allowFade) {
    self.setOpacity(1);
  }
  else if (self.opacity) {
    self.setOpacity(self.opacity);
  }

  // flip left or right, as required
  if (hOrient == 'left') {
    var pageWidth = self.pageRight - self.pageLeft;
    var activeRight = pageWidth - self.activeLeft;
    self.setStyle(balloon,'right',activeRight);
  }
  else {
    var activeLeft = self.activeRight - self.xOffset;
    self.setStyle(balloon,'left',activeLeft);
  }

  // oversized contents? Scrollbars for sticky balloons, clipped for non-sticky
  var overflow = balloonIsSticky ? 'auto' : 'hidden';
  self.setStyle('contentWrapper','overflow',overflow);

  // a bit of room for the closebutton
  if (balloonIsSticky) {
    self.setStyle('contentWrapper','margin-right',self.closeButtonWidth);
  }

  // Make sure the balloon is not offscreen horizontally.
  // We handle vertical sanity checking later, after the final
  // layout is set.
  var balloonLeft   = self.getLoc(balloon,'x1');
  var balloonRight  = self.getLoc(balloon,'x2');
  var scrollBar     = 20;

  if (hOrient == 'right' && balloonRight > (self.pageRight - fullPadding)) {
    var width = (self.pageRight - balloonLeft) - fullPadding - scrollBar;
    self.setStyle(balloon,'width',width);
    self.setStyle('contentWrapper','width',width-fullPadding);
  }
  else if (hOrient == 'left' && balloonLeft < (self.pageLeft + fullPadding)) {
    var width = (balloonRight - self.pageLeft) - fullPadding;
    self.setStyle(balloon,'width',width);
    self.setStyle('contentWrapper','width',width-fullPadding);
  }

  // Get the width/height for the right and bottom outlines
  var balloonWidth  = self.getLoc(balloon,'width');
  var balloonHeight = self.getLoc(balloon,'height');

  // IE7 quirk -- look for unwanted overlap cause by an off by 1px error
  var vOverlap = self.isOverlap('topRight','bottomRight');
  var hOverlap = self.isOverlap('bottomLeft','bottomRight');
  if (vOverlap) {
    self.setStyle('topRight','height',balloonHeight-vOverlap[1]);
  }
  if (hOverlap) {
    self.setStyle('bottomLeft','width',balloonWidth-hOverlap[0]);
  }

  // vertical position of the balloon
  if (vOrient == 'up') {
    var activeTop = self.activeTop - balloonHeight;
    self.setStyle(balloon,'top',activeTop);
  }
  else {
    var activeTop = self.activeBottom;
    self.setStyle(balloon,'top',activeTop);
  }

  // Make sure the balloon is vertically contained in the window
  var balloonTop    = self.getLoc(balloon,'y1');
  var balloonBottom = self.height ? balloonTop + self.height : self.getLoc(balloon,'y2');
  var deltaTop      = balloonTop < self.pageTop ? self.pageTop - balloonTop : 0;
  var deltaBottom   = balloonBottom > self.pageBottom ? balloonBottom - self.pageBottom : 0;

  if (vOrient == 'up' && deltaTop) {
    var newHeight = balloonHeight - deltaTop;
    if (newHeight > (self.padding*2)) {
      self.setStyle('contentWrapper','height',newHeight-fullPadding);
      self.setStyle(balloon,'top',self.pageTop+self.padding);
      self.setStyle(balloon,'height',newHeight);
    }
  }
  if (vOrient == 'down' && deltaBottom) {
    var newHeight = balloonHeight - deltaBottom - scrollBar;
    if (newHeight > (self.padding*2) + scrollBar) {
      self.setStyle('contentWrapper','height',newHeight-fullPadding);
      self.setStyle(balloon,'height',newHeight);
    }
  }

  // If we have an iframe, make sure it fits properly
  var iframe = balloon.getElementsByTagName('iframe');
  if (iframe[0]) {
    iframe = iframe[0];
    var w = self.getLoc('contentWrapper','width');
    if (balloonIsSticky && !this.isIE()) {
      w -= self.closeButtonWidth;
    }
    var h = self.getLoc('contentWrapper','height');
    self.setStyle(iframe,'width',w);
    self.setStyle(iframe,'height',h);
    self.setStyle('contentWrapper','overflow','hidden');
  }

  // Make edges match the main balloon body
  self.setStyle('topRight', 'height', self.getLoc(balloon,'height'));
  self.setStyle('bottomLeft','width', self.getLoc(balloon,'width'));

  // next section is some debugging for IE8 problem
  //  var b = self.activeBalloon;
  //  var bwidth  = self.getLoc(b,'width');
  //  self.setStyle(b,'right',null);
  //  var newLeft = self.activeLeft - bwidth;
  //  self.setStyle(b,'left',newLeft);
  
  self.hOrient = hOrient;
  self.vOrient = vOrient;

  self.adjustBalloonPosition();  // for IE8
}


// Fade method adapted from an example on 
// http://brainerror.net/scripts/javascript/blendtrans/
Balloon.prototype.fade = function(opacStart, opacEnd, millisec) {
  var self = currentBalloonClass || new Balloon;
  if (!millisec || !self.allowFade) {
    return false;
  }

  opacEnd = opacEnd || 100;

  //speed for each frame
  var speed = Math.round(millisec / 100);
  var timer = 0;
  for(o = opacStart; o <= opacEnd; o++) {
    self.timeoutFade = setTimeout('Balloon.prototype.setOpacity('+o+')',(timer*speed));
    timer++;
  }
}

Balloon.prototype.setOpacity = function(opc) {
  var self = currentBalloonClass;
  if (!self || !opc) return false;

  var o = parseFloat(opc/100);

  // opacity handled differently for IE
  var parts = self.isIE() ? self.parts : [self.activeBalloon];

  var len = parts.length;
  for (var i=0;i<len;i++) {
    self.doOpacity(o,opc,parts[i]);
  }
}

Balloon.prototype.doOpacity = function(op,opc,el) {
  var self = currentBalloonClass;
  if (!el) return false;

  // CSS standards-compliant browsers!
  self.setStyle(el,'opacity',op);

  // old IE
  self.setStyle(el,'filter','alpha(opacity='+opc+')');

  // old Mozilla/NN
  self.setStyle(el,'MozOpacity',op);

  // old Safari
  self.setStyle(el,'KhtmlOpacity',op);
}

Balloon.prototype.hideTooltip = function(override) {

  // some browsers pass the event object == we don't want it
  if (override == null)  override = false;
  if (override && typeof override == 'object') override = false;

  if (balloonIsSticky && !override) return false;

  var self = currentBalloonClass;
  Balloon.prototype.showHide(1);
  Balloon.prototype.cleanup();

  if (self) {
    window.clearTimeout(self.timeoutTooltip);
    window.clearTimeout(self.timeoutFade);
    window.clearTimeout(self.timeoutAutoClose);
    if (balloonIsSticky) {
      self.currentElement = null;
    }
    self.startX = 0;
    self.startY = 0;
  }

  balloonIsVisible = false;
  balloonIsSticky  = false;
}

// Garbage collection
Balloon.prototype.cleanup = function() {
  var self = currentBalloonClass;
  var body;
  if (self) {
    body = self.parent   ? self.parent 
         : self.parentID ? $(self.parentID) || document.body
         : document.body;
  }
  else {
    body = document.body;
  }
  
  var bubble = $('balloon');
  var close  = $('closeButton');
  var cont   = $('container');
  if (bubble) { body.removeChild(bubble) } 
  if (close)  { body.removeChild(close)  }
  if (cont)   { body.removeChild(cont)   }
}


// this function is meant to be called externally to clear
// any open balloons
hideAllTooltips = function() {
  var self = currentBalloonClass;
  if (!self) return;
  window.clearTimeout(self.timeoutTooltip);
  if (self.activeBalloon) self.setStyle(self.activeBalloon,'display','none');
  balloonIsVisible    = false;
  balloonIsSticky     = false;
  currentBalloonClass = null;
}


// Track the active mouseover coordinates
Balloon.prototype.setActiveCoordinates = function(evt) {
  var self = currentBalloonClass;
  if (!self) {
    return true;
  }
  var evt = evt || window.event || self.currentEvent;
  if (!evt) {
    return true;
  }

  // avoid silent NaN errors
  self.hOffset = self.hOffset || 1;
  self.vOffset = self.vOffset || 1;
  self.stemHeight = self.stem && self.stemHeight ? (self.stemHeight|| 0) : 0;

  var scrollTop  = 0;
  var scrollLeft = 0;

  var XY = self.eventXY(evt);
  adjustment   = self.hOffset < 20 ? 10 : 0;
  self.activeTop    = scrollTop  + XY[1] - adjustment - self.vOffset - self.stemHeight;
  self.activeLeft   = scrollLeft + XY[0] - adjustment - self.hOffset;
  self.activeRight  = scrollLeft + XY[0];
  self.activeBottom = scrollTop  + XY[1] + self.vOffset + 2*adjustment;

  // dynamic positioning but only if the balloon is not sticky
  // and cursor tracking is enabled
  if (balloonIsVisible && !balloonIsSticky && self.trackCursor) {
    var deltaX = Math.abs(self.activeLeft - self.startX);
    var deltaY = Math.abs(self.activeTop - self.startY);

    if (deltaX > self.stopTrackingX || deltaY > self.stopTrackingY) {
	self.hideTooltip();
    }
    else {
	self.adjustBalloonPosition();
    }
  }

  return true;
}

Balloon.prototype.adjustBalloonPosition = function() {
      var self = currentBalloonClass;
      var b = self.activeBalloon;
      var bwidth  = self.getLoc(b,'width');
      var bheight = self.getLoc(b,'height');
      var btop    = self.getLoc(b,'y1');
      var bleft   = self.getLoc(b,'x1');

      if (self.hOrient == 'right') {
        self.setStyle(b,'left',self.activeRight);
      }
      else if (self.hOrient == 'left') {
        self.setStyle(b,'right',null);
        var newLeft = self.activeLeft - bwidth;
        self.setStyle(b,'left',newLeft);
      }

      if (self.vOrient == 'up') {
        self.setStyle(b,'top',self.activeTop - bheight);
      }
      else if (self.vOrient == 'down') {
        self.setStyle(b,'top',self.activeBottom);
      }
}

////
// event XY and getEventTarget Functions based on examples by Peter-Paul
// Koch http://www.quirksmode.org/js/events_properties.html
Balloon.prototype.eventXY = function(event) {
  var XY = new Array(2);
  var e = event || window.event;
  if (!e) {
    return false;
  }
  if (e.pageX || e.pageY) {
    XY[0] = e.pageX;
    XY[1] = e.pageY;
  }
  else if ( e.clientX || e.clientY ) {
    XY[0] = e.clientX + document.body.scrollLeft + document.documentElement.scrollLeft;
    XY[1] = e.clientY + document.body.scrollTop  + document.documentElement.scrollTop;
  }

  return XY;
}

Balloon.prototype.getEventTarget = function(event) {
  var targ;
  var e = event || window.event;
  if (e.target) targ = e.target;
  else if (e.srcElement) targ = e.srcElement;
  if (targ==null) targ=document.createElement('div');
  if (targ.nodeType == 3) 
      targ = targ.parentNode; // Safari
  return targ;
}
////


Balloon.prototype.setStyle = function(el,att,val) {
  if (!el) { 
    return false;
  }
  if (typeof(el) != 'object') {
    el = $(el);
  }
  if (!el) {
    return false;
  }
  el = Element.extend(el);

  if (val && att.match(/left|top|bottom|right|width|height|padding|margin/)) {
    val = new String(val);
    if (!val.match(/auto/)) {
      val += 'px';
    }
  }

  // z-index does not work as expected
  if (att == 'zIndex') {
    if (el.style) {
      el.style.zIndex = parseInt(val);
    }
  }
  else {
    var style = {};
    style[att] = val;
    el.setStyle(style);
  }
}


Balloon.prototype.getLoc = function(el,request) {
  var offset = $(el).cumulativeOffset();
  var dimensions = $(el).getDimensions();
  switch(request) {
    case ('y1') : return offset.top;
    case ('y2') : return offset.top + dimensions.height;
    case ('x1') : return offset.left;
    case ('x2') : return offset.left + dimensions.width;
    case ('width')  : return dimensions.width;
    case ('height') : return dimensions.height;
    case ('region') : 
      var region = new Object;
      region.y1 = offset.top;
      region.y2 = offset.top + dimensions.height;
      region.x1 = offset.left;
      region.x2 = offset.left + dimensions.width;
      return region; 
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
  this.width       = parseInt(this.width);
  this.maxWidth    = parseInt(this.maxWidth);
  this.minWidth    = parseInt(this.minWidth);
  this.fadeIn      = parseInt(this.fadeIn) || 1000;
}


// show/hide select elements in older IE
// plus user-defined elements
Balloon.prototype.showHide = function(visible) {
  var self = currentBalloonClass || new Balloon;

  // IE z-index bug fix (courtesy of Lincoln Stein)
  if (self.isOldIE()) {
    var balloonContents = $('contentWrapper');
    if (!visible && balloonContents) {
      var balloonSelects = balloonContents.getElementsByTagName('select');
      var myHash = new Object();
      for (var i=0; i<balloonSelects.length; i++) {
        var id = balloonSelects[i].id || balloonSelects[i].name;
        myHash[id] = 1;
      }
      balloonInvisibleSelects = new Array();
      var allSelects = document.getElementsByTagName('select');
      for (var i=0; i<allSelects.length; i++) {
        var id = allSelects[i].id || allSelects[i].name;
        if (self.isOverlap(allSelects[i],self.activeBalloon) && !myHash[id]) {
          balloonInvisibleSelects.push(allSelects[i]);
          self.setStyle(allSelects[i],'visibility','hidden');
        }
      }
    }
    else if (balloonInvisibleSelects) {
      for (var i=0; i < balloonInvisibleSelects.length; i++) {
        var id = balloonInvisibleSelects[i].id || balloonInvisibleSelects[i].name;
        self.setStyle(balloonInvisibleSelects[i],'visibility','visible');
     }
     balloonInvisibleSelects = null;
    }
  }

  // show/hide any user-specified elements that overlap the balloon
  if (self.hide) {
    var display = visible ? 'inline' : 'none';
    for (var n=0;n<self.hide.length;n++) {
      if (self.isOverlap(self.activeBalloon,self.hide[n])) {
        self.setStyle(self.hide[n],'display',display);
      }
    }
  }
}

// Try to find overlap
Balloon.prototype.isOverlap = function(el1,el2) {
  if (!el1 || !el2) return false;
  var R1 = this.getLoc(el1,'region');
  var R2 = this.getLoc(el2,'region');
  if (!R1 || !R2) return false;

  if ((R1.x1 < R2.x2) && (R1.x2 > R2.x1) && (R1.y1 < R2.y2) && (R1.y2 > R2.y1)) { 
    return new Array((R1.x1 < R2.x1 ? R1.x2 - R2.x1 : R2.x2 - R1.x1),(R1.y1 < R2.y1 ? R1.y2 - R2.y1 : R2.y2 - R1.y1));
  } else {
    return false;
  }
}

// Test for the same element
Balloon.prototype.isSameElement = function(el1,el2) {
  if (!el1 || !el2) return false;
  return el1 == el2;
}


///////////////////////////////////////////////////////
// Security -- get the balloon contents while checking 
// for disallowed elements.
//////////////////////////////////////////////////////
Balloon.prototype.getAndCheckContents = function(caption) {
  var originalCaption = caption;
  var notAllowed = 'are not allowed in popup balloons in this web site.  \
Please contact the site administrator for assistance.';
  var notSupported = 'AJAX is not supported for popup balloons in this web site.  \
Please contact the site administrator for assistance.';
  
  // no Help Url without AJAX
  if (this.helpUrl && !this.allowAJAX) {
    alert('Sorry, you have specified help URL '+this.helpUrl+' but '+notSupported);
    return null;
  }

  // look for a url in the balloon contents
  if (caption.match(/^url:/)) {
    this.activeUrl = caption.replace(/^url:/,'');
    caption = '';
  }
  // or if the text is a bare hyperlink
  else if (caption.match(/^(https?:|\/|ftp:)\S+$/i)) {
    this.activeUrl = caption;
    caption = '';
  }

  // Make sure AJAX is allowed
  if (this.activeUrl && !this.allowAJAX) {
    alert('Sorry, you asked for '+originalCaption+' but '+notSupported);
    return null;
  }  

  // check if the contents are to be retrieved from an element
  if (caption.match(/^load:/)) {
    var load = caption.split(':');
    if (!$(load[1])) alert ('problem locating element '+load[1]);
    caption = $(load[1]).innerHTML;
    this.loadedFromElement = true;
  }

  // check if iframes are allowed
  if (caption.match(/\<\s*iframe/i) && !this.allowIframes) {
    alert('Sorry: iframe elements '+notAllowed);
    return null;
  }

  // check if event handlers are allowed
  if (caption.match(/\bon(load|mouse|click|unload|before)[^=]*=/i) && !this.allowEventHandlers) {
    alert('Sorry: JavaScript event handlers '+notAllowed);
    return null;
  }

  // check for script elements
  if (caption.match(/\<\s*script/i) && !this.allowScripts) {
    alert('Sorry: <script> elements '+notAllowed);
    return null;
  }

  // request the contents
  this.currentHelpText = this.getContents(caption);
  this.loadedFromElement = false;
  
  return this.currentHelpText;;
}


///////////////////////////////////////////////////////
// AJAX widget to fill the balloons
// requires prototype.js
///////////////////////////////////////////////////////
Balloon.prototype.getContents = function(section) {

  // just pass it back if no AJAX handler is required.
  if (!this.helpUrl && !this.activeUrl) return section;

  // or if the contents are already loaded from another element
  if (this.loadedFromElement) return section;

  // inline URL takes precedence
  var url = this.activeUrl || this.helpUrl;
  url    += this.activeUrl ? '' : '?section='+section;

  // activeUrl is meant to be single-use only
  this.activeUrl = null;

  var ajax;
  if (window.XMLHttpRequest) {
    ajax = new XMLHttpRequest();
  } else {
    ajax = new ActiveXObject("Microsoft.XMLHTTP");
  }

  if (ajax) {
    ajax.open("GET", url, false);
    ajax.onreadystatechange=function() {
      //alert(ajax.readyState);
    };
    try {
      ajax.send(null);
    }
    catch (e) {
    // alert(e);
    }
    var txt = this.escapeHTML ? escape(ajax.responseText) : ajax.responseText;
    return  txt || section;
  }
  else {
    return section;
  }
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

// test for Konqueror
Balloon.prototype.isKonqueror = function() {
  return navigator.userAgent.toLowerCase().indexOf( 'konqueror' ) != -1;
}

// and Google chrome
Balloon.prototype.isChrome = function() {
  return navigator.userAgent.toLowerCase().indexOf('chrome') > -1;
}
