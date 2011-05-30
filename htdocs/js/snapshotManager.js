// snapshotManager.js
// *** Snapshot functions ***

GBrowseController.addMethods({
 hide_snapshot_prompt:
 function(){
   	$('save_snapshot').hide();
  },
				     
 submitWithEnter: 
 function(e){

   	var sessionName = document.getElementById('snapshot_name').value;
   	
	// Store the value of the key entered
     	if (!e) var e = window.event;
      	if (e.keyCode) code = e.keyCode;
      	else if (e.which) code = e.which;

 	// If the user presses enter, the snapshot is saved
      	if (code==13) {
		Controller.hide_snapshot_prompt();
	
		Controller.saveSnapshot('snapshot_name')

	    	     } 	
 },
				     
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
	if($('snapshot_page_title').innerHTML == 'Current Snapshot : ' + snapshot){
		$('snapshot_page_title').innerHTML = 'Current Snapshot : ';
		$('snapshot_page_title').hide();
	}
   
 },
				     
  saveSnapshot:
  function(textFieldId){

 	var sessionName = document.getElementById(textFieldId).value;

	// If a value was entered for the name of the snapshot then it is saved
 	if(sessionName){
		// An asynchronous request is made to save a snapshot of the session
 		new Ajax.Request(document.URL, {
  	        	  method: 'POST',
  			  asynchronous:true,
  			  parameters: {
  			        action:    'save_session',
  				name: sessionName,
  	        	  }});

		// The page title is updated to reflect the current snapshot
		$('snapshot_page_title').innerHTML = 'Current Snapshot : ' + sessionName;
		$('snapshot_page_title').show();

		$('busy_indicator').show();

		// A timer is used to ensure that the snapshot table is recreated only after the information has been updated
		setTimeout(function(){

			// The snapshot table is updated
			var sections = new Array(snapshot_table_id);
			Controller.update_sections(sections); 	

			// Another timeout is used to end the busy indicator after the table has been created	
			setTimeout(function(){
				Sortable.create('snapshotTable',{tag:'div',only:'draggable'});	
				$('busy_indicator').hide();		
				    	     },1500)	
				     },2500)
	}

  },	
			     		     				     				 				     
 setSnapshot:
 function(sessionName){

	// A request is made to update the current session
 	new Ajax.Request(document.URL, {
  	          method: 'POST',
  		  asynchronous:false,
  		  parameters: {
  		        action: 'set_session',
  			name: sessionName,
  	          },
		  onSuccess: function(transport) {
			// The various sections of the browser affected when a session is changed are updated
			var sections = new Array(track_listing_id, page_title_id, custom_tracks_id, community_tracks_id, search_form_objects_id, snapshot_table_id);
			Controller.update_sections(sections); 	
		  }
	});
	
	$('busy_indicator').show();
	
	// A timeout is used to ensure that the sections are updated before further changes are made
	setTimeout(function(){

		Sortable.create('snapshotTable',{tag:'div',only:'draggable'});	

		// All the children of the tracks_panel are stored
		var children = $A($("tracks_panel").descendants());
		var active_children = new Array(); 

		// Each child that is active, is added to the active children array, and inactive children are removed from the track listing
		children.each(function(child) {
			var track_name = child.id.substring(0, (child.id.length - 6));

			if(child.className == 'track_title activeTrack'){
			 	active_children.push(track_name);
			}else if(child.className == 'track_title'){
				// Toggles the tracks on or off as they're selected
				Controller.delete_track(track_name);
			}
		});	

		// The tracks are added and browser is refreshed.
		Controller.add_tracks(active_children,function(){Controller.update_coordinates("reload segment");}, true);
		
		// The title is updated to reflect the new snapshot that has been set
		$('snapshot_page_title').innerHTML = 'Current Snapshot : ' + sessionName;
		$('snapshot_page_title').show();	

		// The busy indicator is removed after all actions have been completed
		setTimeout(function(){
			$('busy_indicator').hide();
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
  			name: 	snapshot
  	          },
		  onSuccess: function(transport) {
			// Upon success, the snapshot code is output to the user for copying
                  	var results      = transport.responseText;
			$('send_snapshot_url_' + snapshot).innerHTML = results;
		  }
            });
  },

  hideSendSnapshot:
  function(snapshot){

	$('send_snapshot_' + snapshot).hide();	

  },

  loadSnapshot:
  function(){
	
	// The snapshot name and code are stored for later use. ERROR CHECKING NEEDED HERE.
 	var load_name = $('load_snapshot_name').value;
  	var load_snapshot = $('load_snapshot_code').value;
  
  	$('load_snapshot').hide();
  	$('busy_indicator').show();

	// An asynchronous request is made to add the snapshot to the current session
 	new Ajax.Request(document.URL, {
  	          method: 'POST',
  		  asynchronous:true,
  		  parameters: {
  		        action:    'load_session',
  			name: 	load_name,
			snapshot:	load_snapshot,
  	          },
		  onSuccess: function(transport) {
			// The loaded session is set to be the current session
			setSnapshot(load_name);
                  	$('busy_indicator').hide();
		  }
            });
  },

});

