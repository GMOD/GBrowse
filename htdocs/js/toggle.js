function turnOn (element) {
  element.style.display="inline";
}
function turnOff (element) {
  element.style.display="none";
}

function setVisState (element_name,is_visible) {
  var postData = 'div_visible_'+ element_name + '=' + is_visible;
  new Ajax.Request(document.URL,{method:'post',postBody:postData});
}

function visibility (element_name,is_visible) {
   var element = document.getElementById(element_name);
   var show_control = document.getElementById(element_name + "_show");
   var hide_control = document.getElementById(element_name + "_hide");
   if (is_visible == 1) {
      turnOn(element);
      turnOff(show_control);
      turnOn(hide_control);
   } else {
      turnOff(element);
      turnOff(hide_control);
      turnOn(show_control);
   }
   setVisState(element_name,is_visible);
   return false;
}

function collapse(element_name) {
   var control = document.getElementById(element_name+"_title");
   var icon    = document.getElementById(element_name+"_icon");
   var body    = document.getElementById(element_name+"_image");
   var pad     = document.getElementById(element_name+"_pad");
   var closeit = body.style.display != "none";
   var src     = new String(icon.src);
   if (closeit) {
     icon.src = src.replace(/minus/,'plus');
     body.style.display = 'none';
     pad.style.display = 'inline';
     control.className = 'titlebar_inactive';
   } else {
     icon.src = src.replace(/plus/,'minus');
     body.style.display = 'inline';
     pad.style.display = 'none';
     control.className = 'titlebar';
   }
   var postData = 'track_collapse_'+ element_name + '=' + (closeit ? 1 : 0);
   new Ajax.Request(document.URL,{method:'post',postBody:postData});
   return false;
}


