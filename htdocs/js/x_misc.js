// x_misc.js, X v3.15.3, Cross-Browser.com DHTML Library
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)

function xLinearScale(value, inMin, inMax, outMin, outMax)
{
  var m = (outMax - outMin) / (inMax - inMin);
  var b = outMin - (inMin * m);
  return (m * value + b);
}

function xIntersection(e1, e2, o)
{
  var ix1, iy2, iw, ih, intersect = true;
  var e1x1 = xPageX(e1);
  var e1x2 = e1x1 + xWidth(e1);
  var e1y1 = xPageY(e1);
  var e1y2 = e1y1 + xHeight(e1);
  var e2x1 = xPageX(e2);
  var e2x2 = e2x1 + xWidth(e2);
  var e2y1 = xPageY(e2);
  var e2y2 = e2y1 + xHeight(e2);
  // horizontal
  if (e1x1 <= e2x1) {
    ix1 = e2x1;
    if (e1x2 < e2x1) intersect = false;
    else iw = Math.min(e1x2, e2x2) - e2x1;
  }
  else {
    ix1 = e1x1;
    if (e2x2 < e1x1) intersect = false;
    else iw = Math.min(e1x2, e2x2) - e1x1;
  }
  // vertical
  if (e1y2 >= e2y2) {
    iy2 = e2y2;
    if (e1y1 > e2y2) intersect = false;
    else ih = e2y2 - Math.max(e1y1, e2y1);
  }
  else {
    iy2 = e1y2;
    if (e2y1 > e1y2) intersect = false;
    else ih = e1y2 - Math.max(e1y1, e2y1);
  }
  // intersected rectangle
  if (intersect && typeof(o)=='object') {
    o.x = ix1;
    o.y = iy2 - ih;
    o.w = iw;
    o.h = ih;
  }
  return intersect;
}

// from here down, added in v3.15.3

function xGetURLArguments()
{
  var idx = location.href.indexOf('?');
  var params = new Array();
  if (idx != -1) {
    var pairs = location.href.substring(idx+1, location.href.length).split('&');
    for (var i=0; i<pairs.length; i++) {
      nameVal = pairs[i].split('=');
      params[i] = nameVal[1];
      params[nameVal[0]] = nameVal[1];
    }
  }
  return params;
}

function xPad(str, finalLen, padChar, left)
{
  if (left) { for (var i=str.length; i<finalLen; ++i) str = padChar + str; }
  else { for (var i=str.length; i<finalLen; ++i) str += padChar; }
  return str;
}

function xHex(n, digits, prefix)
{
  var p = '', n = Math.ceil(n);
  if (prefix) p = prefix;
  n = n.toString(16);
  for (var i=0; i < digits - n.length; ++i) {
    p += '0';
  }
  return p + n;
}

function xRad(deg)
{
  return deg * (Math.PI / 180);
}

function xDeg(rad)
{
  return rad * (180 / Math.PI);
}

// Capitalize the first letter of every word in str.
function xCapitalize(str)
{
  var i, c, wd, s='', cap = true;
  
  for (i = 0; i < str.length; ++i) {
    c = str.charAt(i);
    wd = isWordDelim(c);
    if (wd) {
      cap = true;
    }  
    if (cap && !wd) {
      c = c.toUpperCase();
      cap = false;
    }
    s += c;
  }
  return s;

  function isWordDelim(c)
  {
    // add other word delimiters as needed
    // (for example '-' and other punctuation)
    return c == ' ' || c == '\n' || c == '\t';
  }
} // end xCapitalize()

// just ported from CBE to X - not completely tested
function xCardinalPosition(e, cp, margin, outside)
{
  if (typeof(cp)!='string'){window.status='xCardinalPosition error: cp=' + cp + ', id=' + e.id; return;}
  var x=xLeft(e), y=xTop(e), w=xWidth(e), h=xHeight(e);
  var pw,ph,p = xParent(e);
  if (p == document || p.nodeName.toLowerCase() == 'html') {pw = xClientWidth(); ph = xClientHeight();}
  else {pw=xWidth(p); ph=xHeight(p);}
  var sx=xScrollLeft(p), sy=xScrollTop(p);
  var right=sx + pw, bottom=sy + ph;
  var cenLeft=sx + Math.floor((pw-w)/2), cenTop=sy + Math.floor((ph-h)/2);
  if (!margin) margin=0;
  else{
    if (outside) margin=-margin;
    sx +=margin; sy +=margin; right -=margin; bottom -=margin;
  }
  switch (cp.toLowerCase()){
    case 'n': x=cenLeft; if (outside) y=sy - h; else y=sy; break;
    case 'ne': if (outside){x=right; y=sy - h;}else{x=right - w; y=sy;}break;
    case 'e': y=cenTop; if (outside) x=right; else x=right - w; break;
    case 'se': if (outside){x=right; y=bottom;}else{x=right - w; y=bottom - h}break;
    case 's': x=cenLeft; if (outside) y=sy - h; else y=bottom - h; break;
    case 'sw': if (outside){x=sx - w; y=bottom;}else{x=sx; y=bottom - h;}break;
    case 'w': y=cenTop; if (outside) x=sx - w; else x=sx; break;
    case 'nw': if (outside){x=sx - w; y=sy - h;}else{x=sx; y=sy;}break;
    case 'cen': x=cenLeft; y=cenTop; break;
    case 'cenh': x=cenLeft; break;
    case 'cenv': y=cenTop; break;
  }
  var o = new Object();
  o.x = x; o.y = y;
  return o;
}
