var track_listing_id        = 'tracks_panel'; 

// setVisState sends the visibility state to the server.
function setVisState (element_name,is_visible) {
  var visibility = is_visible ? 'show' : 'hide';
  var postData   = 'action=show_hide_section;'+visibility+'='+element_name;
  new Ajax.Request(document.URL,{method:'post',postBody:postData});
}


function toggleDiv(id){
var spans = document.getElementsByTagName('div');
    for (var i = spans.length; i--;) {
        var element = spans[i];
        if (element.className.match(RegExp('\\b' + id + '\\b'))) {
            element.style.display = (element.style.display === 'none') ? '' : 'none';
        }
    }
}

function removeByElement(arrayName,arrayElement)
 {
    for(var i=0; i<arrayName.length;i++ )
     { 
        if(arrayName[i]==arrayElement)
            arrayName.splice(i,1);
      } 
  }

///////////////////////////////////////////////////////
function toggle_titlebar_stars(label,isFavorite) {
    var img                      = $('barstar_'+label);
    if (isFavorite == null) {
	isFavorite               = img.hasClassName('favorite');
        isFavorite                   = !isFavorite;  // toggle
    }
    togglestars(label,isFavorite);
}

function togglestars(label,isFavorite) {
    var img                      = $('star_'+label);
    var label_title              = $('selectrackname_'+label);
    if (img != null) {
	if (isFavorite == null)
	    isFavorite               = !img.hasClassName('favorite');  // toggle
	var src                      = Controller.button_url(isFavorite ? 'ficon_2.png'  : 'ficon.png');
	img.src                      = src;
	if (isFavorite)
	    img.addClassName('favorite');
	else
	    img.removeClassName('favorite');
    }

    new Ajax.Request(document.URL, {
 	  method: 'POST',
 	      asynchronous:true,
 	      parameters: {
 	      action:    'set_favorite',
 		  label:    label,
		  favorite: isFavorite ? 1 : 0
		    },
		onComplete: function (transport) {
		    Controller.update_sections(new Array(track_listing_id));
	    }
    });
    set_titlebar_star(label,isFavorite);
}

function set_titlebar_star(label,isFavorite) {
    var img = $('barstar_'+label);
    if (img == null) return;
    var src = Controller.button_url(isFavorite ? 'fmini_2.png'  : 'fmini.png');
    if (isFavorite)
	img.addClassName('favorite');
    else 
	img.removeClassName('favorite');
    img.src = src;
}

function idtoarray(stars,className) {
    var idArray = new Array();
    var x,y;
    for (x=0,y=0; x<stars.length; x++,y++) {
        if (stars[x].className === className) {
	    idArray[y] = stars[x].id;
	}
    }
    return idArray; 
}

Array.prototype.findIndex = function(value){
    var ctr = "";
    for (var i=0; i < this.length; i++) {
	// use === to check for Matches. ie., identical (===), ;
	if (this[i] == value) {
	    return i;
	}
    }
    return ctr;
};

// checkSummaries makes sure any collapsed nodes have their summaries visible upon page load.
function checkSummaries() {
    var tf = $('trackform');
    if (tf==null) return;
    
    var sections = tf.select("div.searchbody div.el_visible");
    for(j = 0; j < sections.length; j++) {
	if(sections[j].visible() == false)
	    summarizeTracks(sections[j]);
    }
}

// Update List - Goes through the listing node and marks any "turned on" nodes.
function updateList(node) {
    var children = getChildren(node);
    var list_items = getList(node).select("span");
    for (var a = 0; a < list_items.length; a++) {
	if (children[a].select('span.activeTrack').length != 0) {
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

function _checkAllToggles(element) {
    var node        = element.up("div.el_visible");
    var all_on      = node.up().down("input[type=checkbox][id$=_a]");
    var all_off     = node.up().down("input[type=checkbox][id$=_n]");
    var all_tracks  = node.select("span.track_title");
    var on_tracks   = all_tracks.findAll(function (el) {return el.hasClassName('activeTrack')});

    all_off.checked = on_tracks.length  == 0;
    all_on.checked  = all_tracks.length == on_tracks.length;
}

// Check "All" Toggles - turns off any "All On" or "All Off" checkboxes which are checked.
function checkAllToggles() {
    _checkAllToggles(this);
}

// summarizeTracks mines the track options box for possible tracks and creates a shorter listing of them when the section is hidden.
function summarizeTracks(node) {
    var children  = getChildren(node);
    var list_text = listText(children);
  
    // Append the HTML into the track list.
    var list = getList(node);
    list.update(list_text);
    list.show();
}

// Determines whether a node should be "on" in the listing.
function isOn(node) {
    return (node.select('span.activeTrack').length > 0)? true : false;
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
	if (((has_groups == true) && children[i].match("div.el_visible")) || ((has_groups == false) && (children[i].select("span.track_title").length > 0)))
	    nodes.push(children[i]);
    }
    return nodes;
}


// getName returns the name of a node, as displayed in the control.
function getName(node) {
  if (isGroup(node)) {
    return (node.previous("div.ctl_visible"))? node.previous("div.ctl_visible").down("span.tctl > b").innerHTML : node.previous("div").down("div.ctl_visible").down("span.tctl > b").innerHTML;
  } else {
      var track_name = node.down("span").innerHTML.stripTags();
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

//same as updatetitle(below) but will refresh the favorites if the user 
//decides to unclick a favorite while it is in show favorites mode
function clearallfav(clear){

    var e = $(track_listing_id);// all e._____ objects are visual effects
    var ministars = document.getElementsByClassName("toolbarStar");
    var i;
    clear =1;
    e.hide();
    e.setOpacity(0.3);
    new Ajax.Request(
		     document.URL, {
			 method: 'POST',
			     asynchronous:false,
			     parameters: {
			     action:    'clear_favorites',
				 clear: clear
				 }
		     }
		     );
    e.show();
    Controller.update_sections(new Array(track_listing_id));
    for (i in ministars){
	ministars[i].src =Controller.button_url('fmini.png');
    }
};

function showFavorites(ison){
    var e = $(track_listing_id);// all e._____ objects are visual effects
    e.hide();
    e.setOpacity(0.3);
    new Ajax.Request(
		     document.URL, {
			 method: 'POST',
			     asynchronous:false,
			     parameters: {
			     action:    'show_favorites',
			     show: ison //sends 0 or 1 
			 }
		     }
		     );
    e.show();
    Controller.update_sections(new Array(track_listing_id));
};

//Wrapper function -- will toggle the 'Show All and Show Favorites' texit 
//then checks to see whether the favorites should be displayed or if they 
//should all be displayed--sends 0 or 1 to the server 
//controller.update_sections does the actual updating of the tracks
// ison true shows favorites
// ison false shows all
function updateTitle(me,ison){
    var show_favorites = Controller.translate('FAVORITES');
    var show_all       = Controller.translate('SHOWALL');
    Element.extend(me);
    var current = me.hasClassName('favorites_only') ? 0 : 1;
    if (ison == null)
	ison = current;
    me.innerHTML = ison ? show_all : show_favorites;
    if (ison)
	me.addClassName('favorites_only');
    else
	me.removeClassName('favorites_only');
    if (ison == current)
	showFavorites(ison);
};

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
