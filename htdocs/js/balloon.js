/*
 balloon.js -- a DHTML library for balloon tooltips

 $Id: balloon.js,v 1.1.2.6 2007-08-28 20:15:52 lstein Exp $

 See http://www.wormbase.org/wiki/index.php/Balloon_Tooltips
 for documentation.

 Copyright (c) 2007 Sheldon McKay, Cold Spring Harbor Laboratory

 This balloon tooltip package and associated files not otherwise copyrighted are 
 distributed under the MIT-style license:
 
 http://opensource.org/licenses/mit-license.php


 Copyright (c) 2007 Sheldon McKay, Cold Spring Harbor Laboratory

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


// Only three global variables.  These are necessary to avoid losing
// scope when setting the balloon timeout and for cross-object communication
var currentBalloonClass;
var balloonIsVisible;
var reallySticky;
var balloonInvisibleSelects;


// constructor for balloon class
// Each instance of this class will be populated with default configuration
// variables that can be overwritten
var Balloon = function() {
  
  // Balloon connector (the triangle part) images
  // Default images are provided, they are 48 px in height
  this.upLeftConnector    = '/images/balloons/balloon_up_bottom_left.png';
  this.upRightConnector   = '/images/balloons/balloon_up_bottom_right.png';
  this.downLeftConnector  = '/images/balloons/balloon_down_top_left.png';
  this.downRightConnector = '/images/balloons/balloon_down_top_right.png';

  // Balloon body background images
  // NOTE: the balloon body height is exaggerated to allow for a sliding
  // non-repeat background image for an arbitrary amount of text. The
  // height of the default balloon images is 900px, but only a small part
  // is usually visible, depending on the content dimensions. 
  this.upBalloon   = '/images/balloons/balloon_up_top.png';
  this.downBalloon = '/images/balloons/balloon_down_bottom.png';

  // Balloon dimensions and text placement
  // the default width 300px images (8 pixel shadow)
  this.balloonWidth     = '308px';
  this.paddingTop       = '30px';
  this.paddingLeft      = '15px';
  this.paddingRight     = '15px';
  this.paddingBottom    = '20px';
  this.paddingConnector = '48px';

  // Horizontal offset: allowed values are 'left' and 'right'
  // the offset will be flipped as required to keep the balloon onscreen
  this.hOffset = 'left';

  // Location of optional ajax handler that returns tooltip contents
  //this.helpUrl = '/db/misc/help';

  // Default tooltip text size
  this.balloonTextSize = '90%';

  // Delay (milliseconds) before balloon is displayed
  // Don't set it too low or you may annoy your users!
  this.delayTime = 750;

  this.vOffset = '5px'
  this.isIE    = document.all && !window.opera;
  this.isOpera = window.opera;

  // A random number ID to avoid collisions between different balloon
  // types in the same document
  this.rID = Math.random();
}

/////////////////////////////////////////////////////////////////////////
// This is the function that is called on mouseover.  It has a built-in
// delay time to avoid balloons popping up on rapid mousover events
/////////////////////////////////////////////////////////////////////////

Balloon.prototype.showTooltip = function(evt,caption,sticky) {

  if (sticky) this.hideStaticTooltip(1);

  if (balloonIsVisible && 
      currentBalloonClass.balloonIsStatic && 
      reallySticky) return false;

  var el = this.getEventTarget(evt);
  
  // attach a mousout event to the target element
  el.onmouseout = this.hideTooltip;

  // set the active coordinates
  this.setActiveCoordinates(evt);

  // Opera tooltip workaround
  if (this.isOpera && (el.getAttribute('title') || el.getAttribute('href')) ) 
    sticky = true;

  this.balloonIsStatic ? this.hideStaticTooltip() : this.hideTooltip();  
  this.balloonIsStatic = sticky;
  this.currentHelpText = caption;
  currentBalloonClass = this;
  this.timeoutTooltip = window.setTimeout(this.doShowTooltip,this.delayTime);
}

/////////////////////////////////////////////////////////////////////
// Tooltip rendering function
/////////////////////////////////////////////////////////////////////

Balloon.prototype.doShowTooltip = function() {
  var bSelf = currentBalloonClass;

  // Stop firing if a balloon is already being displayed
  if (balloonIsVisible) return false;  

  // make sure user-configured numbers are not strings
  bSelf.parseIntAll();

  // actual window dimensions
  var pageWidth  = YAHOO.util.Dom.getViewportWidth();
  var pageHeight = YAHOO.util.Dom.getViewportHeight();
  var pageTop    = bSelf.isIE ? document.body.scrollTop : window.pageYOffset;
  var pageMid    = pageTop + pageHeight/2;
  var pageBottom = pageTop + pageHeight;

  // balloon placement tied to onmouseover element
  var left,hOrient;
  if (bSelf.activeLeft < bSelf.balloonWidth) {
    hOrient = 'right';
    left = bSelf.activeRight;
  }
  else if ((bSelf.activeRight + bSelf.balloonWidth) > pageWidth) {
    hOrient = 'left';
    left = bSelf.activeLeft - bSelf.balloonWidth;
  }
  else {
    hOrient = bSelf.hOffset;
    left = hOrient == 'left' ? (bSelf.activeLeft - bSelf.balloonWidth) : bSelf.activeRight;
  }

  // balloon is up if below midline, down otherwise
  var top,vOrient;
  if (bSelf.activeTop > pageMid) {
    vOrient = 'up';
    top = bSelf.activeTop - Math.abs(bSelf.vOffset);
  }
  else {
    vOrient = 'down';
    top = bSelf.activeBottom + Math.abs(bSelf.vOffset);
  }

  // Get or create the balloon layer
  bSelf.activeBalloon = bSelf.getElement('balloon') || bSelf.createAndAppend('balloon');
  bSelf.setStyle(bSelf.activeBalloon,'display','none');
  bSelf.setStyle(bSelf.activeBalloon,'position','absolute');
  bSelf.activeBody = bSelf.getElement('caption') || bSelf.createAndAppend('caption',bSelf.activeBalloon);
  bSelf.activeText = bSelf.getElement('text')    || bSelf.createAndAppend('text',bSelf.activeBody);

  // look for url 
  if (bSelf.currentHelpText.match(/url:/i)) {
    var urlArray = bSelf.currentHelpText.split(':');
    bSelf.currentHelpText = '';
    bSelf.activeUrl = urlArray[1];
  }
  // or if the text is a bare hyperlink
  else if (bSelf.currentHelpText.match(/^(https?:|\/|ftp:)\S+$/i)) {
    bSelf.activeUrl = bSelf.currentHelpText;
    bSelf.currentHelpText = '';
  }	

  // request the contents synchronously (ie wait for result)
  var helpText = bSelf.getContents(bSelf.currentHelpText);

  // configure for up or down orientation
  if (vOrient == 'up') {
    var upConnector = hOrient == 'left' ?  bSelf.upLeftConnector : bSelf.upRightConnector; 
    bSelf.setStyle(bSelf.activeBalloon,'background','url('+upConnector+') bottom left no-repeat');
    bSelf.setStyle(bSelf.activeBalloon,'padding-bottom',bSelf.paddingConnector);
    bSelf.setStyle(bSelf.activeBalloon,'padding-top',bSelf.paddingTop+5);
    bSelf.setStyle(bSelf.activeBody,'background','url('+bSelf.upBalloon+') top left no-repeat');
    bSelf.setStyle(bSelf.activeBody,'padding-top',bSelf.paddingTop);    
    bSelf.setStyle(bSelf.activeBody,'padding-bottom',1);
  }
  else {
    var downConnector = hOrient == 'left' ?  bSelf.downLeftConnector : bSelf.downRightConnector;
    bSelf.setStyle(bSelf.activeBalloon,'background','url('+downConnector+') top left no-repeat');
    bSelf.setStyle(bSelf.activeBalloon,'padding-bottom',bSelf.paddingBottom);
    bSelf.setStyle(bSelf.activeBalloon,'padding-top',bSelf.paddingConnector);
    bSelf.setStyle(bSelf.activeBody,'background','url('+bSelf.downBalloon+') bottom left no-repeat');
    bSelf.setStyle(bSelf.activeBody,'padding-top',1);
    bSelf.setStyle(bSelf.activeBody,'padding-bottom',bSelf.paddingBottom);
  }
  
  // text boundaries
  bSelf.setStyle(bSelf.activeBody,'padding-left',bSelf.paddingLeft);
  bSelf.setStyle(bSelf.activeBody,'width',bSelf.balloonWidth);
  bSelf.setStyle(bSelf.activeBody,'z-index',10000);
  bSelf.setStyle(bSelf.activeText,'width',bSelf.balloonWidth - (bSelf.paddingLeft + bSelf.paddingRight));
  bSelf.setStyle(bSelf.activeText,'font-size',bSelf.balloonTextSize);

  // persistent balloons need a close control
  if (bSelf.balloonIsStatic) {
    if (vOrient == 'up') {
      bSelf.setStyle(bSelf.activeBody,'padding-top',7);
    }
    else {
      var margin = bSelf.isIE ? -4 : -8;
      bSelf.setStyle(bSelf.activeText,'margin-top',margin);
      bSelf.setStyle(bSelf.activeBody,'padding-top',1);
    }

    helpText = '\
    <a onClick="Balloon.prototype.hideStaticTooltip(1)" title="close this balloon" href=javascript:void(0)\
    style="float:right;font-size:12px;text-decoration:none">\
    Close [X]</a><br>' + helpText;
  }
  else {
    if (vOrient == 'up') {
      bSelf.setStyle(bSelf.activeBody,'padding-top',bSelf.paddingTop);
    }
    else { 
      bSelf.setStyle(bSelf.activeBody,'padding-top',1);
      bSelf.setStyle(bSelf.activeText,'margin-top',0);
    }
  }


  // add the text to the caption layer
  bSelf.activeText.innerHTML = helpText;

  bSelf.showBalloon(vOrient,left,top,pageTop,pageBottom);
}

/////////////////////////////////////////////////////////////////////
// Convenience functions
/////////////////////////////////////////////////////////////////////

Balloon.prototype.getElement = function(id) {
  return document.getElementById(id);
}

// Set the active mouseover coordinates
Balloon.prototype.setActiveCoordinates = function(evt) {
  var el = this.getEventTarget(evt);
  var XY = this.eventXY(evt);

  // is this an image map area?
  var area = el.getAttribute('coords');
  var isImage = el.tagName.match('img', 'i');

  // prefer element vertical bounds if available
  // otherwise, use event's
  this.activeTop  = (!area && !isImage && this.getLoc(el,'y1')) || XY[1];
  this.activeTop -= 10;
  
  this.activeLeft = XY[0] - 10;
  this.activeRight = this.activeLeft + 20;

  this.activeBottom = !area && this.getLoc(el,'y2');
  if (this.activeBottom) this.activeBottom += 10;
  else this.activeBottom = this.activeTop + 20;
}


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


Balloon.prototype.setStyle = function(el,att,val) {
  if (att.match(/left|top|width|height|padding|margin/)) val += 'px'; 
  if (el) YAHOO.util.Dom.setStyle(el,att,val);
}

Balloon.prototype.getLoc = function(el,request) {
  var region = YAHOO.util.Dom.getRegion(el);
  switch(request) {
    case ('y1') : return region.top;
    case ('y2') : return region.bottom;
    case ('x1') : return region.left;
    case ('x2') : return region.right;
    case ('width')  : return (region.right - region.left);
    case ('height') : return (region.bottom - region.top);
    case ('region') : return region; 
 }
}

// We don't know if numbers are overridden with strings
Balloon.prototype.parseIntAll = function() {
  this.balloonWidth     = parseInt(this.balloonWidth);
  this.paddingTop       = parseInt(this.paddingTop);
  this.paddingLeft      = parseInt(this.paddingLeft);
  this.paddingRight     = parseInt(this.paddingRight);
  this.paddingBottom    = parseInt(this.paddingBottom);
  this.paddingConnector = parseInt(this.paddingConnector);
  this.vOffset          = parseInt(this.vOffset);
}

/////////////////////////////////////////////////////////////////////
// Create/append  balloon elements
/////////////////////////////////////////////////////////////////////

Balloon.prototype.createAndAppend = function(id,parent,elTag) {
  var node = this.justCreate(id,elTag);
  this.justAppend(node,parent);
  return node;
}

Balloon.prototype.justCreate = function(id,elTag) {
  var tag = elTag || 'div';
  var node = document.createElement(tag);
  node.setAttribute('id', id);  
  return node;
}

Balloon.prototype.justAppend = function(child,parent) {
  var parentNode = parent || document.body;
  parentNode.appendChild(child);
}


/////////////////////////////////////////////////////////////////////
// Balloon visibility controls
/////////////////////////////////////////////////////////////////////

Balloon.prototype.showBalloon = function(orient,left,top)  {
  YAHOO.util.Dom.setY(this.activeBalloon,999999999);
  this.setStyle(this.activeBalloon,'display','inline');

  if (orient == 'up') {
    var height = this.getLoc(this.activeBalloon,'height');
    top -= height;
  }

  YAHOO.util.Dom.setY(this.activeBalloon,top);
  YAHOO.util.Dom.setX(this.activeBalloon,left);
  balloonIsVisible = true;
  this.showHideSelect();
}

Balloon.prototype.hideTooltip = function() {
  var bSelf = currentBalloonClass;

  if (!bSelf) return;
  currentBalloonClass = null;
  window.clearTimeout(bSelf.timeoutTooltip);
  if (bSelf.balloonIsStatic) return false;
  balloonIsVisible = false;
  if (bSelf.activeBalloon) {
    bSelf.setStyle(bSelf.activeBalloon,'display','none');
  }
}

Balloon.prototype.hideStaticTooltip = function(override) {
  var bSelf = currentBalloonClass;

  currentBalloonClass = null;

  // if reallySticky is defined, the user must
  // click on 'close' to hide static balloons
  // (and open others).  The default is to hide sticky
  // balloons if another showTooltip is fired.
  if (reallySticky && !override) {
    if (bSelf) window.clearTimeout(bSelf.timeoutTooltip);
    return false;
  }

  if (!bSelf) {
    var hideBalloon  = document.getElementById('balloon');
    Balloon.prototype.showHideSelect(1);
    if (hideBalloon) Balloon.prototype.setStyle(hideBalloon,'display','none');
  }
  else if (bSelf.activeBalloon) {
      bSelf.showHideSelect(1);
      bSelf.setStyle(bSelf.activeBalloon,'display','none');
  }	

  balloonIsVisible = false;
}

// this function is meant to be called externally tp clear
// any open balloons
hideAllTooltips = function() {
  var bSelf = currentBalloonClass;
  if (!bSelf) return;
  window.clearTimeout(bSelf.timeoutTooltip);
  if (bSelf.activeBalloon) bSelf.setStyle(bSelf.activeBalloon,'display','none');
  balloonIsVisible = false;
  currentBalloonClass = null;
}

// IE select z-index bug
Balloon.prototype.showHideSelect = function(visible) {
  if (!this.hasSelectBug())   return false;
  if (!visible) {
    var balloonSelects = currentBalloonClass.getElement('text').getElementsByTagName('select');
    var myHash = new Object();
    for (var i=0; i<balloonSelects.length; i++) {
      var id = balloonSelects[i].id || balloonSelects[i].name;
      myHash[id] = 1;
    }
    balloonInvisibleSelects = new Array();
    var allSelects = document.getElementsByTagName('select');
    for (var i=0; i<allSelects.length; i++) {
      var id = allSelects[i].id || allSelects[i].name;
      if (this.isOverlap(allSelects[i])
			 && !myHash[id]) {
	balloonInvisibleSelects.push(allSelects[i]);
	this.setStyle(allSelects[i],'visibility','hidden');
      }
    }
  }
  else {
    for (var i=0; i < balloonInvisibleSelects.length; i++) {
      this.setStyle(balloonInvisibleSelects[i],'visibility','visible');
    }
    balloonInvisibleSelects = undefined;
  }
}

Balloon.prototype.hasSelectBug = function() {
  if (navigator.appVersion.indexOf("MSIE") == -1)
    return false;

  var temp=navigator.appVersion.split("MSIE");
  return parseFloat(temp[1]) < 7;
}

// Try to find overlap 
Balloon.prototype.isOverlap = function(sel) {
  if (!this.activeBalloon) return false;
  var R1 = this.getLoc(this.activeBalloon,'region');
  var R2 = this.getLoc(sel,'region');
  var t1=R1.top,b1=R1.bottom,l1=R1.left,r1=R1.right;
  var t2=R2.top,b2=R2.bottom,l2=R2.left,r2=R2.right;

  if ( ((t2 < b1) && (t2 > t1)) 
      && (((l2 > l1) && (l2 < r1)) || (r2 < r1) && (r2 > l1))) return true;

  if ( ((b2 < b1) && (b2 > t1))
      && (((l2 > l1) && (l2 < r1)) || (r2 < r1) && (r2 > l1))) return true;

  return false;
}


///////////////////////////////////////////////////////
// AJAX widget to fill the balloons
// requires prototype.js
///////////////////////////////////////////////////////
Balloon.prototype.getContents = function(section) {
  // just pass it back if no AJAX handler is required.
  if (!this.helpUrl && !this.activeUrl) return section;

  // inline URL takes precedence
  var url = this.activeUrl || this.helpUrl;

  var pars = this.activeUrl ? '' : 'section='+section;
  var ajax  = new Ajax.Request( url,
                           { method:   'get',
                             asynchronous: false,
		             parameters:  pars,
                             onSuccess: function(t) { currentBalloonClass.updateResult(t.responseText) },
                             onFailure: function(t) { alert('AJAX Failure! '+t.statusText)}});

  // activeUrl is meant to be single-use only
  this.activeUrl = null;

  return this.helpText || section;
}

Balloon.prototype.updateResult = function(text) {
  this.helpText = text;
}


