// x_popup.js, X v3.15.3, Cross-Browser.com DHTML Library
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)

// sTmrType: 'timeout' or 'interval'
// uTimeout: time in ms
// sPos1: on show, slides from this cp
// sPos2: on show, slides to this cp
// sPos3: on hide, slides to this cp
// sStyle: applied to the iframe
// sId: applied to the iframe
// sUrl: gets loaded into the newly created iframe
// cp: 'n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw', 'cen', 'cenh' or 'cenv'

function xPopup(sTmrType, uTimeout, sPos1, sPos2, sPos3, sStyle, sId, sUrl)
{
  if (document.getElementById && document.createElement &&
      document.body && document.body.appendChild)
  { 
    // create popup element
    //var e = document.createElement('DIV');
    var e = document.createElement('IFRAME');
    this.ele = e;
    e.id = sId;
    e.style.position = 'absolute';
    e.className = sStyle;
    //e.innerHTML = sHtml;
    e.src = sUrl;
    document.body.appendChild(e);
    xShow(e);
    this.tmr = xTimer.set(sTmrType, this, sTmrType, uTimeout);
    // init
    this.open = false;
    this.margin = 10;
    this.pos1 = sPos1;
    this.pos2 = sPos2;
    this.pos3 = sPos3;
    this.slideTime = 500; // slide time in ms
    this.interval();
  } 
} // end xPopup
// methods
xPopup.prototype.show = function()
{
  this.interval();
};
xPopup.prototype.hide = function()
{
  this.timeout();
};
// timer event listeners
xPopup.prototype.timeout = function() // hide popup
{
  if (this.open) {
    var e = this.ele;
    var pos = xCardinalPosition(e, this.pos3, this.margin, true);
    xSlideTo(e, pos.x, pos.y, this.slideTime);
    setTimeout("xHide('" + e.id + "')", this.slideTime);
    this.open = false;
  }
};
xPopup.prototype.interval = function() // size, position and show popup
{
  if (!this.open) {
    var e = this.ele;
    var pos = xCardinalPosition(e, this.pos1, this.margin, true);
    xMoveTo(e, pos.x, pos.y);
    xShow(e);
    pos = xCardinalPosition(e, this.pos2, this.margin, false);
    xSlideTo(e, pos.x, pos.y, this.slideTime);
    this.open = true;
  }
};
