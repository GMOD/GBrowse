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
  
  var checkboxes = $(a).select(".track_title");
  if (!checkboxes)
    return false;

  for (var i=0; i<checkboxes.length; i++) {
      var track_name = checkboxes[i].id.substring(0,checkboxes[i].id.lastIndexOf("_"));
      ShowHideTrack(track_name,state);
  }
  gbTurnOff(a);
  button.checked = true;
  updateList($(a));
  return true;
}

function gbToggleTrack (track_name) {
    ShowHideTrack(track_name);
}

// ShowHideTrack toggles the visibility of "track", based on the "visible" flag.
function ShowHideTrack(track_name,visible) {
  var track_title = $(track_name+'_check');
  var track_img   = $(track_name+'_img');
  if (track_title == null) return;
  var ancestor    = track_title.ancestors().find(
					function (el) {
					    return el.nodeName == 'TD'
					});
  if (visible == null) {
      visible = !ancestor.hasClassName('activeTrack');
  }
  if (visible) {
      ancestor.addClassName('activeTrack');
      track_title.addClassName('activeTrack');
      track_img.src=Controller.button_url('check.png');
  }  else {
      ancestor.removeClassName('activeTrack');
      track_title.removeClassName('activeTrack');
      track_img.src=Controller.button_url('square.png');
  }

  checkSummaries();
  _checkAllToggles(track_title);

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

