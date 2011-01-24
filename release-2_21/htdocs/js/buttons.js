var GlobalDrag;

// gbTurnOff turns off any "All On" or "All Off" checkboxes which are checked.
function gbTurnOff (section_name) {
  if ($(section_name+"_a"))
    $(section_name + "_a").checked = false;
  if ($(section_name+"_n"))
    $(section_name + "_n").checked = false;
}

// gbCheck turns all of the tracks on or off in a track group.
function gbCheck (button,state) {
  var a = button.id.substring(0, button.id.lastIndexOf("_"));
  if (!$(a))
    return false;
  
  var checkboxes = $(a).select("input");
  if (!checkboxes)
    return false;

  var added_tracks = false;

  if (state == 1) {
    var track_names = new Array();
    for (var i=0; i<checkboxes.length; i++) {
      checkboxes[i].checked=state;
      track_names.push(checkboxes[i].value)
    }
    added_tracks = Controller.add_tracks(track_names);
  }

  if  (!added_tracks) {
    for (var i=0; i<checkboxes.length; i++) {
      checkboxes[i].checked = state;
      gbToggleTrack(checkboxes[i]);
    }
  }
  gbTurnOff(a);
  button.checked = true;
  updateList($(a));
  return true;
}

function gbToggleTrack (button) {
  var track_name = button.value;
  var visible    = button.checked;
  ShowHideTrack(track_name,visible);
}

// ShowHideTrack toggles the visibility of "track", based on the "visible" flag.
function ShowHideTrack(track_name,visible) {
  if (visible && !Controller.track_exists(track_name)) {
      Controller.add_track(track_name);
      return false;
  }

  Controller.each_track(track_name,function(gbtrack) {
       var el_id   = gbtrack.track_div_id;
       var element = $(el_id);

       if (visible) {
           if (element.style.display == "none") { 
             element.style.display="block";
             Controller.set_track_visibility(gbtrack.track_id, 1);
           }
       }
       else {
          if (element && element.style.display != "none") { 
              element.style.display="none";
              Controller.set_track_visibility(gbtrack.track_id, 0);
          }
       }
     });

     if ($(track_name+'_check') == null)
         track_name = track_name.sub(/:(overview|region|detail)$/,'');
     $(track_name + '_check').checked = visible ? true : false;
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
		      tag:     'div',
		      constraint:  'vertical',
  		      only:    'track',
		      handle:  'drag_region',
		      scroll:   window,
		      onUpdate: function() {
		      var items   = $(div_name).select('[class="track"]');
		      var ids     = items.map(function(e){return e.id});
		      ids         = ids.map(function(i) {return 'label[]='+escape(i.sub(/^track_/,''))});
		      var postData= ids.join('&')+';action=change_track_order';
		      new Ajax.Request(document.URL,{method:'post',postBody:postData});
		    }
		  }
		 );
}

