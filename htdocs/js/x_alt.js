// x_alt.js, X v3.15.3, Cross-Browser.com DHTML Library
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)


// Alternatives to xSlideTo()
function xSlideX(e,iX,fInc,iterating) { // experimental
  if (!(e=xGetElementById(e))) return;
  if (!e.slideXActive) e.slideXTarget = iX;
  else if (!iterating) {e.slideXTarget = iX; return;}
  var dX, X=xLeft(e);
  e.slideXActive = true;
  if (fInc < 1) {
    dX = fInc * Math.abs(Math.abs(X) - Math.abs(e.slideXTarget));
    if (dX < 1) dX = 1;
  }
  else dX = fInc;
  if (X < e.slideXTarget) {
    if (X + dX <= e.slideXTarget) X += dX;
    else X = e.slideXTarget;
  }
  else if (X > e.slideXTarget) {
    if (X - dX >= e.slideXTarget) X -= dX;
    else X = e.slideXTarget;
  }
  else {e.slideXActive = false; return;}
  xLeft(e, X);
  setTimeout("xSlideX('"+e.id+"',"+e.slideXTarget+","+fInc+","+true+")",25);
}
function xSlideY(e,iY,fInc,iterating) { // experimental
  if (!(e=xGetElementById(e))) return;
  if (!e.slideYActive) e.slideYTarget = iY;
  else if (!iterating) {e.slideYTarget = iY; return;}
  var dY, Y=xTop(e);
  e.slideYActive = true;
  if (fInc < 1) {
    dY = fInc * Math.abs(Math.abs(Y) - Math.abs(e.slideYTarget));
    if (dY < 1) dY = 1;
  }
  else dY = fInc;
  if (Y < e.slideYTarget) {
    if (Y + dY <= e.slideYTarget) Y += dY;
    else Y = e.slideYTarget;
  }
  else if (Y > e.slideYTarget) {
    if (Y - dY >= e.slideYTarget) Y -= dY;
    else Y = e.slideYTarget;
  }
  else {e.slideYActive = false; return;}
  xTop(e, Y);
  setTimeout("xSlideY('"+e.id+"',"+e.slideYTarget+","+fInc+","+true+")",25);
}

// alternative to xHasPoint()
function xHasPoint(ele, iLeft, iTop, iClpT, iClpR, iClpB, iClpL) {
  if (arguments.length==3){iClpT=iClpR=iClpB=iClpL=0;}
  else if (arguments.length==4){iClpR=iClpB=iClpL=iClpT;}
  else if (arguments.length==5){iClpL=iClpR; iClpB=iClpT;}
  var thisX = xPageX(ele), thisY = xPageY(ele);
  return (iLeft >= thisX + iClpL && iLeft <= thisX + xWidth(ele) - iClpR &&
          iTop >=thisY + iClpT && iTop <= thisY + xHeight(ele) - iClpB );
}

// xScrollXxxx functions without element support
function xScrollLeft() {
  var offset=0;
  if(xDef(window.pageXOffset)) offset=window.pageXOffset;
  else if(document.documentElement && document.documentElement.scrollLeft) offset=document.documentElement.scrollLeft;
  else if(document.body && xDef(document.body.scrollLeft)) offset=document.body.scrollLeft;
  return offset;
}
function xScrollTop() {
  var offset=0;
  if(xDef(window.pageYOffset)) offset=window.pageYOffset;
  else if(document.documentElement && document.documentElement.scrollTop) offset=document.documentElement.scrollTop;
  else if(document.body && xDef(document.body.scrollTop)) offset=document.body.scrollTop;
  return offset;
}
