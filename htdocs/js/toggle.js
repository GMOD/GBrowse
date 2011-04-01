var track_listing_id        = 'tracks_panel'; 


///create getelementbyclassnames function

/*
	Developed by Robert Nyman, http://www.robertnyman.com
	Code/licensing: http://code.google.com/p/getelementsbyclassname/
*/
var getElementsByClassName = function (className, tag, elm){
	if (document.getElementsByClassName) {
		getElementsByClassName = function (className, tag, elm) {
			elm = elm || document;
			var elements = elm.getElementsByClassName(className),
				nodeName = (tag)? new RegExp("\\b" + tag + "\\b", "i") : null,
				returnElements = [],
				current;
			for(var i=0, il=elements.length; i<il; i+=1){
				current = elements[i];
				if(!nodeName || nodeName.test(current.nodeName)) {
					returnElements.push(current);
				}
			}
			return returnElements;
		};
	}
	else if (document.evaluate) {
		getElementsByClassName = function (className, tag, elm) {
			tag = tag || "*";
			elm = elm || document;
			var classes = className.split(" "),
				classesToCheck = "",
				xhtmlNamespace = "http://www.w3.org/1999/xhtml",
				namespaceResolver = (document.documentElement.namespaceURI === xhtmlNamespace)? xhtmlNamespace : null,
				returnElements = [],
				elements,
				node;
			for(var j=0, jl=classes.length; j<jl; j+=1){
				classesToCheck += "[contains(concat(' ', @class, ' '), ' " + classes[j] + " ')]";
			}
			try	{
				elements = document.evaluate(".//" + tag + classesToCheck, elm, namespaceResolver, 0, null);
			}
			catch (e) {
				elements = document.evaluate(".//" + tag + classesToCheck, elm, null, 0, null);
			}
			while ((node = elements.iterateNext())) {
				returnElements.push(node);
			}
			return returnElements;
		};
	}
	else {
		getElementsByClassName = function (className, tag, elm) {
			tag = tag || "*";
			elm = elm || document;
			var classes = className.split(" "),
				classesToCheck = [],
				elements = (tag === "*" && elm.all)? elm.all : elm.getElementsByTagName(tag),
				current,
				returnElements = [],
				match;
			for(var k=0, kl=classes.length; k<kl; k+=1){
				classesToCheck.push(new RegExp("(^|\\s)" + classes[k] + "(\\s|$)"));
			}
			for(var l=0, ll=elements.length; l<ll; l+=1){
				current = elements[l];
				match = false;
				for(var m=0, ml=classesToCheck.length; m<ml; m+=1){
					match = classesToCheck[m].test(current.className);
					if (!match) {
						break;
					}
				}
				if (match) {
					returnElements.push(current);
				}
			}
			return returnElements;
		};
	}
	return getElementsByClassName(className, tag, elm);
};


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


 
function toggle_bar_stars(event,imgID, label, title){
    var imgTag = document.getElementById(imgID);

//   alert(imgTag.src);
  var fullPathName = imgTag.src;
  var pathSplit = fullPathName.split("/");
  var getfileNameExt = pathSplit.length - 1;
  var fullFilePath = '';
 
// alert(imgID);
// alert(imgTag);
// alert(title);
  if (pathSplit.length == 0)
  {
    fullFilePath = ''; 
  }
  else if (pathSplit.length > 0)
  {
    fullFilePath = fullPathName.replace(pathSplit[getfileNameExt], ''); 
  }
 
  var fileNameExt = pathSplit[getfileNameExt]; 
  var fileNameSpilt = fileNameExt.split("."); 
  var fileName = fileNameSpilt[0]; // just the file name
  var fileExt = fileNameSpilt[1]; // just the file extention
  var fileNameMainSpilt = fileName.split("_"); // check for a spilt on '_'
  var imgName ='';
  var show;     
  
 
  if (fileNameMainSpilt.length > 1)
  {
   
    var fileNameMain = fileNameMainSpilt.length - 1;
    fileNameMain = fileNameMainSpilt[fileNameMain]; 
    if (fileNameMain == 2)
    {
      imgName = fileNameMainSpilt[0] + '.' + fileExt;
   
   
       favorite = false;
   
    }else{
      imgName = fileName + '_2.' + fileExt;
  
  
      favorite = true;	
      
      
	}
  }else{
    imgName = fileName + '_2.' + fileExt;


    favorite = true; 
    
	}

 show = (favorite == true) ? 1 : 0;

 
//  alert(trackStatus);
//    
   new Ajax.Request(document.URL, {
  	          method: 'POST',
  		  asynchronous:true,
  		  parameters: {
  		        action:    'set_favorite',
  			label:  label,
 			favorite:show,
  	          }});
		  
		  
 var finalFile = fullFilePath + imgName;
   imgTag.src = finalFile;
   
   
  
  refresh(0);
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
  var fileNameSpilt = fileNameExt.split("."); 
  var fileName = fileNameSpilt[0]; // just the file name
  var fileExt = fileNameSpilt[1]; // just the file extention
  var fileNameMainSpilt = fileName.split("_"); // check for a spilt on '_'
  var imgName ='';
  var show;     
     var miniID = 'fav_'+imgID;
  
  var browserstarTag = document.getElementById(miniID);
    var blank_min_src =fullFilePath+"fmini.png";
    var coloured_min_src = fullFilePath+"fmini_2.png";

  
  var stars = getElementsByClassName("star");  
  idtoarray(stars,"star");
  var starsid = idArray;
//   /*alert*/(starsid);
  var ministars = getElementsByClassName("toolbarStar");
  idtoarray(ministars, "toolbarStar");
  var ministarsids= idArray;
  
//   alert(ministarsids);
  
  var firstIndex;
  if (!event.shiftKey){
  firstIndex = starsid.findIndex(imgID); 
  sessvars.firstIndex= {"index":firstIndex};
  
 }
  var lastIndex;
 
  if (fileNameMainSpilt.length > 1)
  {
   
    var fileNameMain = fileNameMainSpilt.length - 1;
    fileNameMain = fileNameMainSpilt[fileNameMain]; 
    if (fileNameMain == 2)
    {
      imgName = fileNameMainSpilt[0] + '.' + fileExt;
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
 			favorite:show,
  	          }});

  
if (event.shiftKey) {

    firstIndex = sessvars.firstIndex.index;
    lastIndex = starsid.findIndex(imgID);
  
    var j;
    var i;
//     alert(firstIndex);
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

//     alert(minisrc);
       for(var i=firstIndex ;i<=lastIndex; i++){
   stars[i].src= fullFilePath + imgName;      
   ministars[i].src = minisrc;
   
       }
    }
    

// (favorite == true) ? fullFilePath+'fmini_2.png' : fullFilePath+'fmini.png';
   if(browserstarTag){
   browserstarTag.src = (favorite == true) ? coloured_min_src : blank_min_src;
   };
//    alert(browserstarTag.src);
//   alert(blank_min_src);
//   alert(coloured_min_src);
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
var ministars = getElementsByClassName("toolbarStar");
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
		clear: clear,
			     }
				}
		);
                  
e.show();
		        
Controller.update_sections(new Array(track_listing_id),'',1,false);
 for (i in ministars){
   ministars[i].src ="http://localhost/gbrowse2/images/buttons/fmini.png";
 }
 
};



function refresh(ison){
  
  
var e = $(track_listing_id);// all e._____ objects are visual effects



e.hide();
e.setOpacity(0.3);

		       
new Ajax.Request(
		document.URL, {
		method: 'POST',
		asynchronous:false,
		parameters: {
		action:    'show_favorites',
		show: ison, //sends 0 or 1 
		clear:0,
			     }
				}
		);

new Ajax.Request(
		document.URL, {
		method: 'POST',
		asynchronous:false,
		parameters: {
		action:    'clear_favorites',
	
		clear:0,
			     }
				}
		);
                  
e.show();

Controller.update_sections(new Array(track_listing_id),'',1,false)


 
};
//Wrapper function -- will toggle the 'Show All and Show Favorites' texit 
//then checks to see whether the favorites should be displayed or if they 
//should all be displayed--sends 0 or 1 to the server 
//controller.update_sections does the actual updating of the tracks
function updatetitle(me,main,alt,ison,refresh, clear){
  
  
var e = $(track_listing_id);// all e._____ objects are visual effects
var refreshid = document.getElementById(refresh);
var clearid = document.getElementById(clear);

swap(me,main,alt);//toggle

e.hide();
e.setOpacity(0.3);
ison = (me.innerHTML == main) ? 0 : 1;
refreshid.style.display= (me.innerHTML == main) ? 'none' : 'block';
clearid.style.left=(me.innerHTML == main) ? '350px' : '550px';
clearid.style.bottom=(me.innerHTML == main) ? '30px' : '47px';
new Ajax.Request(
		document.URL, {
		method: 'POST',
		asynchronous:false,
		parameters: {
		action:    'show_favorites',
		show: ison, //sends 0 or 1 
			     }
				}
		);

new Ajax.Request(
		document.URL, {
		method: 'POST',
		asynchronous:false,
		parameters: {
		action:    'clear_favorites',
	
		clear:0,
			     }
				});
                  
		
e.show();
		        
Controller.update_sections(new Array(track_listing_id),'',1,false)
  
 
};

function collapse(element_name) {
   var control = document.getElementById(element_name+"_title");
//    var menuitem = document.getElementById("popmenu_"+element_name);
   var icon    = document.getElementById(element_name+"_icon");
   var body    = document.getElementById(element_name+"_image");
   var pad     = document.getElementById(element_name+"_pad");
   var closeit = body.style.display != "none";
   var src     = new String(icon.src);
//    var text    = new String('');

   if (closeit) {
     icon.src = src.replace(/minus/,'plus');
//      menuitem.text = text.replace(/Collapse/,'Expand');
     body.style.display = 'none';
     pad.style.display = 'inline';
     control.className = 'titlebar_inactive';
     
   } else {
     icon.src = src.replace(/plus/,'minus');
//      menuitem.text = text.replace(/Expand/,'Collapse');
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



	
	/*Script for left slide out panel in the Select track page...credit to dhtmlgoodies.com
	*/
	
		var panelWidth =250;	// Width of help panel	
	var slideSpeed = 50;		// Higher = quicker slide
	var slideTimer = 10;	// Lower = quicker slide
	var slideActive = true;	// Slide active ?
	var initBodyMargin = 0;	// Left or top margin of your <body> tag (left if panel is at the left, top if panel is on the top)
	var pushMainContentOnSlide = true;	// Push your main content to the right when sliding
	var panelPosition = 1; 	// 0 = left , 1 = top
	
	/*	Don't change these values */
	var slideLeftPanelObj=false;
	var slideInProgress = false;	
	var startScrollPos = false;
	var panelVisible = false;
	function initSlideLeftPanel(expandOnly)
	{
		if(slideInProgress)return;
		if(!slideLeftPanelObj){
			if(document.getElementById('dhtmlgoodies_leftPanel')){	// Object exists in HTML code?
				slideLeftPanelObj = document.getElementById('dhtmlgoodies_leftPanel');
				if(panelPosition == 1)slideLeftPanelObj.style.width = '100%';
			}else{	// Object doesn't exist -> Create <div> dynamically
				slideLeftPanelObj = document.createElement('DIV');
				slideLeftPanelObj.id = 'dhtmlgoodies_leftPanel';
				slideLeftPanelObj.style.display='none';
				document.body.appendChild(slideLeftPanelObj);
			}
			
			if(panelPosition == 1){
				slideLeftPanelObj.style.top = "-" + panelWidth + 'px';
				slideLeftPanelObj.style.left = '0px';	
				slideLeftPanelObj.style.height = panelWidth + 'px';			
			}else{
				slideLeftPanelObj.style.left = "-" + panelWidth + 'px';
				slideLeftPanelObj.style.top = '0px';
				slideLeftPanelObj.style.width = panelWidth + 'px';
			}
			

			if(!document.all || navigator.userAgent.indexOf('Opera')>=0)slideLeftPanelObj.style.position = 'fixed';;
		}	
		
		if(panelPosition == 0){
			if(document.documentElement.clientHeight){
				slideLeftPanelObj.style.height = document.documentElement.clientHeight + 'px';
			}else if(document.body.clientHeight){
				slideLeftPanelObj.style.height = document.body.clientHeight + 'px';
			}
			var leftPos = slideLeftPanelObj.style.left.replace(/[^0-9\-]/g,'')/1;
		}else{
			if(document.documentElement.clientWidth){
				slideLeftPanelObj.style.width = document.documentElement.clientWidth + 'px';
			}else if(document.body.clientHeight){
				slideLeftPanelObj.style.width = document.body.clientWidth + 'px';
			}
			var leftPos = slideLeftPanelObj.style.top.replace(/[^0-9\-]/g,'')/1;			
			
			
		}
		slideLeftPanelObj.style.display='block';
		
		if(panelPosition==1)
			startScrollPos = Math.max(document.body.scrollTop,document.documentElement.scrollTop);
		else
			startScrollPos = Math.max(document.body.scrollLeft,document.documentElement.scrollLeft);
		if(leftPos<(0+startScrollPos)){
			if(slideActive){
				slideLeftPanel(slideSpeed);	
			
			}else{
				document.body.style.marginLeft = panelWidth + 'px';
				slideLeftPanelObj.style.left = '0px';
			}
		}else{
			if(expandOnly)return;
			if(slideActive){		
				slideLeftPanel(slideSpeed*-1);
			}else{
				if(panelPosition == 0){
					if(pushMainContentOnSlide)document.body.style.marginLeft =  initBodyMargin + 'px';
					slideLeftPanelObj.style.left = (panelWidth*-1) + 'px';	
				}else{
					if(pushMainContentOnSlide)document.body.style.marginTop =  initBodyMargin + 'px';
					slideLeftPanelObj.style.top = (panelWidth*-1) + 'px';						
				}			
			}
		}	
		
		if(navigator.userAgent.indexOf('MSIE')>=0 && navigator.userAgent.indexOf('Opera')<0){
			window.onscroll = repositionHelpDiv;
		
			repositionHelpDiv();
		}
		window.onresize = resizeLeftPanel;
		
	}
	
	function resizeLeftPanel()
	{
		if(panelPosition == 0){
			if(document.documentElement.clientHeight){
				slideLeftPanelObj.style.height = document.documentElement.clientHeight + 'px';
			}else if(document.body.clientHeight){
				slideLeftPanelObj.style.height = document.body.clientHeight + 'px';
			}		
		}else{
			if(document.documentElement.clientWidth){
				slideLeftPanelObj.style.width = document.documentElement.clientWidth + 'px';
			}else if(document.body.clientWidth){
				slideLeftPanelObj.style.width = document.body.clientWidth + 'px';
			}	
		}
	}
	
	function slideLeftPanel(slideSpeed){
		slideInProgress =true;
		var scrollValue = 0;
		if(panelPosition==1)
			var leftPos = slideLeftPanelObj.style.top.replace(/[^0-9\-]/g,'')/1;
		else
			var leftPos = slideLeftPanelObj.style.left.replace(/[^0-9\-]/g,'')/1;
			
		leftPos+=slideSpeed;
		okToSlide = true;
		if(slideSpeed<0){
			if(leftPos < ((panelWidth*-1) + startScrollPos)){
				leftPos = (panelWidth*-1) + startScrollPos;	
				okToSlide=false;
			}
		}
		if(slideSpeed>0){
			if(leftPos > (0 + startScrollPos)){
				leftPos = 0 + startScrollPos;
				okToSlide = false;
			}			
		}
		
		
		if(panelPosition==0){
			slideLeftPanelObj.style.left = leftPos + startScrollPos + 'px';
			if(pushMainContentOnSlide)document.body.style.marginLeft = leftPos - startScrollPos + panelWidth + 'px';
		}else{
			slideLeftPanelObj.style.top = leftPos + 'px';
			if(pushMainContentOnSlide)document.body.style.marginTop = leftPos - startScrollPos + panelWidth + 'px';			
			
		}
		if(okToSlide)setTimeout('slideLeftPanel(' + slideSpeed + ')',slideTimer); else {
			slideInProgress = false;
			if(slideSpeed>0)panelVisible=true; else panelVisible = false;
		}
		
	}
	
	
	function repositionHelpDiv()
	{
		if(panelPosition==0){
			var maxValue = Math.max(document.body.scrollTop,document.documentElement.scrollTop);
			slideLeftPanelObj.style.top = maxValue;
		}else{
			var maxValue = Math.max(document.body.scrollLeft,document.documentElement.scrollLeft);
			slideLeftPanelObj.style.left = maxValue;	
			var maxTop = Math.max(document.body.scrollTop,document.documentElement.scrollTop);
			if(!slideInProgress)slideLeftPanelObj.style.top = (maxTop - (panelVisible?0:panelWidth)) + 'px'; 		
		}
	}
	
	function cancelEvent()
	{
		return false;
	}
	function keyboardShowLeftPanel()
	{
			initSlideLeftPanel();
			return false;	
	
	}
	
	function leftPanelKeyboardEvent(e)
	{
		if(document.all)return;
		
		if(e.keyCode==112){
			initSlideLeftPanel();
			return false;
		}		
	}
	
	function setLeftPanelContent(text)
	{
		document.getElementById('leftPanelContent').innerHTML = text;
		initSlideLeftPanel(true);
		
	}
	if(!document.all)document.documentElement.onkeypress = leftPanelKeyboardEvent;
	document.documentElement.onhelp  = keyboardShowLeftPanel;
	
	
// 	


	
	
	
	
	
	