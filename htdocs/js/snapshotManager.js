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
  		        action:    'delete_session',
  			name: snapshot,

  	          }});

	// Removes the snapshot from the pages title if it was the last one set
	if($('snapshot_page_title').innerHTML == 'Snapshot : ' + snapshot){
		$('snapshot_page_title').innerHTML = 'Snapshot : ';
		$('snapshot_page_title').hide();
	}
   
 },
				     
  saveSnapshot:
  function(){

 	var sessionName = $('snapshot_name').value;
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
  			        action:    'save_session',
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
  		        action: 'set_session',
  			name: sessionName,
  	          },
		  onSuccess: function(transport) {
			// The array of selected tracks is stored
			active = transport.responseJSON.toString();
			active = active.split(",");
			
			// The various sections of the browser affected when a session is changed are updated
			var sections = new Array(track_listing_id, page_title_id, custom_tracks_id, community_tracks_id, search_form_objects_id, snapshot_table_id);
			Controller.update_sections(sections); 	
		  }
	});
	// A timeout is used to ensure that the sections are updated before further changes are made
	setTimeout(function(){

		Sortable.create('snapshotTable',{tag:'div',only:'draggable'});	

		// All the children of the tracks_panel are stored
		var children = $A($("tracks_panel").descendants());

		// Each child that is active, is added to the active children array, and inactive children are removed from the track listing
		children.each(function(child) {
			var track_name = child.id.substring(0, (child.id.length - 6));
			// All tracks are initially deleted (and unregistered)
			Controller.delete_track(track_name);
		});	

		// The tracks are added and browser is refreshed.
		Controller.add_tracks(active,function(){Controller.refresh_tracks(true);}, true);
		
		// The busy indicator is removed after all actions have been completed
		setTimeout(function(){
			$('busy_indicator').hide();

			// The title is updated to reflect the new snapshot that has been set
			//$('snapshot_page_title').update('Snapshot : ' + sessionName);
			//$('snapshot_page_title').style.color = 'navy';
			Controller.select_tab('main_page')
			$('snapshot_page_title').hide();
			}, 2000)
			     },2000)
  },

  sendSnapshot:
  function(snapshot){

	// The snapshot code to be sent is initially set to ''
  	var snapshot_url = '';

	// Only one send snapshot_box is open at a time
  	var send_snapshot_boxes = $$('.send_snapshot');
  	send_snapshot_boxes.each(function(box){
		box.style.display = "none";
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
  		        action:    'send_session',
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
  		        action:    'mail_session',
  			email: 	   email,
			name:  snapshot,
			url:   document.location.href,
  	          },
		  onSuccess: function(transport) {
                  	$('busy_indicator').hide();
		  }
            });
  },

 checkSnapshot:
  function(){
	// The source, session, and snapshot information are stored
	var browser_source = Controller.findParameter("source");
 	var session = Controller.findParameter("id");
	var snapshot = Controller.findParameter("snapshot");
	
	if(browser_source != null && session != null && snapshot != null){
		// An asynchronous request loads the snapshot into the browser
	 	new Ajax.Request(document.URL, {
	  	          method: 'POST',
	  		  asynchronous:true,
	  		  parameters: {
	  		        action:    'load_url',
				name:  snapshot,
				id: session,
				browser_source: browser_source,
	  	          },
			  onSuccess: function(transport) {
		          	$('busy_indicator').show();
				Controller.setSnapshot(snapshot);
			  },
			  on504: function() {
				alert("GBrowse could not find the provided session or snapshot");
			  }
		    });
	}
	

  },

 findParameter:
  function(param){
	// Searches the URL for the value of the parameter passed in
   	var search = window.location.search.substring(1);
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
 }

});

