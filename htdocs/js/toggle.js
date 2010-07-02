/*** Wherever listed below "node" doesn't refer to the actual DOM node, but the node as it appears in the collapsable track hierarchy ***/

// setVisState sends the visibility data to the session, so that it is retained through page loads.
function setVisState (element_name,is_visible) {
  var visibility = is_visible ? 'show' : 'hide';
  var postData   = 'action=show_hide_section;'+visibility+'='+element_name;
  new Ajax.Request(document.URL,{method:'post',postBody:postData});
}

// checkLists checks to see if any of the track groups are collapsed and require the listing to be inserted.
function checkLists() {
  var sections = getNode(":groups");
  for(var a = 0; a < sections.length; a++) {
    var section_name = getName(sections[a]);
    if(sections[a].select("div.el_visible")[0].visible() == false) {
      list(section_name);
      sections[a].select("span[id$=_list]")[0].show();
    }
  }
}

// getNode returns the box (or boxes) that holds the section (or sections) with the specified title.
function getNode(node_name) {    
  var nodes = new Array;
  if (!node_name) node_name = ""; // Prevent undefined errors.
  switch(node_name.toLowerCase()) {
  
    // Return all group nodes.
    case "all groups":
    case ":groups":
    case ":group":
      var all_groups =  $("track_page").select("div.el_visible");
      for (var j = 0; j < all_groups.length; j++) {
        if (all_groups[j].readAttribute("id").search("_panel") == -1)
          nodes.push(all_groups[j].up());
      }
      break;

    // Return all track nodes.
    case "all tracks":
    case ":tracks":
    case ":track":
      var all_cells = $("track_page").select("div.el_visible span td");
      for (var h = 0; h < all_cells.length; h++) 
        if (all_cells[h].select('input[type="checkbox"]').length > 0)
          nodes.push(all_cells[h]);
      break;
    
    // Return all nodes by combining all groups and all tracks.
    case "all":
    case "*":
    case "":
    case ":all":
      nodes = getNode(":groups").concat(getNode(":tracks"));;
      break;
    
    // If we're just trying to find one specific node, the default case chooses the individual node (or nodes, if there's multiple with the same name).
    default:
      nodes = $("track_page").select("div[id=" + node_name.strip() + "_section]");
      if (nodes.length == 0)
        nodes = $("track_page").select("form#trackform div[id$='" + node_name.strip() + "_section'][class=el_visible]");
      
      // We've selected the name, but the containing cell is the parent.
      for (k = 0; k < nodes.length; k++)
        nodes[k] = nodes[k].up();
      
      // We want to avoid this type of selection if possible, it's the slowest method - it selects every possible track.
      if (nodes.length == 0) {
        var all_tracks = $$("div.el_visible span td");
        if (all_tracks.length > 0) {
          for (var b = 0; b < all_tracks.length; b++) {
            if (all_tracks[b].select('input[type="checkbox"]').length > 0) {
              // Some of the cell names are wrapped within anchor tags, extract the text in either case.
              if (all_tracks[b].down("a") != undefined) {
                if (node_name.toLowerCase().strip() == all_tracks[b].down("a").firstChild.nodeValue.toLowerCase().strip())
                  nodes.push(all_tracks[b]);
              } else {
                if (node_name.toLowerCase().strip() == all_tracks[b].down("input").nextSibling.nodeValue.toLowerCase().strip())
                  nodes.push(all_tracks[b]);
              }
            }
          }
        }
      }
    break;
  }
  
  // Return whatever result we got.
  if (nodes.length > 0) {
    if (nodes.length == 1)  // Avoids returning a one-element array.
      return nodes[0];
    else
      return nodes;
  }
}

// getName takes a node (like the one returned from getNode) and returns the name as it appears in the GUI.
function getName(node) {
  if (node.length) {  // If node is an array of nodes
    var nodes = new Array;
    for (q in node) {
      nodes[q] = getName(node[q]);
    }
    return nodes;
  }
    
  if (nodeType(node) == "group")
    return node.select("span[class=tctl][id$=_title]")[0].down().innerHTML.strip(); // The section's name will always be the bold text inside the first title span found.
  else if (nodeType(node) == "track") {
    // Some of the cell names are wrapped within anchor tags, extract the text in either case.
    if (node.down("a") != undefined)
      return node.down("a").innerHTML.strip();
    else
      return node.down("input").nextSibling.nodeValue.strip();
  }
}

// getChildren returns any child nodes of the current node
function getChildren(node) {
  // We can take a section name or the actual section object; if it's the former, get the object.
  if (typeof node == "string")
    node = getNode(node);
    
  var node_contains = nodeContains(node);
  
  if (nodeType(node) == "track")
    return 0;
  
  // If you're looking for groups, return all the group sections. If not, 
  if (node_contains == "group") {
    return node.down("div.el_visible").down("div").childElements();
  } else {
    // Each track name is a cell in the table within the section with a checkbox inside of it. Find the name, push it to names[].
    var possible_nodes = node.select("span td");
    var nodes = new Array;
    for (var c = 0; c < possible_nodes.length; c++) {      
      // Make sure the selected node isn't blank
      if (!(possible_nodes[c].select('input[type="checkbox"]').length == 0))
        nodes.push(possible_nodes[c]);
    }
    return nodes;
  }
}

// nodeType returns whether the selected node (section or name) is a group, track or panel node.
function nodeType(node) {
  // We can take a section name or the actual section object; if it's the former, get the object.
  if (typeof node == "string")
    node = getNode(node);
  
  // If there are any other collapsable groups below the current one, it is a group list
  if (node.tagName != "TD")
    return "group";
  if (node.select(".trackform").length > 0)
    return "panel";
  else
    return "track";
}

// nodeContains returns whether the selected node (section or name) is a group of tracks or groups.
function nodeContains(node) {
  // We can take a section name or the actual section object; if it's the former, get the object.
  if (typeof node == "string")
    node = getNode(node);
  
  // If the node contains, within its content section, any titles for other content sections it contains groups.
  var children = node.down("div.el_visible span.tctl");
  if (children == undefined)
    if (node.down("td") == undefined)
      return false;
    else
      return "track";
  else
    return "group";
}

// list mines the track groups box for possible names and creates a shorter listing of them when the section is hidden.
function list(section) {
  var truncate_length = 100;  // truncate_length is the maximum number of names we'll list. Anything more gets a "..."
  var list_type = nodeContains(section);
  var node = getNode(section);
  var list = node.select("span[id$=_list]")[0];
  var text_length = 0;
  var overflow = false;

  list.update("");
  var list_text = "&nbsp;(";
  
  // Each track name is a cell in the table within the section with a checkbox inside of it. Find the name, push it to names[].
  var children = getChildren(section)
  var items = new Array;
  for (var d = 0; d < children.length; d++) {
    if (text_length < truncate_length) {
      var item = "";
      // If any checkbox in the group is on, the group is "on"
      var group_on = ((list_type == "group") && (children[d].select('input[type="checkbox"][name=l]:checked').length != 0)) ? true : false;

      // Create the item for the list, including the class.
      if (((list_type == "track") && (children[d].select('input[type="checkbox"][name=l]:checked').length != 0)) || ((list_type == "group") && (group_on == true)))
        item += "<span class=\"list_show\">";
      else
        item += "<span class=\"list_hide\">";
      
      // Get the item name, add the length of that text to the character count. If we're over the count, truncate the name.
      var item_name = getName(children[d]).strip();
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
      
      item += item_name;
      item += "</span>";
      items.push(item);
    }
  }
  
  // Loop through the list, adding the name of each track now hidden.
  for (var f = 0; f < items.length; f++) {
    list_text += items[f];
    if (f < (items.length - 1))
      list_text += ", ";
  }
  
  if (overflow == true)
      list_text += "...";
  list_text += ")";
  
  // Append the HTML into the track list.
  list.update(list_text);
}


// visibility toggles the visibility (on or off) of the selected element.
function visibility (element_name,is_visible) {
   var break_element = $(element_name + "_break");
   
   // If the element should be visible, show it and hide the "show" control. If not, show the "show" control, hide the element and make the track listing.
   if (is_visible == 1) {
      if (element_name.search("_section") != -1)
        $(element_name + "_list").hide();
      $(element_name).show();
      $(element_name + "_show").hide();
      $(element_name + "_hide").show();
      if (break_element != null)
  	    break_element.hide();
   } else {
      if (element_name.search("_section") != -1) {
        list(element_name.substring(0, (element_name.length - "_section".length))); //The substring trims "_section" from the end of a list.
        $(element_name + "_list").show();
      }
      $(element_name).hide();
      $(element_name + "_hide").hide();
      $(element_name + "_show").show();
      if (break_element != null)
    	  break_element.show();
   }
   
   // Send the visibility data to the session vars.
   setVisState(element_name,is_visible);
   return false;
}


// Collapse toggles the temporary visibility of a panel in the main display.
function collapse(element_name) {
   var src     = new String($(element_name+"_icon").src);
   if (body.style.display != "none") {
     $(element_name+"_icon").src = src.replace(/minus/,'plus');
     $(element_name+"_image").style.display = 'none';
     $(element_name+"_pad").style.display = 'inline';
     $(element_name+"_title").className = 'titlebar_inactive';
   } else {
     $(element_name+"_icon").src = src.replace(/plus/,'minus');
     $(element_name+"_image").style.display = 'inline';
     $(element_name+"_pad").style.display = 'none';
     $(element_name+"_title").className = 'titlebar';
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
