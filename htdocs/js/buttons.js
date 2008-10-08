var GlobalDrag;

function gbTurnOff (a) {
  if (document.getElementById(a+"_a")) { document.getElementById(a+"_a").checked='' };
  if (document.getElementById(a+"_n")) { document.getElementById(a+"_n").checked='' };
}

function gbCheck (button,state) {
  var a         = button.id;
  a             = a.substring(0,a.lastIndexOf("_"));
  var container = document.getElementById(a);
  if (!container) { return false; }
  var checkboxes = container.getElementsByTagName('input');
  if (!checkboxes) { return false; }
  if (state == 1){
    var track_names = new Array();
    for (var i=0; i<checkboxes.length; i++) {
      checkboxes[i].checked=state;
      track_names.push(checkboxes[i].value)
    }
    Controller.add_tracks(track_names);
  }
  else{
    for (var i=0; i<checkboxes.length; i++) {
      checkboxes[i].checked=state;
      gbToggleTrack(checkboxes[i]);
    }
  }
  gbTurnOff(a);
  button.checked="on";
  return false;
}

function gbToggleTrack (button) {
  var track_name = button.value;
  var visible    = button.checked;
  var element    = document.getElementById("track_"+track_name);
  if (visible) {
    if (!element) { 
      Controller.add_track(track_name);
    }
    else if (element.style.display == "none") { 
      element.style.display="block";
      Controller.set_track_visibility(track_name, 1);
    }
    return false; 
  }
  else {
    if (element && element.style.display != "none") { 
      element.style.display="none";
      Controller.set_track_visibility(track_name, 0);
    }
  }
}

function update_segment (formdata) {
  var postData = 'render=detailview';
  if (formdata && formdata.length>0) {
      postData = postData + ';' + formdata
 }
  $('details_panel').innerHTML='Loading...';
  new Ajax.Updater('details_panel',
		   document.URL,
		   { method:       'post',
                     postBody:     postData,
                     evalScripts:  true
		   }
                  );
}

function create_drag (div_name) {
   GlobalDrag = div_name;
   Sortable.create(
		  div_name,
		  {
		  constraint: 'vertical',
		      tag: 'div',
		      only: 'track',
		      handle: 'titlebar',
		      onUpdate: function() {
		      var postData = Sortable.serialize(div_name,{name:'label'});
		      new Ajax.Request(document.URL,{method:'post',postBody:postData});
		    }
		  }
		 );
}

function kill_drag() { 
    if (GlobalDrag) {
	var s = Sortable.options(GlobalDrag);
	if(s) {
	    s.draggables.each(
			      function (d) {
				  alert(d.dragging);
				  d.dragging = false;
				 }
			      );
	}
	GlobalDrag = null;
    }
}