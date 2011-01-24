/** This nice bit of software is used courtesy of the webtoolkit group; the file 
    was renamed to be more informative. It is an alternative to XMLHTTP requests
    that allows for files to be uploaded (which Javascript doesn't).
    
	AJAX IFRAME METHOD (AIM)
	http://www.webtoolkit.info/ajax-file-upload.html
**/

var Ajax_Status_Updater;

AIM = {
	frame: function(c) {
		var n = 'f' + Math.floor(Math.random() * 99999);
		var d = Element.extend(document.createElement('DIV'));
		d.update( new Element("iframe", {src: "about:blank", id: n, name: n}).observe("load", function() { AIM.loaded(n) }).setStyle({display: "none"}));
		document.body.appendChild(d);
 
		if (c && typeof(c.onComplete) == 'function')
			$(n).onComplete = c.onComplete;
		return n;
	},
 	
	form: function(form, name) {
		form.setAttribute('target', name);
	},
 	
	submit: function(form, c) {
		AIM.form(form, AIM.frame(c));
		if (c && typeof(c.onStart) == 'function')
			return c.onStart();
		else
			return true;
	},
 	 
	loaded: function(id) {
		var i = $(id);
		
		if (i.contentDocument)
			var target_document = i.contentDocument;
		else if (i.contentWindow)
			var target_document = i.contentWindow.document;
		else
			var target_document = window.frames[id].document;

		if (target_document.location.href == "about:blank")
			return;
 
		if (typeof(i.onComplete) == 'function')
			i.onComplete(target_document.body.innerHTML);
	}
}

function selectUpload(upload_id) {
    var containers = $$("div[id=" + upload_id + "]");
    if (containers.length == 0) return false;

    if (containers[0].down("div.upload_field")) // We're dealing with an upload field.
		status_selector = "*#" + upload_id + "_status";
	else if(upload_container = $$("div[class~=custom_track][id=" + upload_id + "]")[0])	// We're dealing with an uploaded file in the main listing.
		status_selector = "div[id$='_status']";
	else    // Couldn't find the item, return false.
		return false;
    var status_container = upload_container.down(status_selector);
    return {upload: upload_container, status: status_container};
}

// Visually indicates an upload (whether uploaded already, or in the process of uploading) as "busy".
function showUploadBusy(upload_id, message) {
	message = typeof(message) != 'undefined' ? message : Controller.translate('WORKING');
	var spinner = new Element("img", {src: Controller.button_url('spinner.gif'), alt: Controller.translate('WORKING'), "class": "busy_signal"});
	var containers = selectUpload(upload_id);
	if (!containers) return;
	
	// If it's condensed, just show the spinner. If the details are shown, show the message too.
	if (!containers.upload.down("div.details").visible())
	    containers.upload.down("h1").insert({top: spinner});
	else {
	    containers.status.update();
	    containers.status.insert({bottom: spinner});
	    containers.status.insert({bottom: "&nbsp;"});
	    containers.status.insert({bottom: message});
	    if (!containers.status.visible())
		Effect.BlindDown(containers.status, {duration: 0.25});
	}
	return true;
}

// Clears a busy indicator.
function clearUploadBusy(upload_id) {
    var containers = selectUpload(upload_id);
    var spinner;
    if (spinner = containers.status.down("img.busy_signal"))
    	Effect.BlindUp(containers.status, {duration: 0.25, afterFinish: function() { spinner.remove() } });
    return true;
}

// Displays an error for an upload
function showUploadError(upload_id, message) {
	var error_class = "upload_error";
	message = typeof(message) != 'undefined' ? message : Controller.translate('ERROR');
	var container = selectUpload(upload_id);
	var msg =  new Element("div", {"class": error_class}).setStyle({backgroundColor: "pink", "padding": "5px"});
	msg.insert({bottom: new Element("b").update("Error:") });
	msg.insert({bottom: "&nbsp;" + message + "&nbsp;"});
	var remove_link = new Element("a", {href: "javascript:void(0)"}).update(Controller.translate('REMOVE_MESSAGE'));
	remove_link.observe("click", function() {
	    Effect.BlindUp(container.status, {
	        duration: 0.25, afterFinish: function() {
	            container.status.down("div." + error_class).remove()
	        }
	    })
	});
	msg.insert({bottom: remove_link});
	container.status.update(msg);
	if (!container.status.visible())
		Effect.BlindDown(container.status, {duration: 0.25});
}

// Cleanly removes an element, with a nice blinds-up effect.
function cleanRemove(element, speed) {
    speed = (typeof(speed) != 'undefined')? speed : 0.25;
    Effect.BlindUp(element, {duration: speed, afterFinish: function() { 
		try {
		    element.remove() 
			} catch (e) { } }});
}

// Start AJAX Upload - Sends the AJAX request and sets the busy indicator.
function startAjaxUpload(upload_id) {
	var status       = $(upload_id + '_status');
	var upload_form  = $(upload_id + '_form');
	if ($(upload_form))
	    upload_form.hide();
	
	// Create & insert the status update elements.
	var spinner = Controller.button_url('spinner.gif');
	// var img = new Element('img', {'href': spinner}); // broken in IE; don't know why
	status.update('<img src="'+spinner+'" />');
	status.insert(new Element("span").update(Controller.translate('UPLOADING')));
	var cancel = new Element("a", {href: 'javascript:void(0)'}).update("[" + Controller.translate('CANCEL') + "]");
	cancel.observe("click", function() {
		Controller.cancel_upload(upload_id + "_status", upload_id);
		cleanRemove($(upload_id));
	});
	status.insert({after: cancel});
	status.insert({after: "&nbsp;"});
	
	// This hash stores all currently-loading status updaters.
	if (Ajax_Status_Updater == null)
		Ajax_Status_Updater = new Hash();
	
	var updater = new Ajax.PeriodicalUpdater(
	        status,
		document.URL,
		{	method: 'post',
			frequency: 2,  // Don't set this too low, otherwise the first status request will happen before the uploads hash (in $state) is updated.
			parameters: {
				action: 'upload_status',
				upload_id: upload_id
			},
			onSuccess: function(transport) {
				// If it's worked, stop the PeriodicalUpdater stored in the hash and update the screen.
				if (transport.responseText.match(/complete/)) {
					Ajax_Status_Updater.get(upload_id).stop();
					var sections = new Array(custom_tracks_id, track_listing_id);
					if (using_database())
						sections.push(community_tracks_id);
					Controller.update_sections(sections);
				}
			}
		}
	);
	// Add the PeriodicalUpdater object to the Ajax_Status_Updater hash, so it can be found by onSuccess once it's done.
	Ajax_Status_Updater.set(upload_id, updater);
	return true;
}

// Complete AJAX Upload - Runs the controller to add the track or, if there's an error, displays it.
function completeAjaxUpload(response, upload_id, field_type) {
	var r;
	
	// If any JSON data is available, evaluate it. If not, there's been a Perl error.
	try {
		r = response.evalJSON(true);
	} catch(e) { 
    	r = {
       		success:     false, 
            uploadName: 'Uploaded file',
            error_msg:  Controller.translate('UPLOAD_ERROR')
    	}
    }
    
	if (r.success) {
		var fields = new Array(track_listing_id, custom_tracks_id)
		if (using_database())
			fields.push(community_tracks_id);
		// Add any tracks returned to the Controller.
		if (r.tracks != null && r.tracks.length > 0) {
			Controller.add_tracks(
				r.tracks,
				function() { 
					Controller.update_sections(
						fields,
						'',
						false,
						false,
						function() {
							var updater = Ajax_Status_Updater.get(upload_id);
							if (updater != null)
								updater.stop()
							cleanRemove($(upload_id));
						}
					)
				}
			);
		} else {
			// If no tracks were returned, just stop the updater & remove the upload field.
			var updater = Ajax_Status_Updater.get(upload_id);
			if (updater != null) updater.stop();
			cleanRemove($(upload_id));
		}
	} else {
		// Remove the updater, and display the error returned.
		if (Ajax_Status_Updater.get(upload_id) !=null)
		     Ajax_Status_Updater.get(upload_id).stop();
		Ajax_Status_Updater.unset(upload_id);
		var status = $(upload_id + '_status');
		var msg =  new Element("div").setStyle({"background-color": "pink", "padding": "5px"});
		msg.insert({bottom: new Element("b").update(r.uploadName) });
		msg.insert({bottom: "&nbsp;" + r.error_msg + "&nbsp;"});
		var remove_link = new Element("a", {href: "javascript:void(0)"}).update(Controller.translate('REMOVE_MESSAGE'));
		remove_link.observe("click", function() {
			Effect.BlindUp($(upload_id), {duration: 0.25, afterFinish: function() { $(upload_id).remove() } });
		});
		msg.insert({bottom: remove_link});
		status.update(msg);
	}
	return true;
}

// NOTE: these functions should be migrated to Controller

function deleteUpload(upload_id) {
   showUploadBusy(upload_id, "Deleting...");
   new Ajax.Request(
	   document.URL, {
		    method: 'post',
		    parameters: {
		    	action: 'delete_upload',
				upload_id: upload_id
			},
		    onSuccess: function (transport) {
				var tracks = transport.responseText.evalJSON(true).tracks;
				if (tracks != null)
					tracks.each(function(tid) { Controller.delete_track(tid) });
				var sections = new Array(custom_tracks_id, track_listing_id);
				if (using_database())
					sections.push(community_tracks_id);
				Controller.update_sections(sections);
			}
		}
	);
}

function editUploadData (fileid, sourceFile) {
	editUpload(fileid, sourceFile);
}

function editUploadConf (fileid) {
	editUpload(fileid, 'conf');
}

function editUpload (fileid, sourceFile) {
    var container = selectUpload(fileid);
    var editDiv = container.upload.down("*[id$=_form]").id;
    var editID  = 'edit_' + Math.floor(Math.random() * 99999);
    $(editDiv).hide();
	
    //Add the fields, cancel link and submit button.
    $(editDiv).update("<p><b>" + Controller.translate('EDITING_FILE', sourceFile) + "</b></p>");
    $(editDiv).insert({bottom: new Element("textarea", {id: editID, cols: "120", rows: "20", wrap: "off"}).update(Controller.translate('FETCHING')) });
    $(editDiv).insert({bottom: new Element("p")});
	
    var cancel = new Element("a", {href: "javascript:void(0)"}).update(Controller.translate('CANCEL'))
	cancel.observe("click", function() {
		Effect.BlindUp($(editDiv), {duration: 0.5 })
	    });
    $(editDiv).down("p", 1).update("&nbsp;").insert({bottom: cancel});
	
    var submit = new Element("button").update(Controller.translate('SUBMIT'));
    submit.observe("click", function() {
	    Controller.uploadUserTrackSource(editID, fileid, sourceFile, editDiv);
	});
    $(editDiv).down("p", 1).insert("&nbsp;").insert({bottom: submit });
    
    Effect.BlindDown($(editDiv), {duration: 0.5});
    Controller.downloadUserTrackSource(editID, fileid, sourceFile);
}

function loadURL (fileid, mirrorURL, gothere) {
    var container = new Element('div',{id:fileid});
    $('custom_list_start').insert(container);
    Controller.mirrorTrackSource(mirrorURL, fileid, container, gothere, true);
}

function reloadURL (fileid, mirrorURL) {
    showUploadBusy(fileid, "Reloading...");
    var statusDiv = fileid + "_editfield";
    Controller.mirrorTrackSource(mirrorURL, fileid, statusDiv);
}

function addAnUploadField(after_element, action, upload_prompt, remove_prompt, field_type, help_link) {
	if (field_type == null) field_type = 'upload';
	var upload_tag  = 'upload_' + Math.floor(Math.random() * 99999);
	
	// Create the form and attach the AJAX uploader event.
	var form = new Element("form", {name: "ajax_upload", "id": upload_tag + "_form", action: action, enctype: "multipart/form-data", method: "POST"});
	form.observe("submit", function() {
		AIM.submit(this,
			{
				onStart: function() {
					startAjaxUpload(upload_tag);
				},
				onComplete: function(response) {
					completeAjaxUpload(response, upload_tag, field_type);
				}
			}
		)
	});
	
	// Fill in the appropriate form objects, for file, text, and URL uploads.
	var upload_text = new Element("b").update(upload_prompt);
	if (field_type == 'upload') {
		form.insert({bottom: new Element("input", {type: "hidden", name: "action", value: "upload_file"}) });
		form.insert({bottom: new Element("input", {type: "file", name: "file", id: "upload_field"}) });
		form.insert({bottom: new Element("input", {type: "submit", name: "submit", value: Controller.translate('UPLOAD')}) });
	} else if (field_type == 'edit') {
		form.insert({bottom: new Element("input", {type: "hidden", name: "action", value: "upload_file"}) });
		form.insert({bottom: new Element("input", {type: "hidden", name: "name", value: upload_tag}) });
		form.insert({bottom: new Element("textarea", {name: "data", id: "edit_field", rows: 20, cols: 100, wrap: "off"}) });
		form.insert({bottom: new Element("input", {type: "submit", name: "submit", value: Controller.translate('UPLOAD')}) });
	} else if (field_type=='url') {
		form.insert({bottom: new Element("input", {type: "hidden", name: "action", value: "upload_file"}) });
		form.insert({bottom: new Element("input", {type: "text", name: "mirror_url", size: "100"}) });
		form.insert({bottom: new Element("input", {type: "submit", name: "submit", value: Controller.translate('IMPORT')}) });
	} else {
		form.insert({bottom: new Element("input", {type: "hidden", name: "action", value: "import_track"}) });
		form.insert({bottom: new Element("input", {type: "text", name: "url", id: "import_field", "size": 50}) });
		form.insert({bottom: new Element("input", {type: "submit", name: "submit", value: Controller.translate('IMPORT')}) });
	};
	form.insert({bottom: new Element("input", {type: "hidden", name: "upload_id", value: upload_tag}) });
	form.insert({bottom: "&nbsp;" });
	var remove_link = new Element("a", {href: "javascript:void(0)"}).update(remove_prompt);
	remove_link.observe("click", function() { cleanRemove($(upload_tag)) });
	form.insert({bottom: remove_link});
	if (field_type == "upload") {
		form.insert({bottom: new Element("br")});
		form.insert({bottom: new Element("input", {type: "checkbox", name: "overwrite", id: "overwrite"}) });
		form.insert({bottom: new Element("label", {"for": "overwrite"}).update(Controller.translate('OVERWRITE')) });
	}
	var status_box = new Element("span", {id: upload_tag + "_status", style: "margin-left: 0.5em; margin-right: 0.5em;"});
	
	// Now wrap it in a DIV container and add it to the DOM.
	var count = $$("div[id^=upload_]:not([id$=_status])").length;
	var container = new Element("div").addClassName("upload_field " + field_type);
	container.setStyle({backgroundColor: ((count % 2)? '#AAAAAA' : '#CCCCCC'), "padding": "5px"});
	container.insert({bottom: form}).insert({top: upload_text}).insert({bottom: status_box});
	$(after_element).insert({bottom: container.wrap( new Element("div", {id: upload_tag, style: "display: none;"}) ) });
	Effect.BlindDown($(upload_tag), {duration: 0.25});
}

// Changes the permissions of fileid to sharing_policy.
function changePermissions(fileid, sharing_policy) {
	showUploadBusy(fileid, Controller.translate('CHANGING_PERMISSIONS'));
	var offset = $("community_display_offset").value;
	new Ajax.Request(
		document.URL,
		{
			method: 'post',
			parameters: {
				action: 'change_permissions',
				fileid: fileid,
				sharing_policy: sharing_policy
			},
			onSuccess: function (transport) {
				var sections = new Array(custom_tracks_id);
				if (using_database())
					sections.push(community_tracks_id);
				Controller.update_sections(sections, "&offset=" + offset);
				if ($('autocomplete_upload_filter') != null)  initAutocomplete();
			}
		}
	);
}

// Shares a file with the specific userid (or the logged-in user, if userid is blank). A front-end to UserTracks::share().
function shareFile(fileid, userid) {
	showUploadBusy(fileid, Controller.translate('ADDING'));
	var offset = $("community_display_offset").value;
	new Ajax.Request(
		document.URL,
		{
			method: 'post',
			parameters: {
				action: 'share_file',
				fileid: fileid,
				userid: userid
			},
			onSuccess: function (transport) {
				var sections = new Array(custom_tracks_id, track_listing_id);
				if (using_database())
					sections.push(community_tracks_id);
				Controller.update_sections(sections, "&offset=" + offset);
				var tracks = transport.responseText.evalJSON(true).tracks;
				if (tracks != null) {
					Controller.add_tracks(tracks);
					tracks.each(function(tid) { ShowHideTrack(tid, 1)});
			    }
			}
		}
	);
}

// Unshares a file with the specific userid (or the logged-in user, if userid is blank). A front-end to UserTracks::unshare().
function unshareFile(fileid, userid) {
	showUploadBusy(fileid, Controller.translate('REMOVING'));
	var offset = $("community_display_offset").value;
	new Ajax.Request(
		document.URL,
		{
			method: 'post',
			parameters: {
				action: 'unshare_file',
				fileid: fileid,
				userid: userid
			},
			onSuccess: function (transport) {
				var sections = new Array(custom_tracks_id, track_listing_id);
				if (using_database())
					sections.push(community_tracks_id);
				Controller.update_sections(sections, "&offset=" + offset);
				var tracks = transport.responseText.evalJSON(true).tracks;
				if (tracks != null)
					tracks.each(function(tid) { Controller.delete_tracks(tid) });
			}
		}
	);
}

// Updates the public file listing. If given, searches by keyword or provides and offset.
function searchPublic(keyword, offset) {
	Controller.busy();
	new Ajax.Request(
		document.URL,
		{
			method: 'post',
			parameters: {
				action: 'update_sections',
				section_names: community_tracks_id,
				keyword: keyword,
				offset: offset
			},
			onSuccess: function (transport) {
				var html = transport.responseText.evalJSON(true).section_html[community_tracks_id];
				$(community_tracks_id).update(html);
				Controller.idle();
				if ($('autocomplete_upload_filter') != null)  initAutocomplete();
				$("public_search_keyword").focus()
			}
		}
	);
	return false; // This is necessary to stop the form from submitting. Make sure the onSubmit event returns the value of this function.
}

// Looks up the upload ID of the file that contains a track, so it can be shared.
function trackLookup(track) {
	new Ajax.Request(
		document.URL,
		{
			method: 'post',
			parameters: {
				action: 'track_lookup',
				track: track
			},
			onSuccess: function (transport) {
				console.log(transport.responseText);
			}
		}
	);
}
