// x_event.js, X v3.15.3, Cross-Browser.com DHTML Library
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)

function xAddEventListener(e,eventType,eventListener,useCapture)
{
  if(!(e=xGetElementById(e))) return;
  eventType=eventType.toLowerCase();
  if((!xIE4Up && !xOp7 /* && !xMoz */) && e==window) {
    if(eventType=='resize') { window.xPCW=xClientWidth(); window.xPCH=xClientHeight(); window.xREL=eventListener; xResizeEvent(); return; }
    if(eventType=='scroll') { window.xPSL=xScrollLeft(); window.xPST=xScrollTop(); window.xSEL=eventListener; xScrollEvent(); return; }
  }
  var eh='e.on'+eventType+'=eventListener';
  if(e.addEventListener) e.addEventListener(eventType,eventListener,useCapture);
  else if(e.attachEvent) e.attachEvent('on'+eventType,eventListener);
  else eval(eh);
}

function xRemoveEventListener(e,eventType,eventListener,useCapture)
{
  if(!(e=xGetElementById(e))) return;
  eventType=eventType.toLowerCase();
  if((!xIE4Up && !xOp7 /* && !xMoz */) && e==window) {
    if(eventType=='resize') { window.xREL=null; return; }
    if(eventType=='scroll') { window.xSEL=null; return; }
  }
  var eh='e.on'+eventType+'=null';
  if(e.removeEventListener) e.removeEventListener(eventType,eventListener,useCapture);
  else if(e.detachEvent) e.detachEvent('on'+eventType,eventListener);
  else eval(eh);
}

function xEvent(evt) // object prototype
{
  this.type = ''; this.target = null; this.relatedTarget = null;
  this.pageX = 0; this.pageY = 0; this.keyCode = 0;
  this.offsetX = 0; this.offsetY = 0;
  var e = evt || window.event;
  if(!e) return;
  if(e.type) this.type = e.type;
  if(e.target) this.target = e.target;
  else if(e.srcElement) this.target = e.srcElement;
  if (e.relatedTarget) this.relatedTarget = e.relatedTarget;
  else if (xIE4Up) {
    if (e.type == 'mouseover') this.relatedTarget = e.fromElement;
    else if (e.type == 'mouseout') this.relatedTarget = e.toElement;
  }
  if(xOp5or6) { this.pageX = e.clientX; this.pageY = e.clientY; }
  else if(xDef(e.pageX,e.pageY)) { this.pageX = e.pageX; this.pageY = e.pageY; }
  else if(xDef(e.clientX,e.clientY)) { this.pageX = e.clientX + xScrollLeft(); this.pageY = e.clientY + xScrollTop(); }

  /* I need someone with IE/Mac to test this section
     as compared to the following commented-out section.
  */
  if(xDef(e.offsetX,e.offsetY)) {
    this.offsetX = e.offsetX;
    this.offsetY = e.offsetY;
    if (xIE4Up && xMac) {
      this.offsetX += xScrollLeft();
      this.offsetY += xScrollTop();
    }
  }
  else if (xDef(e.layerX,e.layerY)) {
    this.offsetX = e.layerX;
    this.offsetY = e.layerY;
  }
  else {
    this.offsetX = this.pageX - xPageX(this.target);
    this.offsetY = this.pageY - xPageY(this.target);
  }

/*
  if (xDef(e.offsetX,e.offsetY) && !(xIE4Up && xMac)) {
    this.offsetX = e.offsetX;
    this.offsetY = e.offsetY;
  }
  else if (xDef(e.layerX,e.layerY)) {
    this.offsetX = e.layerX;
    this.offsetY = e.layerY;
  }
  else {
    this.offsetX = this.pageX - xPageX(this.target);
    this.offsetY = this.pageY - xPageY(this.target);
  }
*/

  if (e.keyCode) { this.keyCode = e.keyCode; } // for moz/fb, if keyCode==0 use which
  else if (xDef(e.which) && e.type.indexOf('key')!=-1) { this.keyCode = e.which; }
}

function xResizeEvent()
{
  if (window.xREL) setTimeout('xResizeEvent()', 250);
  var cw = xClientWidth(), ch = xClientHeight();
  if (window.xPCW != cw || window.xPCH != ch) { window.xPCW = cw; window.xPCH = ch; if (window.xREL) window.xREL(); }
}
function xScrollEvent()
{
  if (window.xSEL) setTimeout('xScrollEvent()', 250);
  var sl = xScrollLeft(), st = xScrollTop();
  if (window.xPSL != sl || window.xPST != st) { window.xPSL = sl; window.xPST = st; if (window.xSEL) window.xSEL(); }
}
function xStopPropagation(evt)
{
  if (evt && evt.stopPropagation) evt.stopPropagation();
  else if (window.event) window.event.cancelBubble = true;
}
function xPreventDefault(evt)
{
  if (evt && evt.preventDefault) evt.preventDefault();
  else if (window.event) window.event.returnValue = false;
}
