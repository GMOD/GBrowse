// setVisState sends the visibility state to the server.
function setVisState (element_name,is_visible) {
  var visibility = is_visible ? 'show' : 'hide';
  var postData   = 'action=show_hide_section;'+visibility+'='+element_name;
  new Ajax.Request(document.URL,{method:'post',postBody:postData});
}

// checkSummaries makes sure any collapsed nodes have their summaries visible upon page load.
function checkSummaries() {
  var tf = $('trackform');
  if (tf==null) return;

  var sections = tf.select("div.searchbody div.el_visible");
  for(j = 0; j < sections.length; j++) {
    if(sections[j].visible() == false)
      summarizeTracks(sections[j]);
      
    var track_checkboxes = sections[j].select("input[type=checkbox]:not([id$=_a]):not([id$=_n])");
    for (var f = 0; f < track_checkboxes.length; f++)
      track_checkboxes[f].observe("change", checkAllToggles);
  }
}

// Update List - Goes through the listing node and marks any "turned on" nodes.
function updateList(node) {
  var children = getChildren(node);
  var list_items = getList(node).select("span");
  for (var a = 0; a < list_items.length; a++) {
    if (children[a].select('input[type=checkbox]:checked').length != 0) {
      list_items[a].removeClassName("hide").addClassName("show");
    } else {
      list_items[a].removeClassName("show").addClassName("hide");
    }
  }
}

// Get List - Returns (or creates, if missing) the list holder box in the appropriate place.
function getList(node) {
  var list = node.up().down("span.list");
  if (typeof list == "undefined") {
    list = new Element("span", {"class": "list"});
    node.up().down("i.nojs").insert({after: list});
  }
  return list;
}

// Check "All" Toggles - turns off any "All On" or "All Off" checkboxes which are checked.
function checkAllToggles() {
  var node = this.up("div.el_visible");
  var all_on = node.up().down("input[type=checkbox][id$=_a]");
  var all_off = node.up().down("input[type=checkbox][id$=_n]");

  all_off.checked = (node.down("input[type=checkbox]:checked"))? false : true;
  all_on.checked = (node.down("input[type=checkbox]:not(:checked)"))? false : true;
}

// summarizeTracks mines the track options box for possible tracks and creates a shorter listing of them when the section is hidden.
function summarizeTracks(node) {
  var children = getChildren(node);
  var list_text = listText(children);
  
  // Append the HTML into the track list.
  var list = getList(node);
  list.update(list_text);
  list.show();
}

// Determines whether a node should be "on" in the listing.
function isOn(node) {
    return (node.select('input[type="checkbox"][name=l]:checked').length > 0)? true : false;
}

// listText creates the listing text from the elements given.
function listText(elements) {
  var truncate_length = 150;  // truncate_length is the maximum number of names we'll list. Anything more gets a "..."
  var item_wrapper = "span";
  
  var text_length = 0;
  var overflow = false;
  var items = new Array;
  
  var list_text = "&nbsp;(";
 
  // Each track name is a cell in the table within the section with a checkbox inside of it. Find the name, push it to tracks[].
  for (var i = 0; i < elements.length; i++){
    if (text_length < truncate_length) {
      // Create the item for the list, including the class.
      var item_name = getName(elements[i]);
      var item = "<" + item_wrapper + " class =\"" + (isOn(elements[i])? "show" : "hide") + "\">";

      //Add the length of the name to the character count. If we're over the count, truncate the name.
      text_length += item_name.length;
      if (text_length > truncate_length) {
        item_name = item_name.substring(0, text_length - truncate_length);

        // If the truncated name ends in a non-letter character (which would look awkward with an ellipsis after it), truncate more until you hit a letter.
        var match_string = new RegExp(/[A-Za-z0-9]/);
        while (item_name.slice(-1).match(match_string) == null) {
          item_name = item_name.slice(0, -1);
        }
        overflow = true;
      }
      
      item += item_name + "</span>";
      items.push(item);
    } else {
        break;
    }
  }
  
  // Loop through the list, adding the name of each track now hidden.
  for (var c = 0; c < items.length; c++) {
    list_text += items[c];
    if (c < (items.length - 1))
      list_text += ", ";
  }

  if (overflow == true)
    list_text += "...";
  list_text += ")";
  
  return list_text;
}

// containsGroup checks whether a node contains groups (and should look for those when finding children).
function containsGroups(node) {
  return (typeof node.down("div.el_visible") != "undefined")? true : false;
}

// isGroup checks whether a node is a group node or a track node.
function isGroup(node) {
  return (node.nodeName == "DIV")? true : false;
}

// getChildren gets the children nodes of a group.
function getChildren(node) {
  var has_groups = containsGroups(node);
                                                              // This just applies down("div.el_visible") on the childElements array.
  var children = (has_groups == true)? node.down().childElements().collect( function(child) { return child.down("div.el_visible") } ) : node.select('span td');
  var nodes = new Array;
  // Make sure they're valid groups, not just empty table cells...
  for (var i = 0; i < children.length; i++) {
    if (((has_groups == true) && children[i].match("div.el_visible")) || ((has_groups == false) && (children[i].select("input[type=checkbox][name=l]").length > 0)))
      nodes.push(children[i]);
  }
  return nodes;
}


// getName returns the name of a node, as displayed in the control.
function getName(node) {
  if (isGroup(node)) {
    return (node.previous("div.ctl_visible"))? node.previous("div.ctl_visible").down("span.tctl > b").innerHTML : node.previous("div").down("div.ctl_visible").down("span.tctl > b").innerHTML;
  } else {
    //Some of the cell names are wrapped within anchor tags, test if it is or not.
    if (node.down("a"))
      var track_name = node.down("a").firstChild.nodeValue.stripTags();
    else
      var track_name = node.down("input").nextSibling.nodeValue.stripTags();
    return track_name.replace(/^\s+|\s+$/g,"");;
  }
}

// visibility toggles a node as open or closed.
function visibility (element_name,is_visible) {
   var element       = $(element_name);
   var show_control  = $(element_name + "_show");
   var hide_control  = $(element_name + "_hide");
   var title_control = $(element_name + "_title");
   var break_element = $(element_name + "_break");
   var track_list    = $(element_name).up().down("span.list");
   if (is_visible == 1) {
      element.show();
      show_control.hide();
      hide_control.show();
      if (track_list != null)
          track_list.hide();
      if (break_element != null)
        break_element.hide();
   } else {
      if (element_name.search("_section") != -1)
        summarizeTracks(element);
      element.hide();
      hide_control.hide();
      show_control.show();
      if (track_list != null)
        track_list.show();
      if (break_element != null)
        break_element.show();
   }
   setVisState(element_name, is_visible);
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
   updateRuler();
   return false;
}

function enable_keypos (checkbox) {
  var checked = checkbox.checked;
  var ks      = document.getElementsByName('ks');
  for (var i=0;i<ks.length;i++) {ks[i].disabled= checked}
  document.getElementById('ks_label').style.color=checked ? 'lightgray' : 'black';
}
