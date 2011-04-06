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
function toggle_bar_stars(event,imgID, label, title) {
    var imgTag = document.getElementById(imgID);

    var fullPathName = imgTag.src;
    var pathSplit = fullPathName.split("/");
    var getfileNameExt = pathSplit.length - 1;
    var fullFilePath = '';
    if (pathSplit.length == 0) {
	fullFilePath = ''; 
    } else if (pathSplit.length > 0) {
	fullFilePath = fullPathName.replace(pathSplit[getfileNameExt], ''); 
    }
 
    var fileNameExt = pathSplit[getfileNameExt]; 
    var fileNameSplit = fileNameExt.split("."); 
    var fileName = fileNameSplit[0]; // just the file name
    var fileExt = fileNameSplit[1]; // just the file extention
    var fileNameMainSplit = fileName.split("_"); // check for a split on '_'
    var imgName ='';
    var show;     
  
     if (fileNameMainSplit.length > 1) {
	 var fileNameMain = fileNameMainSplit.length - 1;
	 fileNameMain = fileNameMainSplit[fileNameMain]; 
	 if (fileNameMain == 2) {
	     imgName = fileNameMainSplit[0] + '.' + fileExt;
	     favorite = false;
	 } else {
	     imgName = fileName + '_2.' + fileExt;
	     favorite = true;	
	 }
     } else {
	 imgName = fileName + '_2.' + fileExt;
	 favorite = true; 
     }
     show = (favorite == true) ? 1 : 0;
     new Ajax.Request(document.URL, {
	     method: 'POST',
		 asynchronous:false,
		 parameters: {
		 action:    'set_favorite',
		     label:  label,
		     favorite:show,
		     }});
		  
     var finalFile = fullFilePath + imgName;
     imgTag.src = finalFile;
     Controller.update_sections(new Array(track_listing_id));
     return false;
}

function togglestars(event,imgID, txtID, favorites,cellid)
{
 //   detectshiftkey();
  var imgTag = document.getElementById(imgID);

  var cellTag = document.getElementById(cellid);
 
  var txtTag = document.getElementById(txtID);
  var fullPathName = imgTag.src;
  var pathSplit = fullPathName.split("/");
  var getfileNameExt = pathSplit.length - 1;
  var fullFilePath = '';
  var str = imgID.replace("ficonpic_","");
  var labels_Range = new Array();
  var ministars_Range = new Array();
 
  if (pathSplit.length == 0)
  {
    fullFilePath = ''; 
  }
  else if (pathSplit.length > 0)
  {
    fullFilePath = fullPathName.replace(pathSplit[getfileNameExt], ''); 
  }
 
  var fileNameExt = pathSplit[getfileNameExt]; 
  var fileNameSplit = fileNameExt.split("."); 
  var fileName = fileNameSplit[0]; // just the file name
  var fileExt = fileNameSplit[1]; // just the file extention
  var fileNameMainSplit = fileName.split("_"); // check for a split on '_'
  var imgName ='';
  var show;     
     var miniID = 'fav_'+imgID;
  
  var browserstarTag = document.getElementById(miniID);
  var blank_min_src    = fullFilePath+"fmini.png";
  var coloured_min_src = fullFilePath+"fmini_2.png";

  ////select track stars
  var stars = document.getElementsByClassName("star");  
  idtoarray(stars,"star");
  var starsid = idArray;
  /////////////

  var startext = document.getElementsByClassName("selectrackname");
  idtoarray(startext,"selectrackname");
  var starTextId = idArray;

/////browser page stars
  var ministars = document.getElementsByClassName("toolbarStar");
  idtoarray(ministars, "toolbarStar");

  var ministarsids= idArray;
//////////////

  var firstIndex;
  if (!event.shiftKey){
      firstIndex = starsid.findIndex(imgID); 
      sessvars.firstIndex= {"index":firstIndex};
      
  }
  var lastIndex;
 
  if (fileNameMainSplit.length > 1)
      {
   
	  var fileNameMain = fileNameMainSplit.length - 1;
	  fileNameMain = fileNameMainSplit[fileNameMain]; 
	  if (fileNameMain == 2)
	      {
		  imgName = fileNameMainSplit[0] + '.' + fileExt;
		  txtTag.style.fontWeight = "normal";
		  
		  favorite = false;
   
	      }else{
	      imgName = fileName + '_2.' + fileExt;
	      txtTag.style.fontWeight = "900";
	      
	      favorite = true;	
	      
	  }
      }else{
      imgName = fileName + '_2.' + fileExt;
      txtTag.style.fontWeight = "900";
      
      favorite = true; 
      
  }
     
  //if it is favorited send a 1
  
     
  txtTag.className = 'notselected';
  cellTag.className = 'notselected_check';
  show = (favorite == true) ? 1 : 0;
  //    
  new Ajax.Request(document.URL, {
	  method: 'POST',
	      asynchronous:true,
	      parameters: {
	      action:    'set_favorite',
		  label:   imgID,
		  favorite:show
  	          }});

  
  if (event.shiftKey) {

      firstIndex = sessvars.firstIndex.index;
      lastIndex = starsid.findIndex(imgID);
  
      var j;
      var i;
      show = (favorite == true) ? 1 : 0;
      
      if(lastIndex<firstIndex){
	  var tmp; 
	  tmp = lastIndex;
	  lastIndex = firstIndex;
	  firstIndex = tmp;
      }
 
      var range = lastIndex - firstIndex; 
      for( i=firstIndex , j = 0; i<=lastIndex, j <= range ; i++, j++){
	  labels_Range[j] = starsid[i];

      }
      var labels_string = labels_Range.toString();

    
      new Ajax.Request(document.URL, {
	      method: 'POST',
  		  asynchronous:true,
  		  parameters: {
		  action:    'set_favorite',
		      label:  labels_string,
		      favorite:show,
		      }});
		  
      var minisrc = (show == 1) ? coloured_min_src : blank_min_src;

      for(var i=firstIndex ;i<=lastIndex; i++){
	  stars[i].src= fullFilePath + imgName;   
	  
	  if (startext[i] != null) {
	      if(imgName=='ficon.png'){
		  startext[i].style.fontWeight = "normal";
	      } else {
	      startext[i].style.fontWeight = "900";
	      }
	  }
   
	  if(ministars[i]){
	      ministars[i].src = minisrc;
	  }
      }
  }
    

  if(browserstarTag){
      browserstarTag.src = (favorite == true) ? coloured_min_src : blank_min_src;
  };
  var finalFile = fullFilePath + imgName;
  imgTag.src = finalFile;

  return false;
}


function idtoarray(stars,class)
{
 
idArray = new Array();
 
    for (x=0, y=0; x<stars.length; x++,y++) {
        if (stars[x].className===class) {
        idArray[y] = stars[x].id
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

//  function to make text toggle when button/link is touched 
function swap(me,main,alt) {
    me.innerHTML = (me.innerHTML == main) ? alt : main;
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
function updateTitle(me,main,alt,ison){
    var current = (me.innerHTML == main) ? 1 : 0;
    if (ison == null)
	ison = current;
    me.innerHTML = ison ? alt : main;
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
