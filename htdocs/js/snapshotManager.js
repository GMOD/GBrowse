// snapshotManager.js
// *** Snapshot functions ***

GBrowseController.addMethods({
	     	     
 killSnapshot:
 function(snapshot){
	var snapshot_row = document.getElementById(snapshot);
  
	// Stops displaying the selecting snapshot before actually deleting it
   	snapshot_row.style.display="none";

	// An asynchronous request is made to delete the snapshot from the session
    	new Ajax.Request(document.URL, {
  	          method: 'POST',
  		  asynchronous:true,
  		  parameters: {
  		        action:    'delete_snapshot',
  			name: snapshot,

  	          }});

	// Removes the snapshot from the pages title if it was the last one set
	if($('snapshot_page_title').innerHTML == 'Snapshot : ' + snapshot){
		$('snapshot_page_title').innerHTML = 'Snapshot : ';
		$('snapshot_page_title').hide();
	}
   
 },
				     
  saveSnapshot:
  function(alternate){
	var sessionName;
	if(alternate){
		sessionName = 'snap_' + $('snapshot_name_2').value;
	} else {
		sessionName = 'snap_' + $('snapshot_name').value;
	}

	if(Controller.snapshotExists(sessionName)){
		return;
	}
	// If a value was entered for the name of the snapshot then it is saved
 	else if(sessionName){

		$('busy_indicator').show();
		$('snapshot_page_title').update('Saving Snapshot...');
		$('snapshot_page_title').style.color = 'red';
		$('snapshot_page_title').show();

		// An asynchronous request is made to save a snapshot of the session
 		new Ajax.Request(document.URL, {
  	        	  method: 'POST',
  			  asynchronous:true,
  			  parameters: {
  			        action:    'save_snapshot',
  				name: sessionName,
  	        	  }});

		// A timer is used to ensure that the snapshot table is recreated only after the information has been updated
		setTimeout(function(){

			// The snapshot table is updated
			var sections = new Array(snapshot_table_id);
			Controller.update_sections(sections); 	

			// Another timeout is used to end the busy indicator after the table has been created	
			setTimeout(function(){
				Sortable.create('snapshotTable',{tag:'div',only:'draggable'});	
				$('busy_indicator').hide();	

				// The page title is updated to reflect the current snapshot
				//$('snapshot_page_title').update('Snapshot : ' + sessionName);
				//$('snapshot_page_title').style.color = 'navy';
				$('snapshot_page_title').hide();
				    	     },1500)	
				     },2500)
	} else {
		alert("Please enter a name for the snapshot. The snapshot was not saved.");
	}

  },	
	     				     				 				     
 setSnapshot:
 function(sessionName){

	$('busy_indicator').show();
	$('snapshot_page_title').update('Loading Snapshot...');
	$('snapshot_page_title').style.color = 'red';
	$('snapshot_page_title').show();
	var active = new Array();

	// A request is made to update the current session
 	new Ajax.Request(document.URL, {
		method: 'POST',
		    asynchronous:true,
		    parameters: {
		    action: 'set_snapshot',
  			name: sessionName,
			},
		    onSuccess: function(transport) { 
		      var results = transport.responseJSON;
		      Controller.reload_panels(results.segment_info);
		      Controller.update_sections(new Array(track_listing_id));
		      TrackPan.make_details_draggable();
		      console.log(results.segment_info.detail_start);
		      Controller.select_tab('main_page');
		      $('snapshot_page_title').hide();

		}
	});
 },

sendSnapshot: function(snapshot){

	// The snapshot code to be sent is initially set to ''
  	var snapshot_url = '';

	// Only one send snapshot_box is open at a time
  	var send_snapshot_boxes = $$('.send_snapshot');
  	send_snapshot_boxes.each(function(box){
		box.hide();
  	})

	// Snapshot rows are pushed back and the selected row is pushed forward
  	var draggable = $$('.draggable');
  	draggable.each(function(drag){
		drag.style.zIndex = 0;
	})
	
  	$(snapshot).style.zIndex = 1000;
	// The div containing the snapshot information is shown
  	$('send_snapshot_' + snapshot).show();

	// An asynchronous request to the server loads the snapshot code for the selected snapshot
	// This is only loaded for the specific snapshot that the user intends to share rather than all snapshots. This saves time.
 	new Ajax.Request(document.URL, {
  	          method: 'POST',
  		  asynchronous:true,
  		  parameters: {
  		        action:    'send_snapshot',
  			name: 	snapshot,
			url:   document.location.href,
  	          },
		  onSuccess: function(transport) {
			// Upon success, the snapshot code is output to the user for copying
                  	var results      = transport.responseText;
			$('send_snapshot_url_' + snapshot).update(results);
		  }
            });
  },

 pushForward:
  function(snapshot){
	var draggable = $$('.draggable');
	draggable.each(function(drag){
		drag.style.zIndex = 0;
	})
	$(snapshot).style.zIndex = 1000;
 },

  mailSnapshot:
  function(snapshot){
	var email = $('email_' + snapshot).value;

  	$('mail_snapshot_' + snapshot).hide();
  	$('busy_indicator').show();

	// An asynchronous request is used to send an email to the email provided
 	new Ajax.Request(document.URL, {
  	          method: 'POST',
  		  asynchronous:true,
  		  parameters: {
  		        action:    'mail_snapshot',
  			email: 	   email,
			name:  snapshot,
			url:   document.location.href,
  	          },
		  onSuccess: function(transport) {
		      var results = transport.responseJSON;
		      if (!results.success) {
			  Controller.show_error('Your mail could not be sent',results.msg);
		      }
                      $('busy_indicator').hide();
		  }
            });
  },

 checkSnapshot:
    function(){
	// The source, session, and snapshot information are stored
	var browser_source = Controller.findParameter("source");
 	var upload         = Controller.findParameter("id");
	var snapcode       = Controller.findParameter("snapcode");
	var snapname       = Controller.findParameter("snapname");

	if(browser_source != null && upload != null && snapcode != null && name != null){
	    // An asynchronous request loads the snapshot into the browser
	    new Ajax.Request(document.URL, {
		method: 'POST',
		asynchronous:false,
		parameters: {
	  	    action:    'load_snapshot_from_file',
		    snapcode:  snapcode,
		    snapname: snapname,
		    id: upload,
		    browser_source: browser_source,
		},
		onSuccess: function(transport) {
		    $('busy_indicator').show();
		    Controller.setSnapshot(snapname);
		},
		onFailure: function(transport) {
		    alert('failed');
		},
		on504: function() {
		    alert("GBrowse could not find the provided session or snapshot");
		}
	    });
	    location.href=location.href.substr(0,location.href.indexOf('?'));
	}
	
    },

    findParameter:
    function(param, search){
	if(search == null){
		// Searches the URL for the value of the parameter passed in
	   	search = window.location.search.substring(1);
	}
   	if(search.indexOf('&') > -1) {
      		var params = search.split('&');
      		for(var i = 0; i < params.length; i++) {
          		var key_value = params[i].split('=');
          		if(key_value[0] == param) return key_value[1];
      		}
   	} else {
      		var params = search.split('=');
      		if(params[0] == param) return params[1];
   	}
        return null;
 },

 enlarge_image:
  function(image){
	$('large_snapshot').setAttribute('src', image);
	Box.prototype.greyout(true);
	$('enlarge_image').show();
 },

 snapshotExists:
  function(snapshot){
	// If the snapshot exists, the user is prompted to see if they want to overwrite it
	// False is returned if the snapshot does not exist or will be overwritten
	var check = document.getElementById(snapshot);
	
	if (check){
		if(check.style.display == 'none'){
			return false;
		}
		var choice = confirm('A snapshot with the same name has already been saved, would you like to overwrite it?');
		if (choice){
			return false;
		} else {
			return true;
		}
	} else {
		return false;
	}
 },

      /* this code has nothing to do with snapshots
       * but is instead a hack for xyplot overlays
       * disable it for now
 linkTrackLegend:
  function(){
	var subtrack_groups = $$('.subtrack_group');

	subtrack_groups.each(function(subtrack_group) {
		var subtracks = subtrack_group.childElements();
		if(subtracks.size() > 1){
		    subtracks.each(function(subtrack) {
			    var label = subtrack.down().down().innerHTML;
			    var track_div = subtrack.ancestors()[2];
			    var map = track_div.down('map');
			    areas = map.childElements()				 
				areas.each(function(area) {
					var href = area.readAttribute('href');
					href = href.replace(/;/g, "&");
					var param = Controller.findParameter('name', href);
					if(param == label){
					    subtrack.down().href = href.replace(/&/g, ";");
					    area.remove();
					    throw $break;
					}
				    });
			});
		}
	    });
  }
      */

});

