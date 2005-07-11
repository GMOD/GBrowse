function turnOn (a) {
  a.style.display="block";
}
function turnOff (a) {
  a.style.display="none";
}

function visibility (a,state,cookie_name,cookie_expires) {
   var element = document.getElementById(a);
   var show_control = document.getElementById(a + "_show");
   var hide_control = document.getElementById(a + "_hide");
   if (state == "on") {
      turnOn(element);
      turnOff(show_control);
      turnOn(hide_control);
   } else if (state == "off"){
      turnOff(element);
      turnOff(hide_control);
      turnOn(show_control);
   }
   setVisState(a,state,cookie_name,cookie_expires);
   return false;
}

function setVisState (a,state,cookie_name,cookie_expires) {
   var el_index       = a.substring(1);
   var cookie_value   = xGetCookie(cookie_name);
   if (!cookie_value) { cookie_value = 0xFFFFFF; }
   if (state == "on") { cookie_value |= (1 << el_index) }
                 else { cookie_value &= ~(1 << el_index) }
   xSetCookie(cookie_name,cookie_value,cookie_expires);
}

function getVisState (a,cookie_name) {
   var el_index       = a.id.substring(1);
   var cookie_value   = xGetCookie(cookie_name);
   if (!cookie_value) { cookie_value = 0xFFFFFF; }
   return (cookie_value &= (1 << el_index)) == 0 ? 'off' : 'on';
}

// The x{Set,Get}Cookie functions are derived from cross-browser.com
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)
function xSetCookie(name, value, expire)
{
  var path = location.pathname;
  var text = name + "=" + escape(value) +
             (!expire ? "" : "; expires=" + expire) +
             "; path=" + path;
  document.cookie = text;
}

function xGetCookie(name)
{
  var value=null, search=name+"=";
  if (document.cookie.length > 0) {
    var offset = document.cookie.indexOf(search);
    if (offset != -1) {
      offset += search.length;
      var end = document.cookie.indexOf(";", offset);
      if (end == -1) end = document.cookie.length;
      value = unescape(document.cookie.substring(offset, end));
    }
  }
  return value;
}

function startPage() {
 var spans=document.getElementsByTagName("div");
 for (var i=0; i < spans.length; i++){
    if (spans[i].className=="ctl_hidden" || spans[i].className=="el_hidden" ) {
           spans[i].style.display = "none";
    }
 }
}
