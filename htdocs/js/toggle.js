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

function checkSummaries() {
  var sections = $('trackform').select("div.searchbody > div");
  for(j = 0; j < sections.length; j++) {
    var section_name = sections[j].select("div.el_visible > div > span")[0].getAttribute("id");
    if(sections[j].select("div.el_visible")[0].visible() == false) {
      summarizeTracks(section_name);
    }
  }
}

// summarizeTracks mines the track options box for possible tracks and creates a shorter listing of them when the section is hidden.
function summarizeTracks(section_name) {

	   // This is the maximum number of tracks we'll list. Anything more gets a "..."
  var max_track_number = 5;
  
  // If the list is filled, clear it; if not, create it.
  if ($(section_name + '_tracklist'))
    $(section_name + '_tracklist').update("");
  else
    $(section_name + '_show').insert("&nbsp;<i id='" + section_name + "_tracklist'></i>");
  
  var track_list = "(";
 
  // Each track name is a cell in the table within the section with a checkbox inside of it. Find the name, push it to tracks[].
  var cells = $(section_name).select('span td');
  var tracks = new Array;
  for (i = 0; i < cells.length; i++){
    if (cells[i].select('input[type="checkbox"]').length != 0) {
      //Some of the cell names are wrapped within anchor tags, test if it is or not.
      if (cells[i].firstChild.nextSibling.nodeName == "A")
        var track_name = cells[i].firstChild.nextSibling.firstChild.nodeValue.stripTags();
      else
        var track_name = cells[i].firstChild.nextSibling.nodeValue.stripTags();
      tracks.push(track_name);
    }
  }
  
  // If the number of tracks isn't more than the maximum, change the max to the number of tracks.
  if (tracks.length < max_track_number)
    var num_tracks = tracks.length;
  else
    var num_tracks = max_track_number;
  
  // Loop through the list, adding the name of each track now hidden.
  for (i = 0; i < num_tracks; i++) {
    track_list += tracks[i];
    if (i < (num_tracks - 1))
      track_list += ", ";
  }
  
  //If we need, add a "..." to indicate there's more content.
  if (num_tracks < tracks.length)
    track_list += "...";
  track_list += ")";
  
  // Append the HTML into the track list.
  $(section_name + '_tracklist').update(track_list);
}

function visibility (element_name,is_visible) {
   var element       = document.getElementById(element_name);
   var show_control  = document.getElementById(element_name + "_show");
   var hide_control  = document.getElementById(element_name + "_hide");
   var title_control = document.getElementById(element_name + "_title");
   var break_element = document.getElementById(element_name + "_break");
   if (is_visible == 1) {
      turnOn(element);
      turnOff(show_control);
      turnOn(hide_control);
      if (break_element != null)
	  turnOff(break_element);
   } else {
      if (element_name.search("_section") != -1)
        summarizeTracks(element_name);
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
