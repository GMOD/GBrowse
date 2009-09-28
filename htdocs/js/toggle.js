function turnOn (element) {
  element.style.display="inline";
}
function turnOff (element) {
  element.style.display="none";
}

function setVisState (element_name,is_visible) {
  var visibility = is_visible ? 'show' : 'hide';
  var postData   = 'action=show_hide_section;'+visibility+'='+element_name;
  new Ajax.Request(document.URL,{method:'post',postBody:postData});
}

function visibility (element_name,is_visible) {
   var element       = document.getElementById(element_name);
   var show_control  = document.getElementById(element_name + "_show");
   var hide_control  = document.getElementById(element_name + "_hide");
   var title_control = document.getElementById(element_name+"_title");
   var break_element = document.getElementById(element_name + "_break");
   if (is_visible == 1) {
      turnOn(element);
      turnOff(show_control);
      turnOn(hide_control);
      if (break_element != null)
	  turnOff(break_element);
   } else {
      turnOff(element);
      turnOff(hide_control);
      turnOn(show_control);
      if (break_element != null)
	  break_element.style.display='block';
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
   
   var direction = closeit ? 'collapse' : 'open';
   var postData  = 'action=open_collapse_track;'+direction+'='+escape(element_name);
   new Ajax.Request(document.URL,{method:'post',postBody:postData});
   return false;
}

function enable_keypos (checkbox) {
  var checked = checkbox.checked;
  var ks      = document.getElementsByName('ks');
  for (var i=0;i<ks.length;i++) {ks[i].disabled= checked}
  document.getElementById('ks_label').style.color=checked ? 'lightgray' : 'black';
}
