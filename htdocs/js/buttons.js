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

  var added_tracks = false;

  if (state == 1){
    var track_names = new Array();
    for (var i=0; i<checkboxes.length; i++) {
      checkboxes[i].checked=state;
      track_names.push(checkboxes[i].value)
    }
    added_tracks = Controller.add_tracks(track_names);
  }

  if  (!added_tracks) {
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
  ShowHideTrack(track_name,visible);
}

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
		      handle:  'titlebar',
		      scroll:   window,
		      onUpdate: function() {
		      var postData = Sortable.serialize(div_name,{name:'label'});
		      new Ajax.Request(document.URL,{method:'post',postBody:postData});
		    }
		  }
		 );
}

