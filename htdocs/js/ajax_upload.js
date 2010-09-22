/** This nice bit of software is used courtesy of the webtoolkit group; the file 
    was renamed to be more informative.
    
	AJAX IFRAME METHOD (AIM)
	http://www.webtoolkit.info/
**/

var Ajax_Status_Updater;

//AIM is an object which
AIM = {
	frame: function(c) {
		var n = 'f' + Math.floor(Math.random() * 99999);
		var d = document.createElement('DIV');
		d.innerHTML = '<iframe style="display:none" src="about:blank" id="' + n + '" name="' + n + '" onload="AIM.loaded(\'' + n + '\')"></iframe>';
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

// Start AJAX Upload - Sends the AJAX request and sets the busy indicator.
function startAjaxUpload(upload_id) {
	var status       = $(upload_id + '_status');
	var upload_form  = $(upload_id + '_form');
	upload_form.hide();

	status.update(new Element("img", {href: Controller.button_url('spinner.gif')}) );
	status.insert(new Element('span').update('<b>Uploading...</b>'));
	status.insert(new Element('a', {href: 'javascript:void(0)', onClick: "Controller.cancel_upload(\"" + upload_id + "_status\", \"" + upload_id + "\")" }).update(' Cancel'));

	if (Ajax_Status_Updater == null)
		Ajax_Status_Updater = new Hash();
		
	var updater = new Ajax.PeriodicalUpdater(
		{success: status.down('span')},
		'#',
		{	parameters: {
				action: 'upload_status',
				upload_id: upload_id
			},
			onSuccess: function(transport) {
				if (transport.responseText.match(/complete/)) {
					Ajax_Status_Updater.get(upload_id).stop();
					var sections = new Array(custom_tracks_id);
					if (using_database())
						sections.push(public_tracks_id);
					Controller.update_sections(sections);
				}
			}
		}
	);
	Ajax_Status_Updater.set(upload_id, updater);
	return true;
}

// Complete AJAX Upload - Runs the controller to add the track or, if there's an error, displays it.
function completeAjaxUpload(response, upload_id, field_type) {
	var r;
	try {
		r = response.evalJSON(true);
	} catch(e) { 
       r = {success:     false, 
            uploadName: 'Uploaded file',
            error_msg:  'The server returned an error during upload'
    	}
    }
    
	if (r.success) {
		var fields = new Array(track_listing_id, custom_tracks_id)
		if (using_database())
			fields.push(public_tracks_id);
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
							$(upload_id).remove();
						}
					)
				}
			);
		} else {
			var updater = Ajax_Status_Updater.get(upload_id);
			if (updater != null) updater.stop();
			$(upload_id).remove();
		}
	} else {
		if (Ajax_Status_Updater.get(upload_id) !=null)
		     Ajax_Status_Updater.get(upload_id).stop();
		Ajax_Status_Updater.unset(upload_id);
		var status = $(upload_id + '_status');
		var msg =  new Element("div").setStyle({"background-color": "pink", "padding": "5px"});
		msg.insert({bottom: new Element("b").update(r.uploadName) });
		msg.insert({bottom: "&nbsp;" + r.error_msg + "&nbsp;"});
		msg.insert({bottom: new Element("a", {href: "javascript:void(0)", onClick: "$('" + upload_id + "').remove()"}).update("[Remove Message]") });
		status.update(msg);
	}
return true;
}

// NOTE: these functions should be migrated to Controller

function deleteUpload (fileName) {
   var indicator = fileName + "_stat";
   $(indicator).innerHTML = '<image src="' + Controller.button_url('spinner.gif') + '" />';
   new Ajax.Request(
	   document.URL, {
		    method: 'post',
		    parameters: {
		    	action: 'delete_upload',
				file:  fileName
			},
		    onSuccess: function (transport) {
				var tracks = transport.responseJSON.tracks;
				if (tracks != null)
					tracks.each(function(tid) { Controller.delete_track(tid) });
				var sections = new Array(custom_tracks_id, track_listing_id);
				if (using_database())
					sections.push(public_tracks_id);
				Controller.update_sections(sections);
			}
		}
	);
}

function editUploadData (fileName,sourceFile) {
	editUpload(fileName,sourceFile);
}

function editUploadConf (fileName) {
	editUpload(fileName,'conf');
}

function editUpload (fileName,sourceFile) {
	var editDiv = fileName + "_editfield";
	var editID  = 'edit_' + Math.floor(Math.random() * 99999);
	$(editDiv).innerHTML = '<p><b>Editing ' + sourceFile + '</b></p>'
	+ '<textarea id="' + editID + '" cols="120" rows="20" wrap="off">fetching...</textarea>'
	+ '<p>'
	+ '<a href="javascript:void(0)" onClick="' + '$(\'' + editDiv + '\').innerHTML=\'\'">[Cancel]</a>'
	+ '<button onClick="Controller.uploadUserTrackSource(\''+ editID + '\',' + '\'' + fileName +'\',' + '\'' + sourceFile +'\',' + '\'' + editDiv +'\')">Submit</button>'
	+ '</p>';
	Controller.downloadUserTrackSource(editID,fileName,sourceFile);
}

function addAnUploadField(after_element, action, upload_prompt, remove_prompt, field_type, help_link) {
	if (field_type == null) field_type = 'upload';
	var upload_tag  = 'upload_' + Math.floor(Math.random() * 99999);
	var script      = 'return AIM.submit(this,{onStart:  function() {';
	script         += 'startAjaxUpload(\''+upload_tag+'\')';
	script         += '},';
	script         += 'onComplete: function(response) {'
	script         += 'completeAjaxUpload(response,\''+upload_tag+'\',\''+field_type+'\')';
	script         += '}})';

	var count = $$("div[id^=upload_]:not([id$=_status])").length;
	var form = new Element("form", {"name": "ajax_upload", "id": upload_tag + "_form", "onSubmit": script, "action": action, "enctype": "multipart/form-data", "method": "POST"});
	var upload_text = new Element("b").update(upload_prompt);
	if (field_type == 'upload') {
		form.insert({bottom: new Element("input", {"type": "hidden", "name": action, "value": "upload_file"}) });
		form.insert({bottom: new Element("input", {"type": "file", "name": "file", "id": "upload_field"}) });
	} else if (field_type == 'edit') {
		form.insert({bottom: new Element("input", {"type": "hidden", "name": action, "value": "upload_file"}) });
		form.insert({bottom: new Element("input", {"type": "hidden", "name": "name", "value": upload_tag}) });
		form.insert({bottom: new Element("textarea", {"name": "data", "id": "edit_field", "rows": 20, "cols": 100, "wrap": "off"}) });
	} else {
		form.insert({bottom: new Element("input", {"type": "hidden", "name": action, "value": "import_track"}) });
		form.insert({bottom: new Element("input", {"type": "text", "name": "url", "id": "import_field", "size": 50}) });
	};
	form.insert({bottom: new Element("input", {"type": "submit", "name": "submit", "value": "Upload"}) });
	form.insert({bottom: new Element("input", {"type": "hidden", "name": "upload_id", "value": upload_tag}) });
	form.insert({bottom: "&nbsp;" });
	form.insert({bottom: new Element("a", {"href": "javascript:void(0)", "onClick": "Element.extend(this);this.up(\'div\').remove()"}).update(remove_prompt) });
	var status_box = new Element("div", {"id": upload_tag + "_status"});
	
	var container = new Element("div", {id: upload_tag});
	container.setStyle({"background-color": ((count % 2)? '#AAAAAA' : '#CCCCCC'), "padding": "5px"});
	container.insert({bottom: form}).insert({top: upload_text}).insert({bottom: status_box});
	$(after_element).insert({bottom: container});
}

function changePermissions(fileid, sharing_policy) {
	var title = $("upload_" + fileid).down("div[id$='_stat']");
	if (title)
		title.innerHTML = '<img src="' + Controller.button_url('spinner.gif') + '" />';
	new Ajax.Request(
		document.URL, {
			method: 'post',
			parameters: {
				action: 'change_permissions',
				fileid: fileid,
				sharing_policy: sharing_policy
			},
			onSuccess: function (transport) {
				var sections = new Array(custom_tracks_id);
				if (using_database())
					sections.push(public_tracks_id);
				Controller.update_sections(sections);
			}
		}
	);
}

function shareFile(fileid, userid) {
	var title = $("upload_" + fileid);
	if (title)
		title.down("div[id$='_stat']").innerHTML = '<img src="' + Controller.button_url('spinner.gif') + '" />';
	new Ajax.Request(
		document.URL, {
			method: 'post',
			parameters: {
				action: 'share_file',
				fileid: fileid,
				userid: userid
			},
			onSuccess: function (transport) {
				var sections = new Array(custom_tracks_id);
				console.log(using_database());
				if (using_database())
					sections.push(public_tracks_id);
				Controller.update_sections(sections);
			}
		}
	);
}

function unshareFile(fileid, userid) {
	var title = $("upload_" + fileid);
	if (title)
		title.down("div[id$='_stat']").innerHTML = '<img src="' + Controller.button_url('spinner.gif') + '" />';
	new Ajax.Request(
		document.URL, {
			method: 'post',
			parameters: {
				action: 'unshare_file',
				fileid: fileid,
				userid: userid
			},
			onSuccess: function (transport) {
				var sections = new Array(custom_tracks_id);
				if (using_database())
					sections.push(public_tracks_id);
				Controller.update_sections(sections);
			}
		}
	);
}
