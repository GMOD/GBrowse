// x_anim.js, X v3.15.3, Cross-Browser.com DHTML Library
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)

function xEllipse(e, xRadius, yRadius, radiusInc, totalTime, startAngle, stopAngle)
{
  if (!(e=xGetElementById(e))) return;
  if (!e.timeout) e.timeout = 25;
  e.xA = xRadius;
  e.yA = yRadius;
  e.radiusInc = radiusInc;
  e.slideTime = totalTime;
  startAngle *= (Math.PI / 180);
  stopAngle *= (Math.PI / 180);
  var startTime = (startAngle * e.slideTime) / (stopAngle - startAngle);
  e.stopTime = e.slideTime + startTime;
  e.B = (stopAngle - startAngle) / e.slideTime;
  e.xD = xLeft(e) - Math.round(e.xA * Math.cos(e.B * startTime)); // center point
  e.yD = xTop(e) - Math.round(e.yA * Math.sin(e.B * startTime)); 
  e.xTarget = Math.round(e.xA * Math.cos(e.B * e.stopTime) + e.xD); // end point
  e.yTarget = Math.round(e.yA * Math.sin(e.B * e.stopTime) + e.yD); 
  var d = new Date();
  e.C = d.getTime() - startTime;
  if (!e.moving) {e.stop=false; _xEllipse(e);}
}
function _xEllipse(e)
{
  if (!(e=xGetElementById(e))) return;
  var now, t, newY, newX;
  now = new Date();
  t = now.getTime() - e.C;
  if (e.stop) { e.moving = false; }
  else if (t < e.stopTime) {
    setTimeout("_xEllipse('"+e.id+"')", e.timeout);
    if (e.radiusInc) {
      e.xA += e.radiusInc;
      e.yA += e.radiusInc;
    }
    newX = Math.round(e.xA * Math.cos(e.B * t) + e.xD);
    newY = Math.round(e.yA * Math.sin(e.B * t) + e.yD);
    xMoveTo(e, newX, newY);
    e.moving = true;
  }  
  else {
    if (e.radiusInc) {
      e.xTarget = Math.round(e.xA * Math.cos(e.B * e.slideTime) + e.xD);
      e.yTarget = Math.round(e.yA * Math.sin(e.B * e.slideTime) + e.yD); 
    }
    xMoveTo(e, e.xTarget, e.yTarget);
    e.moving = false;
  }  
}

// Animation with Parametric Equations

function xParaEq(e, xExpr, yExpr, totalTime)
{
  if (!(e=xGetElementById(e))) return;
  e.t = 0;
  e.tStep = .008;
  if (!e.timeout) e.timeout = 25;
  e.xExpr = xExpr;
  e.yExpr = yExpr;
  e.slideTime = totalTime;
  var d = new Date( )
  e.C = d.getTime();
  if (!e.moving) {e.stop=false; _xParaEq(e);}
}
function _xParaEq(e)
{
  if (!(e=xGetElementById(e))) return;
  var now = new Date();
  var et = now.getTime() - e.C;
  e.t += e.tStep;
  t = e.t;
  if (e.stop) { e.moving = false; }
  else if (!e.slideTime || et < e.slideTime) {
    setTimeout("_xParaEq('"+e.id+"')", e.timeout);
    var p = xParent(e);
    var centerX = (xWidth(p)/2)-(xWidth(e)/2);
    var centerY = (xHeight(p)/2)-(xHeight(e)/2);
    e.xTarget = Math.round((eval(e.xExpr) * centerX) + centerX) + xScrollLeft(p);
    e.yTarget = Math.round((eval(e.yExpr) * centerY) + centerY) + xScrollTop(p);
    xMoveTo(e, e.xTarget, e.yTarget);
    e.moving = true;
  }  
  else {
    e.moving = false;
  }  
}
