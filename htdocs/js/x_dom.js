// x_dom.js, X v3.15.3, Cross-Browser.com DHTML Library
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)

function xWalkTree(oNode, fnVisit)
{
  if (oNode) {
    if (oNode.nodeType == 1) {fnVisit(oNode);}
    for (var c = oNode.firstChild; c; c = c.nextSibling) {
      xWalkTree(c, fnVisit);
    }
  }
}
function xGetComputedStyle(oEle, sProp, bInt)
{
  var s, p = 'undefined';
  if(document.defaultView && document.defaultView.getComputedStyle){
    s = document.defaultView.getComputedStyle(oEle,'');
    if (s) p = s.getPropertyValue(sProp);
  }
  else if(oEle.currentStyle) {
    // convert css property name to object property name for IE
    var a = sProp.split('-');
    sProp = a[0];
    for (var i=1; i<a.length; ++i) {
      c = a[i].charAt(0);
      sProp += a[i].replace(c, c.toUpperCase());
    }   
    p = oEle.currentStyle[sProp];
  }
  return bInt ? (parseInt(p) || 0) : p;
}
function xGetElementsByClassName(clsName, parentEle, tagName, fn)
{
  var found = new Array();
  var re = new RegExp('\\b'+clsName+'\\b', 'i');
  var list = xGetElementsByTagName(tagName, parentEle);
  for (var i = 0; i < list.length; ++i) {
    if (list[i].className.search(re) != -1) {
      found[found.length] = list[i];
      if (fn) fn(list[i]);
    }
  }
  return found;
}
function xGetElementsByTagName(tagName, parentEle)
{
  var list = null;
  tagName = tagName || '*';
  parentEle = parentEle || document;
  if (xIE4 || xIE5) {
    if (tagName == '*') list = parentEle.all;
    else list = parentEle.all.tags(tagName);
  }
  else if (parentEle.getElementsByTagName) list = parentEle.getElementsByTagName(tagName);
  return list || new Array();
}
function xGetElementsByAttribute(sTag, sAtt, sRE, fn)
{
  var a, list, found = new Array(), re = new RegExp(sRE, 'i');
  list = xGetElementsByTagName(sTag);
  for (var i = 0; i < list.length; ++i) {
    a = list[i].getAttribute(sAtt);
    if (!a) {a = list[i][sAtt];}
    if (typeof(a)=='string' && a.search(re) != -1) {
      found[found.length] = list[i];
      if (fn) fn(list[i]);
    }
  }
  return found;
}
function xCreateElement(sTag) {
  if (document.createElement) return document.createElement(sTag);
  else return null;
}
function xAppendChild(oParent, oChild) {
  if (oParent.appendChild) return oParent.appendChild(oChild);
  else return null;
}
